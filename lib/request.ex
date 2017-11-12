defmodule Torrent.Request do
  @data_request_len 16384 # 2^14 is a common size
  # @data_request_len 8192 # 2^13 for simple offset tests
  @max_piece_req 4 # how many max requests per cycle
  @max_load 3 # max concurrent requests on one peer

  def data_request_len do
    @data_request_len
  end

  def start_link(meta_info) do
    { _, pid } = Task.start_link(fn ->

      num_pieces = Torrent.Filehandler.num_pieces(meta_info["info"])
      num_blocks = Torrent.Filehandler.num_blocks(meta_info["info"])
      last_piece_size = Torrent.Filehandler.last_piece_size(meta_info["info"])

      meta_info = meta_info |> Map.put(:num_pieces, num_pieces)
      meta_info = meta_info |> Map.put(:num_blocks, num_blocks)
      meta_info = meta_info |> Map.put(:last_piece_size, last_piece_size)

      piece_struct =
        0..num_pieces - 1
        |> Enum.map(fn(index) -> { index, %{ state: :pending, peers: [], } } end)
        |> Map.new

      manage_requests(piece_struct, %{}, meta_info)
    end)
    pid
  end

  def manage_requests(piece_struct, peer_struct, meta_info) do
    receive do
      { :bitfield, peer_ip, socket, bitfield } ->
        peer_struct = add_new_peer(peer_struct, peer_ip, socket)
        piece_struct = add_bitfield(piece_struct, peer_ip, bitfield, 0)
        manage_requests(piece_struct, peer_struct, meta_info)

      { :piece, peer_ip, index } ->
        piece_struct = add_new_peer_id(piece_struct, peer_ip, index)
        manage_requests(piece_struct, peer_struct, meta_info)

      { :state, peer_ip, state } ->
        peer_struct = add_state_to_peer(peer_struct, peer_ip, state)
        request(piece_struct, peer_struct, meta_info)

      { :received, index, from } ->
        IO.puts "received #{index}"
        piece_struct = put_in(piece_struct, [index, :state], :received)
        peer_struct = update_in(peer_struct, [from, :load], &(&1 - 1))
        unless any_pending?(piece_struct) do
          IO.puts "canceled #{index}"
          cancel(peer_struct, meta_info, index)
        end
        request(piece_struct, peer_struct, meta_info)
    end
  end

  def cancel(peer_struct, meta_info, index) do
    Enum.each(peer_struct, fn({_, info}) ->
      socket = info[:socket]
      send_piece_request(socket, index, 0, meta_info, :cancel)
    end)
  end

  def pieces_to_request(piece_struct, meta_info) do
    unless any_pending?(piece_struct) do
      piece_struct 
      |> Enum.filter(fn({_, info}) -> info[:state] == :requested end)
      |> Enum.take(@max_piece_req)
      |> Enum.map(fn({index, _}) -> index end)
    else
      piece_struct 
      |> Enum.filter(fn({_, info}) -> info[:state] == :pending end)
      |> Enum.sort_by(fn({index, _}) -> index end)
      |> Enum.take(@max_piece_req)
      |> Enum.map(fn({index, _}) -> index end)
    end
  end

  def any_pending?(piece_struct) do
    Enum.any?(piece_struct, fn({_, info}) -> info[:state] == :pending end)
  end

  def request(piece_struct, peer_struct, meta_info) do
    pieces = pieces_to_request(piece_struct, meta_info)
    request(piece_struct, peer_struct, meta_info, pieces)
  end

  def request(piece_struct, peer_struct, meta_info, pieces) do
    if length(pieces) == 0 do
      manage_requests(piece_struct, peer_struct, meta_info)
    else
      index = pieces |> Enum.at(0)
      { piece_struct, peer_struct } =
        case find_good_peer(piece_struct, peer_struct, index, meta_info) do
          nil ->  # could not find a peer for piece
            IO.puts "could not find peer for #{index}"
            { piece_struct, peer_struct }

          peer_ip = { ip, peer } -> # found one good peer for request
            IO.puts "sending request for piece #{index} to #{ip}"
            peer_struct[peer_ip][:socket] 
            |> send_piece_request(index, 0, meta_info, :request)
            {
              put_in(piece_struct, [index, :state], :requested),
              update_in(peer_struct, [peer_ip, :load], &(&1 + 1)),
            }

          [ first | peers ] -> # request from a list of peers
            request_from_all(peer_struct, index, meta_info, first, peers)
            { piece_struct, peer_struct }
        end
        request(piece_struct, peer_struct, meta_info, List.delete_at(pieces, 0))
    end
  end

  # request a piece from all peers
  def request_from_all(peer_struct, index, meta_info, next, remaining) do
    { peer_id, info } = next
    peer_struct[peer_id][:socket] 
    |> send_piece_request(index, 0, meta_info, :request)

    { ip, _ } = peer_id
    IO.puts "requesting #{index} from #{ip}"

    if length(remaining) > 0 do
      [ next | remaining ] = remaining
      request_from_all(peer_struct, index, meta_info, next, remaining)
    end
  end

  # find a peer that can send the piece
  def find_good_peer(piece_struct, peer_struct, index, meta_info) do
    possible_peers = piece_struct[index][:peers]

    filtered_peers = 
      peer_struct
      |> Enum.filter(
        fn({key, info}) -> 
          key in possible_peers 
          && info[:state] == :unchoke
        end)

    unless any_pending?(piece_struct) do
      filtered_peers |> Enum.shuffle |> Enum.take(5)
    else
      # return the id with the lowest load
      %{ id: peer_ip, load: _ } =
        filtered_peers
        |> Enum.reduce(%{id: nil, load: @max_load}, 
           fn({peer_ip, info}, acc) -> 
             if info[:load] < acc[:load] do
               %{ id: peer_ip, load: info[:load] }
             else
               acc
             end
           end)
      peer_ip
    end
  end

  # peer switched from choke to unchoke or vv
  def add_state_to_peer(peer_struct, id, state) do
    put_in(peer_struct, [id, :state], state)
  end

  # new peer connection
  def add_new_peer(peer_struct, id, socket) do
    case peer_struct[id] do
      nil ->
        peer_struct |> Map.put(id, %{state: :choke, socket: socket, load: 0})
      _   ->
        peer_struct
    end
  end

  # add peer to list of available sender for one piece
  def add_new_peer_id(piece_struct, peer, index) do
    update_in(piece_struct, [index, :peers], &(&1 ++ [peer]))
  end

  def add_bitfield(piece_struct, peer, bitfield, bit_index) do
    if piece_struct[bit_index] == nil do
      piece_struct
    else
      case bitfield |> Enum.at(bit_index) do
        "1" ->
          piece_struct 
          |> add_new_peer_id(peer, bit_index)
          |> add_bitfield(peer, bitfield, bit_index + 1)
        "0" ->
          piece_struct 
          |> add_bitfield(peer, bitfield, bit_index + 1)
      end
    end
  end

  def send_piece_request(socket, index, offset, meta_info, type) do
    send_block_request(socket, index, offset, meta_info, type)
    len = data_length(index, meta_info)
    if offset + @data_request_len < len do
      new_offset = offset + @data_request_len
      send_piece_request(socket, index, new_offset, meta_info, type)
    end
  end

  def send_block_request(socket, index, offset, meta_info, type) do
    req = request_query(index, offset, meta_info, type)
    socket |> Socket.Stream.send(req)
  end

  def data_length(index, meta_info) do
    info_hash = meta_info["info"]
    num_pieces = meta_info[:num_pieces]
    if index != num_pieces do
      info_hash["piece length"]
    else
      meta_info[:last_piece_size]
    end
  end

  def request_query(index, offset, meta_info, type) do
    num_pieces = meta_info[:num_pieces]
    request_length = 13

    id = case type do
      :request ->
        6
      :cancel ->
        8
    end

    block_size = cond do
      num_pieces - 1 == index -> 
        # meta_info[:last_piece_size]
        @data_request_len
      true -> 
        @data_request_len
    end

    << request_length :: 32 >>
    <> << id :: 8 >>
    <> << index :: 32 >>
    <> << offset :: 32 >>
    <> << block_size :: 32 >>
  end

end
