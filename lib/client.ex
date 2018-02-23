defmodule Torrent.Client do

  def connect(meta_info, output_path) do
    Process.flag(:trap_exit, true)

    self()                                      |> Process.register(:torrent_client)
    Torrent.Request.start_link()                |> Process.register(:request)
    Torrent.Tracker.start_link(meta_info)       |> Process.register(:tracker)
    Torrent.Filehandler.start_link(output_path) |> Process.register(:writer)
    Torrent.Metadata.start_link(meta_info)      |> Process.register(:metadata)

    { seeder_pid, port } = Torrent.Seeder.start_link()
    Process.register seeder_pid, :seeder
    
    meta_info = put_in(meta_info, [:peers], [])
    send :tracker, { :received, 0 }
    manage_peers [], meta_info
  end

  def connect_all_peers(peers, meta_info) do
    # Torrent.Logger.log :client, "connecting #{Enum.count(peers)} new peers"

    Enum.map(peers, fn(peer) -> 
      %{ meta_info: meta_info, peer: peer }
      |> Torrent.Peer.connect
    end)
  end

  def manage_peers(peer_pids, meta_info) do
    # Torrent.Logger.log :client, "connected with #{Enum.count(peer_pids)} peers"
    { peer_pids, meta_info } = connect_some_peers(meta_info, peer_pids)
    receive do
      { :EXIT, from, :normal } -> # peer died
        peer_pids = List.delete peer_pids, from
        manage_peers peer_pids, meta_info

      { :meta_info, new_meta_info } -> # peer send the metainfo
        if meta_info[:info] do
          manage_peers peer_pids, meta_info
        else
          send_metadata_to_peers peer_pids, new_meta_info
          manage_peers peer_pids, new_meta_info
        end

      { :received, index } -> # piece is finished
        Enum.shuffle(peer_pids)
        |> Enum.take(1) # TODO: how many?
        |> Enum.each(&(send(&1, { :received, index })))
        manage_peers peer_pids, meta_info

      { :tracker, tracker_resp } -> # tracker cycle serves new peers
        peers = Torrent.Parser.parse_all_peers(tracker_resp[:peers])
        peers = meta_info[:peers] ++ peers |> Enum.uniq
        meta_info = put_in(meta_info, [:peers], peers)
        { peer_pids, meta_info } = connect_some_peers(meta_info, peer_pids)
        manage_peers(peer_pids, meta_info)

      { :finished } -> # download is finished
        Enum.each peer_pids, &(Process.exit(&1, :kill))
        shutdown()
    end
  end

  def connect_some_peers(meta_info, peer_pids) do
    number_of_new_connections = meta_info[:max_peers] - Enum.count(peer_pids)
    if number_of_new_connections > 0 && Enum.count(meta_info[:peers]) > 0 do
      all_connections = meta_info[:peers]
      new_connections = all_connections |> Enum.slice(0..number_of_new_connections)
                        |> connect_all_peers(meta_info)
      left_connections = all_connections |> Enum.slice(number_of_new_connections..-1)
      meta_info = put_in(meta_info, [:peers], all_connections ++ left_connections |> Enum.uniq)
      { new_connections ++ peer_pids, meta_info }
    else
      { peer_pids, meta_info }
    end
  end

  def shutdown do
    processes = [:tracker, :metadata, :request, :seeder]
    Enum.each processes, fn(name) ->
      pid = Process.whereis name
      Process.unregister name
      Process.exit pid, :kill
    end
    Process.unregister :torrent_client
  end

  def send_metadata_to_peers(peer_pids, meta_info) do
    Enum.each peer_pids, &(send(&1, { :meta_info, meta_info }))
  end

end
