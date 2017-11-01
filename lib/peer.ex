defmodule Torrent.Peer do

  def connect(info_structs) do 
    { ip, port } = info_structs[:peer]

    { :ok, pid } = Task.start_link fn -> 
      connect(ip, port)
      |> initiate_connection(info_structs)
    end
    pid
  end

  defp connect(ip, port, count \\ 0) do
    IO.puts "Try to connect to: " <> ip
    try do
      Socket.TCP.connect!(ip, port, [timeout: 1000]) 
    rescue
      e ->
        if e.message == "timeout" do
          IO.puts "got a Timeout on IP: " <> ip
          if count == 5 do
            IO.puts "fifth try on IP " <> ip <> " ... stopping now!"
            exit(:normal)
          else
            connect(ip, port, count + 1)
          end
        else
          exit(:normal)
        end
    end
  end

  def initiate_connection(socket, info_structs) do
    answer = socket 
           |> say_hello(info_structs[:meta_info]) 
           |> hear_hello
           |> verify_checksum(info_structs[:meta_info])

    info_structs = info_structs |> Map.put(:peer_id, answer[:peer_id])
    socket |> Torrent.Stream.leech(info_structs)
  end

  def verify_checksum(answer_struct, meta_info) do
    real_hash = meta_info["info"] |> Bencoder.encode |> Torrent.Parser.sha_sum
    foreign_hash = answer_struct[:info_hash]
    if foreign_hash != real_hash do
      exit(:wrong_checksum)
    else
      IO.puts "handshake successful"
      answer_struct
    end
  end

  def say_hello(socket, meta_info) do
    handshake = meta_info["info"]
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
      pstr: socket |> Socket.Stream.recv!(request_length),
      placeholder: socket |> Socket.Stream.recv!(8),
      info_hash: socket |> Socket.Stream.recv!(20),
      peer_id: socket |> Socket.Stream.recv!(20)
    }
  end

  defp generate_handshake(sha_info_hash) do
    # The Number 19 followed by the Protocol String
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
