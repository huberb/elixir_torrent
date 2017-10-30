defmodule Torrent.Request do

  def request_all(socket, bitfield, meta_info) do
    bitfield 
    |> Torrent.Parser.parse_bitfield
    |> Enum.with_index
    |> Enum.each(fn({piece, index}) -> 
      send_request(socket, piece, index, meta_info)
    end)
  end

  # TODO: move piece availability info to another process
  def send_request(socket, piece, index, meta_info) do
    if piece[:available] do
      IO.puts "sending request for piece Nr: "
      IO.puts index
      request = request_query(index, meta_info)

      socket |> Socket.Stream.send!(request)
    end
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

  def request_query(index, meta_info) do
    request_length = 13
    id = 6

    # TODO: dont hardcode offset
    << request_length :: 32 >> <> # length
    << id :: 8 >> <> # id
    << index :: 32 >> <> # index
    << 0 :: 32 >> <> # offset
    << data_length(index, meta_info) :: 32 >> # length
  end

end
