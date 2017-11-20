defmodule Torrent.Client do

  def connect(meta_info, output_path) do
    Process.flag(:trap_exit, true)

    requester_pid = Torrent.Request.start_link(meta_info)
    # writer_pid = Torrent.Filehandler.start_link(meta_info, requester_pid, self(), output_path)
    # output_pid = Torrent.Output.start_link(self(), writer_pid, meta_info)
     
    info_structs = %{
      meta_info: meta_info, 
      # writer_pid: writer_pid,
      requester_pid: requester_pid
    }
    
    meta_info
    |> Torrent.Tracker.request
    |> connect_all_peers(info_structs)
  end

  def connect_all_peers(tracker_resp, info_structs) do
    peers = Torrent.Parser.parse_all_peers(tracker_resp[:peers])

    peer_pids = Enum.map(peers, fn(p) -> 
                  Map.put(info_structs, :peer, p)
                  |> Torrent.Peer.connect
                end)

    manage_peers(peer_pids, info_structs[:requester_pid])
  end

  def manage_peers(peer_pids, requester_pid) do
    if length(peer_pids) != 0 do
      receive do
        { :EXIT, from, :normal } ->
          peer_pids = remove_peer(peer_pids, from)
          manage_peers(peer_pids, requester_pid)

        { :output, pid } ->
          send pid, { :peers, peer_pids |> length }
          manage_peers(peer_pids, requester_pid)

        { :finished } ->
          Process.exit(requester_pid, :kill)
          Enum.each(peer_pids, &(Process.exit(&1, :kill)))
          IO.puts "shutting down!"
      end
    else
      # TODO: close filehandler and requester?
    end
  end

  def remove_peer(peer_pids, pid) do
    peer_pids = List.delete(peer_pids, pid)
    len = peer_pids |> length |> to_string
    peer_pids
  end

end
