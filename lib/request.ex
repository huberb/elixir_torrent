defmodule Torrent.Request do

  def request_all(socket, peer_list, meta_info) do
    spawn fn() -> 
      for { key, val } <- peer_list do
        if key == 1 && val == 1 do
          send_request(socket, key, meta_info)
          # :timer.sleep(1000)
        end
      end
    end
  end

  def send_request(socket, index, meta_info) do
    IO.puts "sending request for piece Nr: "
    IO.puts index
    request = request_query(index, meta_info)

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
    #test
    16384
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
