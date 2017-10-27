defmodule Torrent.Peer do

  def connect(peer_struct) do 

    { ip, port } = peer_struct[:peer]

    case connect(ip, port) do
      { :ok, socket } ->
        socket 
        |> initiate_connection(peer_struct[:info_hash])

      { :error, e } ->
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

  def initiate_connection(socket, info_hash) do
    socket 
    |> say_hello(info_hash) 
    |> hear_hello
    |> verify_checksum(info_hash)
    |> set_bitfield(socket)
  end

  def set_bitfield(answer_struct, socket) do
    IO.puts "setting bitfield"

    # for some reason we need to pull 3 empty bytes
    # the 4th byte is a length param
    { :ok, message } = socket |> Socket.Stream.recv(4)
    len = message |> :binary.bin_to_list |> List.last
    IO.puts "recv length: "
    IO.puts len

    # now pull one more byte
    # this is the state
    { :ok, message } = socket |> Socket.Stream.recv(1)
    state = message |> :binary.bin_to_list |> Enum.at(0)
    IO.puts "recv state: "
    IO.puts state

    # TODO: struct for all flags
    if state == 5 do # bitfield flag set
      IO.puts "got a valid Bitfield Flag."
      # TODO: find out what this values do
      # if we got a bitfield, we pull length - 1 bytes
      { :ok, bitstring } = socket |> Socket.Stream.recv(len - 1)
      # need the bitstring in binary?
      binary_list = bitstring 
                    |> :binary.bin_to_list 
                    |> Enum.map(fn(b) -> Integer.to_string(b, 2) end)

      IO.puts "got a bitstring: "
      # TODO: do something with this
      IO.puts binary_list

      socket |> Torrent.Stream.recv
    else
      IO.puts "Bitfield Flag not set, Abort!"
      raise "Bitfield Flag not set on Peer"
    end

  end

  def verify_checksum(answer_struct, info_hash) do
    real_hash = info_hash |> Bencoder.encode |> sha_sum
    { :ok, foreign_hash } = answer_struct[:info_hash]
    if foreign_hash != real_hash do
      raise "Wrong Checksum! Abort!"
    else
      IO.puts "handshake successful"
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
