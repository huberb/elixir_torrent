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
    # IO.puts "send interested message"
    socket
  end

  def cancel() do
    exit(:normal)
  end

  def piece(socket, len, info_structs) do
    index = socket |> recv_32_bit_int
    offset = socket |> recv_32_bit_int
    # IO.puts "received #{index} with offset: #{offset}"
    block = %{
      peer: info_structs[:peer],
      len: len - 9,
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
      { :bitfield, info_structs[:peer], socket, piece_list }

    pipe_message(socket, info_structs)
  end

  def have(socket, info_structs) do
    index = socket |> recv_32_bit_int
    send info_structs[:requester_pid], 
      { :piece, info_structs[:peer], index }
    pipe_message(socket, info_structs)
  end

  def unchoke(socket, info_structs) do
    send info_structs[:requester_pid],
      { :state, info_structs[:peer], :unchoke }
    pipe_message(socket, info_structs)
  end

  def pipe_message(socket, info_structs) do
    len = socket |> recv_32_bit_int
    id = socket |> recv_8_bit_int

    # IO.puts "got a #{flag} message"
    case Enum.at(@message_flags, id) do
      :choke ->
        pipe_message(socket, info_structs)
      :unchoke ->
        unchoke(socket, info_structs)
      :interested ->
        pipe_message(socket, info_structs)
      :uninterested ->
        pipe_message(socket, info_structs)
      :have ->
        have(socket, info_structs)
      :bitfield ->
        bitfield(socket, len, info_structs)
      :request ->
        require IEx
        IEx.pry
        pipe_message(socket, info_structs)
      :piece ->
        piece(socket, len, info_structs)
      :cancel ->
        cancel()
      nil ->
        exit(:normal)
    end
  end

  def recv_8_bit_int(socket) do 
    socket |> recv_byte!(1) |> :binary.bin_to_list |> Enum.at(0) 
  end

  def recv_32_bit_int(socket) do
    socket |> recv_byte!(4) |> :binary.decode_unsigned
  end

  def recv_byte!(socket, count) do
    case socket |> Socket.Stream.recv(count) do
      { :error, _ } ->
        exit(:normal)
      { :ok, nil } ->
        exit(:normal)
      { :ok, message } ->
        message
    end
  end

end
