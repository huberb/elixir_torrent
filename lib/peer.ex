defmodule Torrent.Peer do

  def connect(peer_struct) do 

    { ip, port } = peer_struct[:peer]

    IO.puts ip
    IO.puts port

    case connect(ip, port) do
      { :ok, socket } ->
        socket 
        |> initiate_connection(peer_struct[:info_hash])

      { :error, e } ->
        e
    end
  end

  defp connect(ip, port) do
    try do
      socket = Socket.TCP.connect!(ip, port, packet: :line) 
      { :ok, socket }
    rescue
      e -> { :error, e }
    end
  end

  def initiate_connection(socket, info_hash) do
    socket 
    |> say_hello(info_hash) 
    |> hear_hello
    |> verify_checksum(info_hash)
  end

  def verify_checksum(answer_struct, info_hash) do
    real_hash = info_hash |> Bencoder.encode |> sha_sum
    if answer_struct != real_hash do
      raise "Wrong Checksum! Abort!"
    else
      answer_struct
    end
  end

  def say_hello(socket, info_hash) do
    IO.puts "init handshake: "
    handshake = info_hash
                |> Bencoder.encode
                |> sha_sum
                |> generate_handshake
    socket |> Socket.Stream.send!(handshake)
    socket
  end

  def try_to_understand_the_dude(message) do

  end

  def hear_hello(socket) do 
    socket |> Socket.packet! :raw
    { :ok, message } = socket |> Socket.Stream.recv(1)
    request_length = message |> :binary.bin_to_list |> Enum.at(0)

    answer = %{
      pstrlen: request_length,
      pstr: socket |> Socket.Stream.recv(request_length),
      placeholder: socket |> Socket.Stream.recv(8),
      info_hash: socket |> Socket.Stream.recv(20),
      peer_id: socket |> Socket.Stream.recv(20)
    }
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
