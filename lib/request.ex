defmodule Torrent.Request do
  # @data_request_len 16384 # 2^14 is a common size
  @data_request_len 8192 # 2^13 for simple offset tests

  def data_request_len do
    @data_request_len
  end

  def request_all(socket, peer_list, meta_info) do
    spawn fn() -> 
      for { key, val } <- peer_list do
        if val == 1 do
          len = data_length(key, meta_info)
          send_piece_request(socket, key, 0, len, meta_info)
          # :timer.sleep(500)
        end
      end
    end
  end

  def send_piece_request(socket, index, offset, len, meta_info) do
    if offset + @data_request_len < len do
      new_offset = offset + @data_request_len
      send_block_request(socket, index, offset)
      send_piece_request(socket, index, new_offset, len, meta_info)
    else
      send_block_request(socket, index, offset)
    end
  end

  def send_block_request(socket, index, offset) do
    IO.puts "send request index: #{index}, offset: #{offset}"
    request = request_query(index, offset)
    socket |> Socket.Stream.send!(request)
  end

  def data_length(index, meta_info) do
    info_hash = meta_info["info"]
    num_pieces = Torrent.Filehandler.num_pieces(info_hash)
    if index != num_pieces do
      info_hash["piece length"]
    else
      Torrent.Filehandler.last_piece_length(info_hash)
    end
  end

  def request_query(index, offset) do
    request_length = 13
    id = 6

    << request_length :: 32 >> <>
    << id :: 8 >> <>
    << index :: 32 >> <>
    << offset :: 32 >> <>
    << @data_request_len :: 32 >>
  end

end
