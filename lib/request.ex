defmodule Torrent.Request do
  @data_request_len 16384 # 2^14 is a common size
  # @data_request_len 8192 # 2^13 for simple offset tests
  @max_piece_req 3
  @max_load 100

  def start_link(meta_info) do
    { ok, pid } = Task.start_link(fn ->

      num_pieces = Torrent.Filehandler.num_pieces(meta_info["info"])
      num_blocks = Torrent.Filehandler.num_blocks(meta_info["info"])
      last_piece_size = Torrent.Filehandler.last_piece_size(meta_info["info"])

      meta_info = meta_info |> Map.put(:num_pieces, num_pieces)
      meta_info = meta_info |> Map.put(:num_blocks, num_blocks)
      meta_info = meta_info |> Map.put(:last_piece_size, last_piece_size)
      # meta_info = meta_info |> Map.put(:last_block_size, last_block_size)
      meta_info = meta_info |> Map.put(:last_req_piece, 0)

      piece_struct =
        0..num_pieces
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

      { :piece, peer_ip, socket, index } ->
        { ip, _ } = peer_ip
        IO.puts "peer: #{ip} has piece number #{index}"
        piece_struct = add_new_peer_id(piece_struct, peer_ip, index)
        manage_requests(piece_struct, peer_struct, meta_info)

      { :state, peer_ip, state } ->
        peer_struct = add_state_to_peer(peer_struct, peer_ip, state)
        request(piece_struct, peer_struct, meta_info, @max_piece_req)

      { :received, index, from } ->
        { ip, _ } = from
        # IO.puts "set piece Nr: #{index} to received from #{ip}"
        piece_struct = put_in(piece_struct, [index, :state], :received)
        peer_struct = update_in(peer_struct, [from, :load], &(&1 - 1))
        request(piece_struct, peer_struct, meta_info, @max_piece_req)
    end
  end

  def request(piece_struct, peer_struct, meta_info, count) do
    index = meta_info[:last_req_piece]
    piece = piece_struct[index]

    { piece_struct, peer_struct } =
      case piece[:state] do

        :requested -> { piece_struct, peer_struct } # we don't need this piece

        :received -> { piece_struct, peer_struct } # we don't need this piece

        :pending -> # we need this piece
          case lowest_load(piece_struct, peer_struct, index) do
            nil -> 
              # IO.puts "attempted request #{index} but found no peer"
              { piece_struct, peer_struct } # could not find a peer for piece

            peer_ip -> # found good peer for request
              { ip, _ } = peer_ip
              # IO.puts "send request for piece #{index} from #{ip} with load: #{peer_struct[peer_ip][:load]}"
              peer_struct[peer_ip][:socket] 
              |> send_piece_request(index, 0, meta_info)
              {
                put_in(piece_struct, [index, :state], :requested),
                update_in(peer_struct, [peer_ip, :load], &(&1 + 1))
              }
          end
      end

    meta_info = raise_counter(meta_info)
    if count == 0 do
      manage_requests(piece_struct, peer_struct, meta_info)
    else
      request(piece_struct, peer_struct, meta_info, count - 1)
    end
  end

  def raise_counter(meta_info) do
    if meta_info[:last_req_piece] == meta_info[:num_pieces] do
      Map.put(meta_info, :last_req_piece, 0)
    else
      Map.update!(meta_info, :last_req_piece, &(&1 + 1))
    end
  end

  def lowest_load(piece_struct, peer_struct, index) do
    possible_peers = piece_struct[index][:peers]

    filtered_peers = 
      peer_struct
      |> Enum.filter(
        fn({key, info}) -> 
          key in possible_peers 
          && info[:state] == :unchoke
        end)

    # return the id with the lowest load
    %{ id: peer_ip, load: load } =
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

  def add_state_to_peer(peer_struct, id, state) when state |> is_atom do
    put_in(peer_struct, [id, :state], state)
  end

  def add_new_peer(peer_struct, id, socket) do
    case peer_struct[id] do
      nil ->
        peer_struct |> Map.put(id, %{state: :choke, socket: socket, load: 0})
      _   ->
        peer_struct
    end
  end

  def add_new_peer_id(piece_struct, peer, index) do
    update_in(piece_struct, [index, :peers], &(&1 ++ [peer]))
  end

  def add_bitfield(piece_struct, peer, bitfield, bit_index) do
    if bit_index == length(bitfield) do
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

  def data_request_len do
    @data_request_len
  end

  def send_piece_request(socket, index, offset, meta_info) do
    send_block_request(socket, index, offset, meta_info)
    len = data_length(index, meta_info)
    if offset + @data_request_len < len do
      new_offset = offset + @data_request_len
      send_piece_request(socket, index, new_offset, meta_info)
    end
  end

  def send_block_request(socket, index, offset, meta_info) do
    # IO.puts "sending request with #{index} and #{offset}"
    req = request_query(index, offset, meta_info)
    try do
      socket |> Socket.Stream.send!(req)
    catch e ->
    end
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

  def request_query(index, offset, meta_info) do
    request_length = 13
    id = 6
    data_len = @data_request_len

    if index == meta_info[:num_pieces] do
      data_len = meta_info[:last_piece_size]
    end

    << request_length :: 32 >> <>
    << id :: 8 >> <>
    << index :: 32 >> <>
    << offset :: 32 >> <>
    << data_len :: 32 >>
  end

end
