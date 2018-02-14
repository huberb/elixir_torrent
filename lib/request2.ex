defmodule Torrent.Request2 do
  @data_request_len 16384 # 2^14 is a common size
  @request_count 2 # how many request tries per received block
  @max_load 3 # max load on one peer
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
        endgame: false,
        request_index: 0,
        request_offset: 0,
        request_size: @data_request_len
      }

      manage_requests %{}, [], request_info
    end)
    pid
  end

  def next_block(request_info, pieces) do
    if request_info[:endgame] do
      pieces |> Enum.shuffle() |> List.first()
    else
      %{
        index: request_info[:request_index], 
        offset: request_info[:request_offset], 
        size: request_info[:request_size] 
      }
    end
  end

  def raise_block_counter(request_info) do
    if request_info[:request_index] == request_info[:num_pieces] do
      request_info
    else
      index = request_info[:request_index]
      offset = request_info[:request_offset]
      piece_len = piece_length(index, request_info)
      last_piece? = request_info[:num_pieces] - 1 == index
      last_block? = offset + @data_request_len >= piece_len

      cond do 
        last_piece? && last_block? ->
          size = request_info[:last_piece_size] - offset
          size = if size <= 0, do: @data_request_len, else: size
          put_in(request_info, [:endgame], true)
          |> put_in([:request_size], size)

        last_block? ->
          update_in(request_info, [:request_index], &(&1 + 1))
          |> put_in([:request_offset], 0)

        true ->
          update_in(request_info, [:request_offset], &(&1 + @data_request_len))

      end
    end
  end

  def manage_requests(peers, pieces, request_info) do
    IO.puts length(pieces)
    receive do
      # add a new connection with its piece infos
      { :bitfield, connection, socket, bitfield } ->
        peers
        |> add_peer(connection, socket) 
        |> add_bitfield(connection, bitfield, request_info)
        |> manage_requests(pieces, request_info)

      # have message from peer
      { :piece, connection, socket, index } ->
        add_peer_info(peers, connection, socket, index)
        |> request(pieces, request_info)

      # choke or unchoke message
      { :state, connection, socket, state } ->
        put_in(peers, [connection, :state], state)
        |> request(pieces, request_info)

      # received block
      { :received, connection, index, offset } ->
        pieces = received_block(pieces, index, offset)
        peers = update_in(peers, [connection, :load], &(&1 - 1))
        request peers, pieces, request_info

      after 3_000 ->
        request peers, pieces, request_info
    end
  end

  def request(peers, pieces, request_info, count \\ @request_count) do
    block = next_block(request_info, pieces)

    { connection, peer } = 
      peers_with_piece(peers, block[:index]) 
      |> Enum.shuffle()
      |> List.first()

    cond do 
      count == 0 ->
        manage_requests peers, pieces, request_info
      peer == nil ->
        request peers, pieces, request_info, count - 1
      true ->
        peers = 
          case send_block_request(peer[:socket], block) do
            :ok -> update_in(peers, [connection, :load], &(&1 + 1))
            _ -> Map.pop(peers, connection) |> elem(1)
          end
        request_info = raise_block_counter(request_info)
        pieces = pieces ++ [block]
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
    List.pop_at(pieces, piece_index) |> elem(1)
  end

  def add_peer(peers, connection, socket) do
    put_in(peers, [connection], 
           %{ state: :choked, socket: socket, load: 0, pieces: [] } )
  end

  def add_peer_state(peers, connection, socket, state) when is_atom(state) do
    if peers[connection] == nil do
      add_peer(peers, connection, socket)
      |> put_in([connection, :state], state)
    else
      put_in peers, [connection, :state], state
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
    new_peers = Enum.filter(peers, fn({connection, info}) -> 
      Enum.member?(info[:pieces], index) &&
      info[:state] == :unchoke &&
      info[:load] < @max_load
    end)
    if Enum.empty?(new_peers) do
      [{nil, nil}]
    else
      new_peers
    end
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

    Torrent.Logger.log :request, 
      "sending request: index #{index}, offset: #{offset}, size: #{size}"

    << request_length :: 32 >>
    <> << id :: 8 >>
    <> << index :: 32 >>
    <> << offset :: 32 >>
    <> << size :: 32 >>
  end

end
