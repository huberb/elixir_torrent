defmodule Torrent.Request do
  @data_request_len 16384 # 2^14 is a common size
  # @data_request_len 8192 # 2^13 for simple offset tests
  @max_piece_req 10 

  def start_link(meta_info) do
    { ok, pid } = Task.start_link(fn ->

      num_pieces = Torrent.Filehandler.num_pieces(meta_info["info"])
      num_blocks = Torrent.Filehandler.num_blocks(meta_info["info"])

      meta_info = meta_info |> Map.put(:num_pieces, num_pieces)
      meta_info = meta_info |> Map.put(:num_blocks, num_blocks)

      offset_struct = 
        0..num_blocks 
        |> Enum.map(fn(offset) -> { offset * data_request_len, :pending } end)
        |> Map.new

      piece_struct =
        0..num_pieces
        |> Enum.map(fn(index) -> { index, %{ state: :pending, peers: [], offset: offset_struct } } end)
        |> Map.new

      manage_requests(piece_struct, %{}, meta_info)
    end)
    pid
  end

  def manage_requests(piece_struct, peer_struct, meta_info) do
    receive do
      { :bitfield, peer_id, socket, bitfield } ->
        peer_struct = peer_struct |> update_peer_struct(peer_id, socket)
        piece_struct = piece_struct |> update_piece_struct(peer_id, bitfield, 0)
        manage_requests(piece_struct, peer_struct, meta_info)

      { :piece, peer, socket, index } ->
        manage_requests(piece_struct, peer_struct, meta_info)

      { :state, peer_id, state } ->
        peer_struct = peer_struct |> update_peer_struct(peer_id, state)
        piece_struct = piece_struct |> request(peer_struct, meta_info, 0, @max_piece_req)
        manage_requests(piece_struct, peer_struct, meta_info)

      { :received, index, offset } ->
        piece_struct = put_in(piece_struct, [index, :offset, offset], :received)
        manage_requests(piece_struct, peer_struct, meta_info)
    end
  end

  def request(piece_struct, peer_struct, meta_info, index, max) do
    if index == max do
      piece_struct
    else
      piece = piece_struct[index]
      if piece[:state] == :pending && length(piece[:peers]) > 0 do
        # TODO: better way to choose peer
        peer_id = piece[:peers] |> Enum.at(0)
        peer = peer_struct[peer_id]
        if peer[:state] == :unchoke do
          block_len = data_length(index, meta_info)
          send_piece_request(peer[:socket], index, 0, block_len)
          IO.puts "send request index: #{index}"
          piece_struct = put_in(piece_struct, [index, :state], :requested)
          request(piece_struct, peer_struct, meta_info, index + 1, max)
        else
          IO.puts "skipped request index: #{index} because of choke"
          request(piece_struct, peer_struct, meta_info, index + 1, max)
        end
      else
        IO.puts "skipped request index: #{index} with state #{piece[:state]}"
        request(piece_struct, peer_struct, meta_info, index + 1, max)
      end
    end
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

  def update_piece_struct(piece_struct, peer, index) do
    peer_list = piece_struct[index][:peers] ++ [peer]
    put_in(piece_struct, [index, :peers], peer_list)
  end

  def update_piece_struct(piece_struct, peer, bitfield, bit_index) do
    if bit_index == length(bitfield) do
      piece_struct
    else
      case bitfield |> Enum.at(bit_index) do
        "1" ->
          piece_struct 
          |> update_piece_struct(peer, bit_index)
          |> update_piece_struct(peer, bitfield, bit_index + 1)
        "0" ->
          piece_struct 
          |> update_piece_struct(peer, bitfield, bit_index + 1)
      end
    end
  end

  def data_request_len do
    @data_request_len
  end

  def send_piece_request(socket, index, offset, len) do
    send_block_request(socket, index, offset)
    if offset + @data_request_len < len do
      new_offset = offset + @data_request_len
      send_piece_request(socket, index, new_offset, len)
    end
  end

  def send_block_request(socket, index, offset) do
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
