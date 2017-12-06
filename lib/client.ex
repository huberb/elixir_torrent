defmodule Torrent.Client do

  def connect(meta_info, output_path) do
    Process.flag(:trap_exit, true)

    requester_pid = Torrent.Request.start_link()
    writer_pid = Torrent.Filehandler.start_link(requester_pid, self(), output_path)
    output_pid = Torrent.Output.start_link(self(), writer_pid)
    seeder_pid = Torrent.Seeder.start_link()

    Process.register(requester_pid, :requester)
     
    info_structs = %{
      meta_info: meta_info, 
      output_pid: output_pid, 
      writer_pid: writer_pid,
      requester_pid: :requester
    }

    metadata_pid = Torrent.Metadata.start_link(info_structs, meta_info)
    info_structs = put_in(info_structs, [:metadata_pid], metadata_pid)
    
    meta_info
    |> Torrent.Tracker.request
    |> connect_all_peers(info_structs)
  end

  def connect_all_peers(tracker_resp, info_structs) do
    peers = Torrent.Parser.parse_all_peers(tracker_resp[:peers])

    peer_pids = Enum.map(peers, fn(p) -> 
                  info_structs
                  |> Map.put(:peer, p)
                  |> Map.put(:parent_pid, self())
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
          Process.exit(info_structs[:requester_pid], :kill)
          Enum.each(peer_pids, &(Process.exit(&1, :kill)))
          IO.puts "shutting down!"
      end
    end
  end

  def remove_peer(peer_pids, pid) do
    List.delete(peer_pids, pid)
  end

end
