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

    block = %{
      from_peer: info_structs[:peer_id],
      len: len,
      index: socket |> recv_32_bit_int,
      offset: socket |> recv_32_bit_int,
      data: socket |> recv_byte!(len - 9)
    }

    Torrent.Parser.validate_data(info_hash["pieces"], block)

    send info_structs[:writer_pid], { :put, block }
  end

  def bitfield(socket, len, info_structs) do
    meta_info = info_structs[:meta_info]
    message = socket |> recv_byte!(len - 1)
    Torrent.Request.request_all(socket, message, meta_info)
  end

  def have(socket, len, info_structs) do
    # this is always 4 byte
    message = socket |> recv_32_bit_int
    # TODO: request here
  end

  def pipe_message(socket, info_structs) do
    meta_info = info_structs[:meta_info]
    writer_process = info_structs[:writer_pid]
    peer_id = info_structs[:peer_id]

    len = socket |> recv_32_bit_int
    id = socket |> recv_8_bit_int

    case id do
      0 ->
        IO.puts "got a unchoke message"
      1 ->
        IO.puts "got a choke message"
      2 ->
        IO.puts "got a interested message"
      3 ->
        IO.puts "got a uninterested message"
      4 ->
        IO.puts "got a have message"
        have(socket, len, info_structs)
      5 ->
        IO.puts "got a bitfield message"
        bitfield(socket, len, info_structs)
      6 ->
        IO.puts "got a request message"
      7 ->
        IO.puts "got a piece message"
        piece(socket, len, info_structs)
      8 ->
        IO.puts "got a cancel message"
    end

    pipe_message(socket, info_structs)
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
