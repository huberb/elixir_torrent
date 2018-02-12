defmodule Torrent.Request2 do
  @data_request_len 16384 # 2^14 is a common size
  @request_count 2 # how many requests per received block
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

      pieces = create_piece_struct([], request_info)
      manage_requests %{}, pieces, request_info
    end)
    pid
  end

  def create_piece_struct(acc, request_info, index \\ 0, offset \\ 0) do
    piece_len = piece_length(index, request_info)
    last_piece? = request_info[:num_pieces] - 1 == index
    last_block? = offset + @data_request_len >= piece_len

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

  def manage_requests(peers, pieces, request_info) do
    receive do
      # add a new connection with its piece infos
      { :bitfield, connection, socket, bitfield } ->
        peers
        |> add_peer(connection, socket) 
        |> add_bitfield(connection, bitfield, request_info)
        |> manage_requests(pieces, request_info)

      # have message from peer
      { :piece, connection, socket, index } ->
        peers = add_peer_info(peers, connection, socket, index)
        request(peers, pieces, request_info)

      # choke or unchoke message
      { :state, connection, socket, state } ->
        put_in(peers, [connection, :state], state)
        |> request(pieces, request_info)

      # received block
      # TODO: remember who sent it
      { :received, _connection, index, offset } ->
        pieces = received_block(pieces, index, offset)
        IO.puts length(pieces)
        request peers, pieces, request_info

    end
  end

  def request(peers, pieces, request_info, count \\ @request_count) do
    piece = piece_with_state(pieces, :pending)
    piece = 
      if piece != nil, do: piece, 
      else: piece_with_state(pieces, :requested)

    peer = 
      peers_with_piece(peers, piece[:index]) 
      |> Enum.shuffle()
      |> List.first()

    cond do 
      count == 0 ->
        manage_requests peers, pieces, request_info
      peer == nil ->
        request peers, pieces, request_info, count - 1
      true ->
        send_block_request(peer[:socket], piece)
        pieces = requested_piece(pieces, piece)
        request peers, pieces, request_info, count - 1
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

  def received_block(pieces, index, offset) do
    piece_index = 
      Enum.find_index(pieces, 
        fn(piece) -> piece[:index] == index && piece[:offset] == offset end)

    if index == 1189 && offset == 507904 do
      require IEx
      IEx.pry
    end

    List.pop_at(pieces, piece_index) |> elem(1)
  end

  def requested_piece(pieces, piece) do
    index = 
      Enum.find_index(pieces, 
        fn(p) -> p[:index] == piece[:index] && p[:offset] == piece[:offset] end)

    { piece, pieces } = List.pop_at(pieces, index)
    piece = %{ piece | state: :requested }
    [piece] ++ pieces
  end

  def piece_with_state(pieces, state) do
    Enum.filter(pieces, fn piece -> piece[:state] == state end)
    |> List.first()
  end

  def add_block(pieces, index, offset, size) do
    pieces ++ [%{ index: index, offset: offset, size: size, state: :pending }]
  end

  def add_peer(peers, connection, socket) do
    put_in(peers, [connection], %{ state: :choked, socket: socket, pieces: [] } )
  end

  def add_peer_info(peers, connection, socket, state) when is_atom(state) do
    if peers[connection] == nil do
      add_peer(peers, connection, socket)
      |> put_in([connection, :state], :unchoked)
    else
      put_in peers, [connection, :state], :unchoked
    end
  end

  def add_peer_info(peers, connection, socket, index) when is_integer(index) do
    if peers[connection] == nil do
      add_peer(peers, connection, socket)
      |> update_in([connection, :pieces], &(Enum.uniq(&1 ++ [index])))
    else
      update_in peers, [connection, :pieces], &(Enum.uniq(&1 ++ [index]))
    end
  end

  def peers_with_piece(peers, index) do
    Enum.filter(peers, fn({connection, info}) -> 
      Enum.member?(info[:pieces], index) &&
      info[:state] == :unchoke
    end)
    |> Enum.map(fn({connection, info}) -> info end)
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

  def send_block_request(socket, piece) do
    %{ index: index, offset: offset, size: size } = piece
    send_block_request(socket, index, offset, size, :request)
  end
  def send_block_request(socket, index, offset, size, type) do
    req = request_query index, offset, size, type 
    socket |> Socket.Stream.send(req)
  end

  def request_query(index, offset, size, type) do
    request_length = 13 # length of packet
    id = if type == :request, do: 6, else: 8

    send :output, 
    { :request, "sending request: index #{index}, offset: #{offset}, size: #{size}" }

    << request_length :: 32 >>
    <> << id :: 8 >>
    <> << index :: 32 >>
    <> << offset :: 32 >>
    <> << size :: 32 >>
  end

end
