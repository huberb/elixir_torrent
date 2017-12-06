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
    
    meta_info
    |> Torrent.Tracker.request
    |> connect_all_peers( %{ meta_info: meta_info })
  end

  def connect_all_peers(tracker_resp, info_structs) do
    peers = Torrent.Parser.parse_all_peers(tracker_resp[:peers])

    peer_pids = Enum.map(peers, fn(p) -> 
                  info_structs
                  |> Map.put(:peer, p)
                  |> Torrent.Peer.connect
                end)

    manage_peers(peer_pids, info_structs)
  end

  def manage_peers(peer_pids, info_structs) do
    if length(peer_pids) != 0 do
      receive do
        { :EXIT, from, :normal } ->
          peer_pids = remove_peer(peer_pids, from)
          manage_peers(peer_pids, info_structs)

        { :output, pid } ->
          send pid, { :peers, peer_pids |> length }
          manage_peers(peer_pids, info_structs)

        { :finished } ->
          Process.exit(:request, :kill)
          Process.exit(:seeder, :kill)
          Process.exit(:output, :kill)
          Enum.each(peer_pids, &(Process.exit(&1, :kill)))
          IO.puts "shutting down!"
      end
    end
  end

  def remove_peer(peer_pids, pid) do
    List.delete(peer_pids, pid)
  end

end
