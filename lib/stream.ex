defmodule Torrent.Stream do

  @message_flags [
    { 0, :choke },
    { 1, :unchoke },
    { 2, :interested },
    { 3, :uninterested },
    { 4, :have },
    { 5, :bitfield },
    { 6, :request },
    { 7, :piece },
    { 8, :cancel },
    { 20, :extension },
  ]

  def ask_for_meta_info(socket, extension_hash) do
    meta_info_message_index = extension_hash["m"]["ut_metadata"]
    meta_info_length = extension_hash["metadata_size"]
    id = 20

    # this is buggy
    # Enum.each(0..10, fn(i) -> 
    # payload = %{ "msg_type": i, "piece": 0 } |> Bencoder.encode
    payload = %{ "msg_type": 0, "piece": 0 } |> Bencoder.encode
    IO.puts "sending request for piece #{0} of metadata"
    len = byte_size(payload)
    packet = << len :: 32 >> 
             <> << id :: 8 >> 
             <> << payload :: binary >>
    Socket.Stream.send(socket, packet)
      # end)
  end

  def leech(socket, info_structs) do
    send_interested(socket)
    pipe_message(socket, info_structs)
  end

  def send_interested(socket) do
    IO.puts "sending interested message"
    # len 1, id 2
    message = [0,0,0,1,2] |> :binary.list_to_bin
    socket |> Socket.Stream.send(message)
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
    if info_structs[:extension_handshake] && info_structs[:meta_info][:info] == nil do
      ask_for_meta_info(socket, info_structs[:extension_handshake])
    end
    pipe_message(socket, info_structs)
  end

  def meta_info_bitfield(socket, info_structs, handshake) do
    info_structs = put_in(info_structs, [:extension_handshake], handshake)
    len = recv_32_bit_int(socket)
    id = recv_8_bit_int(socket)

    flag = List.keyfind(@message_flags, id, 0) |> elem(1)

    # if this was not a bitfield flag, something went wrong and we abort
    unless flag == :bitfield do
      raise "expected a meta info bitfield after extension handshake"
    end

    bitfield = recv_byte!(socket, len - 1)
    pipe_message(socket, info_structs)
  end

  def answer_extension_handshake(socket) do
    # TODO: what extensions to support?
    payload = %{ "m": "" } |> Bencoder.encode
    id = 20
    len = byte_size(payload) + 1

    handshake = << len :: 32 >> <> << id :: 8 >> <> << 0 :: 8 >> <> << payload :: binary >>
    IO.puts "extension handshake answer"
    require IEx
    IEx.pry
    Socket.Stream.send(socket, handshake)
  end

  def extension(socket, len, info_structs) do
    id = recv_byte!(socket, 1) |> :binary.bin_to_list |> Enum.at(0)
    # IO.puts "got extension message with id: #{id}"
    if id == 1 do
      require IEx
      IEx.pry
    end
    handshake = recv_byte!(socket, len - 2)
    handshake = Bencoder.decode(handshake)

    if id == 0 do # id 0 is a handshake message
      # after this we expect a meta info bitfield
      answer_extension_handshake(socket)
      meta_info_bitfield(socket, info_structs, handshake)
    else # otherwise continue as usual
      pipe_message(socket, info_structs)
    end
  end

  def pipe_message(socket, info_structs) do
    len = socket |> recv_32_bit_int
    id = socket |> recv_8_bit_int
    # IO.puts "socket: #{info_structs[:peer] |> elem(0)}, id: #{id}"

    { id, flag } = List.keyfind(@message_flags, id, 0)
    case flag do
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
        pipe_message(socket, info_structs)
      :piece ->
        piece(socket, len, info_structs)
      :cancel ->
        cancel()
      :extension -> # extension for metadata transfer
        extension(socket, len, info_structs)
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
