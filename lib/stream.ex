defmodule Torrent.Stream do

  def leech(socket, writer_process, meta_info) do
    # spawn keep_alive(socket)
    bitfield = socket |> set_bitfield

    spawn fn() -> 
      Torrent.Request.request_all(socket, bitfield, meta_info) 
    end

    socket |> send_interested
    |> wait_for_unchoke(0)
    |> recv_block(writer_process, meta_info)
  end

  # some peers dont send a bitfield
  # TODO: handle this
  def set_bitfield(socket) do
    IO.puts "setting bitfield"
    { id, len, payload } = socket |> recv_message

    if id == 5 do # bitfield flag set
    IO.puts "got a valid Bitfield Flag."
    payload
    else
      raise "Bitfield Flag not set on Peer"
    end
  end

  def send_interested(socket) do
    # len 1, id 2
    message = [0,0,0,1,2] |> :binary.list_to_bin
    socket |> Socket.Stream.send!(message)
    IO.puts "send interested message"
    socket
  end

  # TODO: use this
  def keep_alive(socket) do
    try do
      IO.puts "send keep_alive"
      message = [0,0,0,0] |> :binary.list_to_bin
      socket |> Socket.Stream.send!(message)
      :timer.sleep(5000)
      keep_alive(socket)
    rescue
      e -> IO.puts(e.message)
    end
  end

  def recv_message(socket) do
    len = socket |> recv_32_bit_int
    id = recv_8_bit_int(socket)
    payload = nil

    if id |> has_payload? do
      payload = socket |> recv_byte(len - 1)
    end

    { id, len, payload }
  end

  def wait_for_unchoke(socket, count) do
    IO.puts "got #{count} chokes"
    { id, len, payload } = socket |> recv_message

    if id == 1 do # unchoke
    IO.puts "unchoke!"
    socket
    else
      socket |> wait_for_unchoke(count + 1)
    end
  end

  def recv_block(socket, write_process_pid, meta_info) do
    try do

      byte_length = meta_info["length"]
      len = socket |> recv_32_bit_int
      id = socket |> recv_8_bit_int
      index = socket |> recv_32_bit_int

      block = %{
        len: len,
        id: id,
        index: index,
        offset: socket |> recv_32_bit_int,
        # rest of the stream is the file data,
        # there are 
        # len - size(id) - size(index) - size(offset)
        # bytes left
        data: socket |> recv_byte(len - 9)
      }

      Torrent.Parser.validate_data(meta_info["pieces"], block)

      send write_process_pid, { :put, block }
      recv_block(socket, write_process_pid, meta_info)
    rescue e ->
      IO.puts e.message
    end
  end

  def has_payload?(id) do
    if id in [4, 5, 6, 7, 8, 9] do
      true
    else
      false
    end
  end

  def recv_byte(socket, count) do
    { ok, message } = socket |> Socket.Stream.recv(count)
    if message == nil do
      raise "Connection Closed"
    end
    message
  end

  def recv_8_bit_int(socket) do 
    socket |> recv_byte(1) |> :binary.bin_to_list |> Enum.at(0) 
  end

  def recv_32_bit_int(socket) do
    socket |> recv_byte(4) |> :binary.decode_unsigned
  end

end
