defmodule Torrent.Stream do

  def recv(socket) do
    # spawn keep_alive(socket)
    socket |> send_interested
           |> wait_for_unchoke(0)
           |> send_request

    block = socket |> recv_block
    require IEx
    IEx.pry
  end

  def send_interested(socket) do
    # TODO: can write this better
    message = [0,0,0,1,2] |> :binary.list_to_bin
    socket |> Socket.Stream.send!(message)
    IO.puts "send interested message"
    socket
  end

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
    len = socket |> recv_length_param
    id = len |> recv_id(socket)
    payload = nil

    if id |> has_payload? do
      payload = socket |> recv_byte(len - 1)
    end

    { id, len, payload }
  end

  def wait_for_unchoke(socket, count) do
    IO.puts "so far i got #{count} chokes"

    { id, len, payload } = socket |> recv_message

    if id == 1 do # unchoke
      socket
    else
      socket |> wait_for_unchoke(count + 1)
    end
  end

  def recv_block(socket) do
    { id, len, payload } = socket |> recv_message
  end

  def send_request(socket) do
    socket |> Socket.Stream.send!(request_block)
  end

  def request_block do
    # the doc says i need len 12 here, but for some
    # reason the peer won't answer and wireshark says
    # malformed packet if i don't use 13
    # TODO: find out why
    len = 13

    # id is 6, just like in the docs
    id = 6
    
    # packet structure after len and id:
    # ---------------------------------------------
    # | Piece Index | Block Offset | Block Length |
    # ---------------------------------------------

    # TODO: dont hardcode
    block = << len :: 32 >> <> # length
    << id :: 8 >> <> # id
    << 0 :: 32 >> <> # index
    << 0 :: 32 >> <> # offset
    # people suggest 2^14 here
    << 16384 :: 32 >> # length

    block
  end

  # TODO: better design
  def recv_payload({ len, id }, socket) do
  end

  def has_payload?(id) do
    if id in [4, 5, 6, 7, 8, 9] do
      true
    else
      false
    end
  end

  def recv_id(len, socket) do
    if len == 0 do
      -1
    else
      socket |> recv_byte(1) |> Enum.at(0)
    end
  end

  def recv_byte(socket, count) do
    { :ok, message } = socket |> Socket.Stream.recv(count)
    # IO.puts(message |> :binary.bin_to_list)
    message = message |> :binary.bin_to_list
    IO.puts(message)
    message
  end

  def recv_length_param(socket) do
    socket |> recv_byte(4) |> List.last
  end

end
