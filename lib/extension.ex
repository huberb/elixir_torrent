defmodule Torrent.Extension do

  @ut_metadata_id 3
  @metadata_piece_length 16384

  def pipe_message(socket, len, info_structs) do
    id = Torrent.Stream.recv_byte!(socket, 1) |> :binary.bin_to_list |> Enum.at(0)

    case id do
      0 -> # 0 is the handshake message
        binary_handshake = Torrent.Stream.recv_byte!(socket, len - 2)
        handshake = Bento.decode!(binary_handshake) |> Torrent.Parser.keys_to_atom
        answer_extension_handshake(socket, handshake)
        check_metadata_request(socket, handshake, info_structs)
        { :handshake, handshake }

      @ut_metadata_id -> # only extension we support
        cond do
          is_map(info_structs[:meta_info][:info]) -> # maybe we already got the metadata
            # if yes, we pull the data anyway to free up for the next message
            recv_metadata_piece(socket, len) 
            # and send the metadata back
            { :meta_info, info_structs[:meta_info][:info] }
          is_list(info_structs[:meta_info][:info]) ->
            # otherwise we pull we data
            { header, data } = recv_metadata_piece(socket, len) 
            # concat it with we data we already have
            metadata_pieces = info_structs[:meta_info][:info] ++ [{ header, data }]

            # check if all is downloaded
            current_len = metadata_pieces |> compile_metadata |> byte_size
            needed_len = info_structs[:extension_hash][:metadata_size]
            if current_len == needed_len do # we're finished
              info = compile_metadata(metadata_pieces) 
                         |> Bento.decode! 
                         |> Torrent.Parser.keys_to_atom
              { :meta_info, info }
            else # still parts missing
              { :downloading, { header, data } }
            end
        end
    end
  end

  def compile_metadata(metadata_pieces) do
    metadata_pieces 
    |> Enum.sort_by(fn({ header, _ }) -> header["piece"] end)
    |> Enum.map(fn({ _, data }) -> data end)
    |> Enum.join("")
  end

  def recv_metadata_piece(socket, len, header \\ "") do
    byte = Torrent.Stream.recv_byte!(socket, 1)
    header = header <> byte
    case Bento.decode(header) do
      { :error, _ } ->
        recv_metadata_piece(socket, len, header)
      { :ok, compiled_header } ->
        data = Torrent.Stream.recv_byte!(socket, len - byte_size(header) - 2)
        { compiled_header, data }
    end
  end

  def answer_extension_handshake(socket, extension_hash) do
    id = 20
    extension_id = 0

    extensions = %{ 
      'm': %{ 'ut_metadata': @ut_metadata_id }, 
      'metadata_size': extension_hash[:metadata_size]
    } |> Bento.encode!

    payload = << id :: 8 >> <> << extension_id :: 8 >> <> << extensions :: binary >>
    len = byte_size(payload)

    packet = << len :: 32 >> <> payload
    Socket.Stream.send(socket, packet)
  end

  def check_metadata_request(socket, extension_hash, info_structs) do
    # only request if the peer supports ut_metadata and we dont have the metainfo yet
    ut_metadata_support = extension_hash[:m][:ut_metadata] != nil
    need_metadata = info_structs[:meta_info][:info] |> Enum.empty?
    if ut_metadata_support && need_metadata do
      ask_for_meta_info(socket, extension_hash, 0)
    end
  end

  def ask_for_meta_info(socket, extension_hash, index) do
    bittorrent_id = 20
    metadata_id = extension_hash[:m][:ut_metadata]
    payload = %{ "msg_type": 0, "piece": index } |> Bento.encode!
    len = byte_size(payload) + 2

    packet = 
      << len :: 32 >> 
      <> << bittorrent_id :: 8 >> 
      <> << metadata_id :: 8 >> 
      <> << payload :: binary >>

    Socket.Stream.send(socket, packet)
    num_pieces = extension_hash[:metadata_size] / @metadata_piece_length - 1
    if index < num_pieces do
      ask_for_meta_info(socket, extension_hash, index + 1)
    end
  end

end
