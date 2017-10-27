defmodule Torrent.Stream do

  def recv(socket) do
    # spawn keep_alive(socket)
    socket |> send_interested
    socket |> wait_for_unchoke(0)
  end

  def send_interested(socket) do
    # TODO: can write this better
    message = [0,0,0,1,2] |> :binary.list_to_bin
    socket |> Socket.Stream.send!(message)
    IO.puts "send interested message"
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

  def wait_for_unchoke(socket, count) do
    IO.puts "so far i got #{count} chokes"
    count = count + 1

    len = socket |> recv_length_param
    id = len |> recv_id(socket)

    if id == 4 do
      payload = {len, id} |> recv_payload(socket)
    end

    IO.puts "len: "
    IO.puts len
    IO.puts "id: "
    IO.puts id
    if id == 1 do # unchoke
      # after we get a unchoke message
      # we send a request for the first piece
      socket |> send_request

      piece = socket |> get_piece
      require IEx
      IEx.pry
    else
      socket |> wait_for_unchoke(count)
    end
  end

  def get_piece(socket) do
    mess = socket |> Socket.Stream.recv(1)
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
    if id |> has_payload? do
      IO.puts "receiving Payload"
      payload = socket |> recv_byte(len - 1)
    else
      nil
    end
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
