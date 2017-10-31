defmodule Torrent.Stream do

  @message_flags [
    :choke, 
    :unchoke, 
    :interested, 
    :uninterested, 
    :have, 
    :bitfield, 
    :request, 
    :piece, 
    :cancel 
  ]

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
    index = socket |> recv_32_bit_int
    offset = socket |> recv_32_bit_int

    block = %{
      from_peer: info_structs[:peer_id],
      len: len,
      data: socket |> recv_byte!(len - 9)
    }

    send info_structs[:writer_pid], { :put, block, index, offset }
    pipe_message(socket, info_structs)
  end

  def bitfield(socket, len, info_structs) do
    piece_list = socket 
                |> recv_byte!(len - 1) 
                |> Torrent.Parser.parse_bitfield

    send info_structs[:requester_pid], 
      { :bitfield, info_structs[:peer_id], socket, piece_list }

    pipe_message(socket, Map.put(info_structs, :piece_list, piece_list))
  end

  def have(socket, info_structs) do
    # this is always 4 byte
    index = socket |> recv_32_bit_int
    piece_list = info_structs[:piece_list] 
                |> List.update_at(index, fn(i) -> i = 1 end)
    pipe_message(socket, Map.update!(info_structs, :piece_list, fn(l) -> l = piece_list end))
  end

  def unchoke(socket, len, info_structs) do

    send info_structs[:requester_pid],
      { :state, info_structs[:peer_id], :unchoke }

    pipe_message(socket, info_structs)
  end

  def pipe_message(socket, info_structs) do
    len = socket |> recv_32_bit_int
    id = socket |> recv_8_bit_int
    flag = @message_flags |> Enum.at(id)

    IO.puts "got a #{flag} message"
    case flag do
      :choke ->
        pipe_message(socket, info_structs)
      :unchoke ->
        unchoke(socket, len, info_structs)
      :interested ->
        pipe_message(socket, info_structs)
      :uninterested ->
        pipe_message(socket, info_structs)
      :have ->
        have(socket, info_structs)
      :bitfield ->
        bitfield(socket, len, info_structs)
      :request ->
        pipe_message(socket, info_structs)
      :piece ->
        piece(socket, len, info_structs)
      :cancel ->
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

end
