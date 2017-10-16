defmodule Torrent.Peer do

  def connect(peer_struct) do 

    { ip, port } = peer_struct[:peer]

    IO.puts ip

    try do
      socket = Socket.TCP.connect!(ip, port, packet: :line) 
      socket |> say_hello(peer_struct[:info_hash])
    rescue
      e -> IO.puts(e.message)
        if e.message != "host is unreachable" do
          raise e
        end
    end

  end

  def say_hello(socket, info_hash) do
    IO.puts "init handshake: "
    sha_info_hash = info_hash
                    |> Bencoder.encode
                    |> sha_sum

    handshake = sha_info_hash 
                |> generate_handshake
    socket |> Socket.Stream.send!(handshake)
    socket |> Socket.Stream.recv! |> hear_hello
  end

  def hear_hello(message) do 
    require IEx
    IEx.pry
    start_talking
  end

  def start_talking do
  end

  defp sha_sum(binary) do
    :crypto.hash(:sha, binary)
  end

  defp generate_handshake(sha_info_hash) do
    # The Number 19 in Binary followed by the Protocol String
    << 19, "BitTorrent protocol" :: binary >> <>
      # add 8 Zeros and the SHA Hash from the Tracker info, 20 Bytes long
    << 0, 0, 0, 0, 0, 0, 0, 0, sha_info_hash :: binary, >> <>
      # some Peer ID, also 20 Bytes long
    << generate_peer_id :: binary >>
  end


  defp generate_peer_id do
    # TODO: generate better Peer_id
    id = "BE"
    version = "0044"
    :random.seed(:erlang.now)
    number = :random.uniform(1000000000000)
    number = number |> Integer.to_string |> String.rjust(13, ?0)
    "-#{id}#{version}#{number}"
  end


end
