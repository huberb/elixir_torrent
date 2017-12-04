defmodule Torrent.Extension do

  @ut_metadata_id 3

  def pipe_message(socket, len) do
    id = Torrent.Stream.recv_byte!(socket, 1) |> :binary.bin_to_list |> Enum.at(0)
    IO.puts "got extension message with id: #{id}"

    case id do
      0 -> # 0 is the handshake message
        handshake = Torrent.Stream.recv_byte!(socket, len - 2)
        handshake = Bento.decode!(handshake)
        answer_extension_handshake(socket, handshake)
        ask_for_meta_info(socket, handshake)

      @ut_metadata_id -> # ut_metadata extension
        recv_metadata_piece(socket, len)

    end
  end

  def recv_metadata_piece(socket, len, binary \\ "") do
    byte = Torrent.Stream.recv_byte!(socket, 1)
    binary = binary <> byte
    case Bento.decode(binary) do
      { :error, _ } ->
        recv_metadata_piece(socket, len, binary)
      { :ok, message } ->
        Torrent.Stream.recv_byte!(socket, len - byte_size(binary) - 2)
    end
  end

  def answer_extension_handshake(socket, extension_hash) do
    id = 20
    extension_id = 0

    extensions = %{ 
      'm': %{ 'ut_metadata': @ut_metadata_id }, 
      'metadata_size': extension_hash["metadata_size"]
    } |> Bento.encode!

    payload = << id :: 8 >> <> << extension_id :: 8 >> <> << extensions :: binary >>
    len = byte_size(payload)

    packet = << len :: 32 >> <> payload
    IO.puts "extension handshake answer"
    Socket.Stream.send(socket, packet)
  end

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


end
