defmodule Torrent.Request2 do
  @data_request_len 16384 # 2^14 is a common size
  # @data_request_len 8192 # 2^13 for simple offset tests

  def data_request_len do
    @data_request_len
  end

  def start_link() do
    { _, pid } = Task.start_link(fn ->
      Process.flag(:priority, :high)

      meta_info = Torrent.Metadata.wait_for_metadata()
      num_pieces = Torrent.Filehandler.num_pieces meta_info[:info] 
      last_piece_size = Torrent.Filehandler.last_piece_size meta_info[:info] 

      request_info = %{
        num_pieces: num_pieces,
        last_piece_size: last_piece_size,
        piece_length: meta_info[:info][:piece_length],
        request_stack: 0,
      }

      pieces = create_piece_struct(%{}, request_info)
      manage_requests %{}, pieces, request_info
    end)
    pid
  end

  def create_piece_struct(acc, request_info, index \\ 0, offset \\ 0) do
    piece_len = piece_length(index, request_info)
    last_piece? = request_info[:num_pieces] - 1 == index
    last_block? = offset + @data_request_len > piece_len

    cond do 
      last_piece? && last_block? ->
        size = request_info[:last_piece_size] - offset
        size = if size <= 0, do: @data_request_len, else: size
        add_block(acc, index, offset, size)

      last_block? ->
        add_block(acc, index, offset, @data_request_len)
        |> create_piece_struct(request_info, index + 1, 0)

      true ->
        add_block(acc, index, offset, @data_request_len)
        |> create_piece_struct(request_info, index, offset + @data_request_len)
    end
  end

  def add_block(acc, index, offset, size) do
    if acc[index] == nil do
      put_in(acc, [index], %{ peers: [], blocks: %{} })
      |> put_in([index, :blocks, offset], %{ size: size, state: :pending })
    else
      put_in(acc, [index, :blocks, offset], %{ size: size, state: :pending })
    end
  end

  def piece_length(index, request_info) do
    num_pieces = request_info[:num_pieces]
    if index != num_pieces - 1 do
      request_info[:piece_length]
    else
      request_info[:last_piece_size]
    end
  end

  def manage_requests(peers, pieces, request_info) do
    receive do
      # add a new connection with its piece infos
      { :bitfield, connection, socket, bitfield } ->
        peers
        |> add_peer(connection, socket) 
        |> add_bitfield(connection, bitfield, request_info)
        request peers, pieces, request_info

      # have message from peer
      # TODO: get socket
      { :piece, peer_ip, index } ->
        piece_struct = add_peer_info(pieces, peer_ip)
        manage_requests(piece_struct, peer_struct, meta_info)

      # choke or unchoke message
      { :state, connection, state } ->
        peers = put_in(peers, [connection, :state], state)
        request_info = raise_stack(request_info, :state, state)
        request peers, pieces, request_info

    end
  end

  def raise_stack(request_info, :state, state) do
    case state do
      :unchoke -> raise_stack(request_info)
      _ -> request_info
    end
  end

  def raise_stack(request_info) do
    update_in(request_info, [:request_stack], &(&1 + 1))
  end

  def request(peers, pieces, request_info) do
    pieces 
    |> Enum.filter(fn{index, piece} -> has_pending_blocks?(piece) end)
  end

  def pending_blocks(piece) do
    piece[:blocks] |> Enum.filter(fn({offset, state}) -> state == :pending end)
    piece[:blocks] |> Enum.map(fn({offset, state}) -> offset end)
  end

  def has_pending_blocks?(piece) do
    piece[:blocks] |> Enum.any?(fn({offset, state}) -> state == :pending end)
  end

  def send_block_request(socket, index, offset, request_info, type) do
    req = request_query index, offset, request_info, type 
    socket |> Socket.Stream.send(req)
  end

  def add_peer(peers, connection, socket) do
    put_in(peers, [connection], %{ state: :choked, socket: socket, pieces: [] } )
  end

  def add_bitfield(peers, connection, bitfield, request_info) do
    add_bitfield(peers, connection, bitfield, 0, request_info[:num_pieces])
  end

  def add_bitfield(peers, connection, bitfield, index, max) do
    if index == max do
      peers
    else
      case Enum.at(bitfield, index) do
        "1" ->
          peers 
          |> update_in([connection, :pieces], &(&1 ++ [index]))
          |> add_bitfield(connection, bitfield, index + 1, max)
        "0" ->
          peers 
          |> add_bitfield(connection, bitfield, index + 1, max)
      end
    end
  end

  def request_query(index, offset, request_info, type) do
    num_pieces = request_info[:num_pieces]
    request_length = 13
    id = if type == :request, do: 6, else: 8

    last_piece? = num_pieces - 1 == index
    last_block? = offset + @data_request_len > request_info[:last_piece_size]

    block_size = cond do
      last_piece? && last_block? ->
        size = request_info[:last_piece_size] - offset
        if size <= 0, do: @data_request_len, else: size
      true -> 
        @data_request_len
    end

    # IO.puts "index: #{index}, offset: #{offset}, block_size: #{block_size}"
    << request_length :: 32 >>
    <> << id :: 8 >>
    <> << index :: 32 >>
    <> << offset :: 32 >>
    <> << block_size :: 32 >>
  end

end
