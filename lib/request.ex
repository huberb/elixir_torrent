defmodule Torrent.Request do
  # @data_request_len 16384 # 2^14 is a common size
  @data_request_len 8192 # 2^13 for simple offset tests

  def start_link(meta_info) do
    num_pieces = Torrent.Filehandler.num_pieces(meta_info["info"])
    piece_list = 0..num_pieces
                 |> Enum.map(fn(i) -> %{ state: :pending, peers: [] } end)

    meta_info |> Map.put(:num_pieces, num_pieces)

    { ok, pid } = Task.start_link(fn ->
      manage_requests(piece_list, %{}, meta_info)
    end)
    pid
  end

  def manage_requests(piece_list, peer_struct, meta_info) do
    receive do
      { :bitfield, peer_id, socket, bitfield } ->
        peer_struct = peer_struct |> update_peer_struct(peer_id, socket)
        piece_list = piece_list |> update_piece_list(peer_id, bitfield)
        manage_requests(piece_list, peer_struct, meta_info)

      { :piece, peer, socket, index } ->
        manage_requests(piece_list, peer_struct, meta_info)

      { :state, peer_id, state } ->
        peer_struct = peer_struct |> update_peer_struct(peer_id, state)
        piece_list 
        |> request(peer_struct, meta_info)
        |> manage_requests(peer_struct, meta_info)
    end
  end

  def request(piece_list, peer_struct, meta_info) do
    piece_list |> Enum.take(1) |> Enum.with_index |> Enum.map(fn({piece, index}) -> 
      if piece[:state] == :pending do
        peer_id = piece[:peers] |> Enum.at(0)
        socket = peer_struct[peer_id][:socket]
        state = peer_struct[peer_id][:state]
        if state == :unchoke do
          len = data_length(index, meta_info)
          send_piece_request(socket, index, 0, len)
          piece |> Map.update!(:state, fn(i) -> :requested end)
        else
          piece
        end
        piece
      end
    end)
  end

  def update_peer_struct(peer_struct, id, state) when state |> is_atom do
    put_in(peer_struct, [id, :state], state)
  end

  def update_peer_struct(peer_struct, id, socket) do
    case peer_struct[id] do
      nil ->
        peer_struct |> Map.put(id, %{state: :choke, socket: socket})
      _   ->
        peer_struct
    end
  end

  def update_piece_list(piece_list, peer, index) when index |> is_integer do 
    piece_list 
    |> Enum.at(index) 
    |> Map.update!(:peers, fn(list) -> list ++ [peer] end)
  end

  def update_piece_list(piece_list, peer, bitfield) when bitfield |> is_list do
    bitfield 
    |> Enum.with_index 
    |> Enum.map(
      fn({value, index}) -> 
        if value == "1" do
          update_piece_list(piece_list, peer, index)
        end
      end)
  end

  def data_request_len do
    @data_request_len
  end

  def request_all(socket, piece_list, meta_info) do
    spawn fn() -> 
      for { index, available } <- piece_list do
        if index == 1 && available == 1 do
          len = data_length(index, meta_info)
          send_piece_request(socket, index, 0, len)
          # :timer.sleep(500)
        end
      end
    end
  end

  def send_piece_request(socket, index, offset, len) do
    if offset + @data_request_len < len do
      new_offset = offset + @data_request_len
      send_block_request(socket, index, offset)
      send_piece_request(socket, index, new_offset, len)
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
