defmodule Torrent.Peer do

  def connect(info_structs) do 

    { ip, port } = info_structs[:peer]

    case connect(ip, port) do
      { :ok, socket } ->
        socket |> initiate_connection(info_structs)

      { :error, e } ->
        # TODO: handle this error
        raise e
    end
  end

  defp connect(ip, port) do
    IO.puts "Try to connect to: " <> ip
    try do
      socket = Socket.TCP.connect!(ip, port, [timeout: 2000]) 
      { :ok, socket }
    rescue
      e ->
        if e.message == "timeout" do
          IO.puts "got a Timeout.. try again"
          connect(ip, port)
        else
          { :error, e }
        end
    end
  end

  def initiate_connection(socket, info_structs) do
    socket 
    |> say_hello(info_structs[:meta_info]) 
    |> hear_hello
    |> verify_checksum(info_structs[:meta_info])

    writer_process = info_structs[:writer_pid]

    socket |> Torrent.Stream.leech(writer_process, info_structs[:meta_info])
  end

  def verify_checksum(answer_struct, info_hash) do
    real_hash = info_hash |> Bencoder.encode |> Torrent.Parser.sha_sum
    { :ok, foreign_hash } = answer_struct[:info_hash]
    if foreign_hash != real_hash do
      raise "Wrong Checksum! Abort!"
    else
      IO.puts "handshake successful"
    end
  end

  def say_hello(socket, info_hash) do
    handshake = info_hash
                |> Bencoder.encode
                |> Torrent.Parser.sha_sum
                |> generate_handshake
    socket |> Socket.Stream.send!(handshake)
    socket
  end

  def hear_hello(socket) do 
    socket |> Socket.packet!(:raw)
    { :ok, message } = socket |> Socket.Stream.recv(1)
    request_length = message |> :binary.bin_to_list |> Enum.at(0)

    %{
      pstrlen: request_length,
      pstr: socket |> Socket.Stream.recv(request_length),
      placeholder: socket |> Socket.Stream.recv(8),
      info_hash: socket |> Socket.Stream.recv(20),
      peer_id: socket |> Socket.Stream.recv(20)
    }
  end

  defp generate_handshake(sha_info_hash) do
    # The Number 19 in Binary followed by the Protocol String
    << 19, "BitTorrent protocol" :: binary >> <>
    # add 8 Zeros and the SHA Hash from the Tracker info, 20 Bytes long
    << 0, 0, 0, 0, 0, 0, 0, 0, sha_info_hash :: binary, >> <>
    # some Peer ID, also 20 Bytes long
    << generate_peer_id() :: binary >>
  end

  def generate_peer_id do
    # TODO: generate better Peer_id
    id = "BE"
    version = "0044"
    :random.seed(:erlang.now)
    number = :random.uniform(1000000000000)
    number = number |> Integer.to_string |> String.rjust(13, ?0)
    "-#{id}#{version}#{number}"
  end

end
