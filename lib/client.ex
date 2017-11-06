defmodule Torrent.Client do

  def connect(torrent_path, output_path) do
    Process.flag(:trap_exit, true)
    meta_info = torrent_path
                |> Torrent.Parser.parse_file

    requester_pid = Torrent.Request.start_link(meta_info)
    writer_pid = Torrent.Filehandler.start_link(meta_info, requester_pid, output_path)
    output_pid = Torrent.Output.start_link(self(), writer_pid, meta_info)

    info_structs = %{
      meta_info: meta_info, 
      writer_pid: writer_pid,
      requester_pid: requester_pid
    }

    meta_info
    |> Torrent.Tracker.request
    |> connect_all_peers(info_structs)
  end

  def connect_all_peers(tracker_resp, info_structs) do
    tracker_resp["peers"]
    |> Torrent.Parser.parse_all_peers
    |> Enum.map(fn(p) -> 
      Map.put(info_structs, :peer, p)
      |> Torrent.Peer.connect
    end)
    |> manage_peers(info_structs[:writer_pid])
  end

  def manage_peers(peer_pids, writer_pid) do
    if length(peer_pids) != 0 do
      receive do
        { :EXIT, from, :normal } ->
          peer_pids = remove_peer(peer_pids, from)
          manage_peers(peer_pids, writer_pid)

        { :output, pid } ->
          send pid, { :peers, peer_pids |> length }
          manage_peers(peer_pids, writer_pid)

        # TODO: use this
        { :finished } ->

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
