defmodule Torrent.Stream do

  @ut_metadata_id 3

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
    if extension_hash["m"]["ut_metadata"] != nil do
      IO.puts "sending request metainfo"
      bittorrent_id = 20
      metadata_id = extension_hash["m"]["ut_metadata"]

      payload = %{ "msg_type": 0, "piece": 0 } |> Bento.encode!
      len = byte_size(payload) + 2

      packet = 
        << len :: 32 >> 
        <> << bittorrent_id :: 8 >> 
        <> << metadata_id :: 8 >> 
        <> << payload :: binary >>

      Socket.Stream.send(socket, packet)
    end
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
    pipe_message(socket, info_structs)
  end

  def answer_extension_handshake(socket, handshake) do
    id = 20
    extension_id = 0

    extensions = %{ 
      'm': %{ 'ut_metadata': @ut_metadata_id }, 
      'metadata_size': handshake["metadata_size"]
    } |> Bento.encode!

    payload = << id :: 8 >> <> << extension_id :: 8 >> <> << extensions :: binary >>
    len = byte_size(payload)

    handshake = << len :: 32 >> <> payload
    IO.puts "extension handshake answer"
    Socket.Stream.send(socket, handshake)
  end

  def extension(socket, len, info_structs) do
    id = recv_byte!(socket, 1) |> :binary.bin_to_list |> Enum.at(0)
    IO.puts "got extension message with id: #{id}"

    case id do
      0 -> # 0 is the handshake message
        handshake = recv_byte!(socket, len - 2)
        handshake = Bento.decode!(handshake)
        answer_extension_handshake(socket, handshake)
        ask_for_meta_info(socket, handshake)

      @ut_metadata_id -> # ut_metadata extension
        data = recv_byte!(socket, len)
        require IEx
        IEx.pry

    end

    pipe_message(socket, info_structs)
  end

  def pipe_message(socket, info_structs) do
    len = socket |> recv_32_bit_int
    id = socket |> recv_8_bit_int
    # IO.puts "socket: #{info_structs[:peer] |> elem(0)}, id: #{id}"

    { id, flag } = List.keyfind(@message_flags, id, 0)
    IO.puts flag
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
