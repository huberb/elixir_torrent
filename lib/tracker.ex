defmodule Torrent.Tracker do

  @action_ids [
    :connect,
    :announce,
    :scrape,
    :error
  ]

  def index(list, value) do
    Enum.find_index(list, &(&1 == value))
  end

  def start_link(torrent) do
    peers = ask_for_peers(torrent, 0)
    { _, pid } = Task.start_link(fn ->
      serve_peers(torrent)
    end)
    { pid, peers }
  end

  def ask_for_peers(torrent, received) do
    IO.puts "tracker query"
    cond do 
      String.starts_with?(torrent[:announce], "http") ->
        HTTPoison.start
        tcp_request(torrent, received)
      String.starts_with?(torrent[:announce], "udp") ->
        udp_request(torrent)
      true ->
        raise "this is no announce url"
    end
  end

  def serve_peers(torrent) do
    # wait for request cycle
    :timer.sleep 30000
    # tell writer we need info
    send :writer, { :tracker }
    # receive info
    response = 
      receive do
        { :received, num } ->
          ask_for_peers(torrent, num)
      end
    send :client, { :tracker, response }
    serve_peers(torrent)
  end

  def udp_request(torrent) do
    [ query, port ] = String.replace_prefix(torrent[:announce], "udp://", "")
                      |> String.split(":")

    port = String.to_integer(port)
    req = udp_query_for_connection_ip()
    udp_socket = Socket.UDP.open!(port)
    tracker = { query, port }
    Socket.Datagram.send(udp_socket, req, tracker)
    conn_id = recv_connection_id(udp_socket)
    udp_announce(udp_socket, conn_id, tracker, torrent[:hash])
  end

  def tcp_request(torrent, received) do
    query = tcp_query torrent, received
    case HTTPoison.get(query, [], [follow_redirect: true]) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        Bento.decode!(body) |> Torrent.Parser.keys_to_atom

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        IO.puts "Tracker not found :("
        raise "404"

      {:error, %HTTPoison.Error{reason: reason}} ->
        IO.inspect reason
        raise "TrackerError"
    end
  end

  def udp_announce(udp_socket, conn_id, tracker, hash) do
    trans_id = transaction_id()
    req = udp_announce_packet(conn_id, hash, trans_id)
    Socket.Datagram.send(udp_socket, req, tracker)

    << action :: 32, transaction_id :: 32, interval :: 32, leechers :: 32, seeders :: 32, peers :: binary >>
    = Socket.Datagram.recv!(udp_socket) |> elem(0)

    unless Enum.at(@action_ids, action) == :announce do
      raise "wrong action id on tracker request"
    end
    unless trans_id == transaction_id do
      raise "wrong transaction id on tracker request"
    end
    %{ peers: peers }
  end

  def udp_announce_packet(conn_id, info_hash, trans_id) do
    downloaded = 0
    uploaded = 0
    left = 10000

    conn_id
    <> << index(@action_ids, :announce) :: 32 >> # action
    <> << trans_id :: 32 >>
    <> info_hash
    <> Torrent.Peer.generate_peer_id()
    <> << downloaded :: 64 >>
    <> << left :: 64 >>
    <> << uploaded :: 64 >>
    <> << 0 :: 32 >> # event
    <> << 0 :: 32 >> # ip
    <> << 0 :: 32 >> # key
    <> << -1 :: 32 >> # num_want
    <> << 6881 :: 16 >> # port
  end

  def transaction_id do
    :math.pow(2, 32) |> trunc |> :rand.uniform()
  end

  def recv_connection_id(udp_socket) do
    data = Socket.Datagram.recv!(udp_socket) |> elem(0)
    # action, transaction_id, connection_id
    << action :: size(32), _ :: size(32), connection_id :: binary >> = data
    unless Enum.at(@action_ids, action) == :connect do
      raise "wrong action id on tracker request"
    end
    connection_id
  end

  defp udp_query_for_connection_ip do
    # hard coded protocol id
    << 0x41727101980 :: 64 >>
    # action id
    <> << index(@action_ids, :connect) :: 32 >>
    # transaction id, random value
    <> << transaction_id :: 32 >>
  end

  defp tcp_query(torrent_info, received) do
    info_hash = torrent_info[:hash]

    # TODO: less hardcode
    query = %{
      "info_hash"  => info_hash,
      "port"       => 6881,
      "peer_id"    => 78742315344684734465,
      "uploaded"   => 0,
      "downloaded" => received,
      "event"      => "started",
      "left"       => 10000,
      "compact"    => 1,
      "no_peer_id" => 0,
      "event"      => "started"
    } |> URI.encode_query

    torrent_info[:announce] <> "?" <> query
  end

end
