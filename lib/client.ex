defmodule Torrent.Client do

  def connect(meta_info, output_path) do
    Process.flag(:trap_exit, true)

    self()                                      |> Process.register(:client)
    Torrent.Request.start_link()                |> Process.register(:request)
    Torrent.Filehandler.start_link(output_path) |> Process.register(:writer)
    Torrent.Metadata.start_link(meta_info)      |> Process.register(:metadata)
    Torrent.Output.start_link()                 |> Process.register(:output)

    { seeder_pid, port } = Torrent.Seeder.start_link()
    Process.register(seeder_pid, :seeder)
    
    { tracker_pid, peers } = Torrent.Tracker.start_link(meta_info)
    Process.register(tracker_pid, :tracker)

    connect_all_peers(peers, %{ meta_info: meta_info })
  end

  def connect_all_peers(tracker_resp, info_structs) do
    peers = Torrent.Parser.parse_all_peers(tracker_resp[:peers])

    peer_pids = Enum.map(peers, fn(p) -> 
                  info_structs
                  |> Map.put(:peer, p)
                  |> Torrent.Peer.connect
                end)

    manage_peers(peer_pids, info_structs[:meta_info])
  end

  def manage_peers(peer_pids, meta_info) do
    if length(peer_pids) != 0 do
      receive do
        { :EXIT, from, :normal } -> # peer died
          peer_pids = remove_peer(peer_pids, from)
          manage_peers(peer_pids, meta_info)

        { :output } -> # output process needs info
          send :output, { :peers, peer_pids |> length }
          manage_peers(peer_pids, meta_info)

        { :meta_info, new_meta_info } -> # peer send the metainfo
          if meta_info[:info] do
            manage_peers(peer_pids, meta_info)
          else
            send_metadata_to_peers(peer_pids, new_meta_info)
            manage_peers(peer_pids, new_meta_info)
          end

        { :received, index } -> # piece is finished
          Enum.shuffle(peer_pids)
          |> Enum.take(2) 
          |> Enum.each(&(send(&1, { :received, index })))
          manage_peers(peer_pids, meta_info)

        { :finished } -> # download is finished
          Process.exit(:request, :kill)
          Process.exit(:seeder, :kill)
          Process.exit(:output, :kill)
          Process.exit(:metadata, :kill)
          Enum.each(peer_pids, &(Process.exit(&1, :kill)))
          IO.puts "shutting down!"
      end
    end
  end

  def send_metadata_to_peers(peer_pids, meta_info) do
    Enum.each(peer_pids, &(send(&1, { :meta_info, meta_info })))
  end

  def remove_peer(peer_pids, pid) do
    List.delete(peer_pids, pid)
  end

end
