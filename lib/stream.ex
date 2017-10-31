defmodule Torrent.Stream do

  def leech(socket, info_structs) do
    socket |> send_interested
    |> pipe_message(info_structs)
  end

  def send_interested(socket) do
    # len 1, id 2
    message = [0,0,0,1,2] |> :binary.list_to_bin
    socket |> Socket.Stream.send!(message)
    IO.puts "send interested message"
    socket
  end

  def piece(socket, len, info_structs) do
    info_hash = info_structs[:meta_info]["info"]
    index = socket |> recv_32_bit_int
    block = %{
      from_peer: info_structs[:peer_id],
      len: len,
      offset: socket |> recv_32_bit_int,
      data: socket |> recv_byte!(len - 9)
    }

    # Torrent.Parser.validate_data(info_hash["pieces"], index, block)
    send info_structs[:writer_pid], { :put, block, index }
    pipe_message(socket, info_structs)
  end

  def bitfield(socket, len, info_structs) do
    peer_list = socket 
                |> recv_byte!(len - 1) 
                |> Torrent.Parser.parse_bitfield
    pipe_message(socket, Map.put(info_structs, :peer_list, peer_list))
  end

  def have(socket, info_structs) do
    # this is always 4 byte
    meta_info = info_structs[:meta_info]
    index = socket |> recv_32_bit_int
    peer_list = info_structs[:peer_list] 
                |> Map.update!(index, fn(i) -> i = 1 end)
    pipe_message(socket, Map.update!(info_structs, :peer_list, fn(l) -> l = peer_list end))
  end

  def unchoke(socket, len, info_structs) do
    # start requesting all we know
    Torrent.Request.request_all(socket, info_structs[:peer_list], info_structs[:meta_info])
    pipe_message(socket, info_structs)
  end

  def pipe_message(socket, info_structs) do
    len = socket |> recv_32_bit_int
    id = socket |> recv_8_bit_int

    case id do
      0 ->
        IO.puts "got a choke message"
        pipe_message(socket, info_structs)
      1 ->
        IO.puts "got a unchoke message"
        unchoke(socket, len, info_structs)
      2 ->
        IO.puts "got a interested message"
        pipe_message(socket, info_structs)
      3 ->
        IO.puts "got a uninterested message"
        pipe_message(socket, info_structs)
      4 ->
        IO.puts "got a have message"
        have(socket, info_structs)
      5 ->
        IO.puts "got a bitfield message"
        bitfield(socket, len, info_structs)
      6 ->
        IO.puts "got a request message"
        pipe_message(socket, info_structs)
      7 ->
        IO.puts "got a piece message"
        piece(socket, len, info_structs)
      8 ->
        IO.puts "got a cancel message"
        pipe_message(socket, info_structs)
    end
  end

  def recv_8_bit_int(socket) do 
    socket |> recv_byte!(1) |> :binary.bin_to_list |> Enum.at(0) 
  end

  def recv_32_bit_int(socket) do
    socket |> recv_byte!(4) |> :binary.decode_unsigned
  end

  def recv_byte!(socket, count) do
    { ok, message } = socket |> Socket.Stream.recv(count)
    message
  end

  def recv_byte(socket, count) do
    { ok, message } = socket |> Socket.Stream.recv(count)
    { ok, message }
  end
end
