defmodule Torrent.Client do

  def connect(torrent_path, output_path) do
    Process.flag(:trap_exit, true)
    meta_info = torrent_path
                |> Torrent.Parser.parse_file

    writer_pid = Torrent.Filehandler.start_link(meta_info, output_path)

    meta_info
    |> Torrent.Tracker.request
    |> connect_all_peers(meta_info["info"], writer_pid)
  end

  def connect_all_peers(tracker_resp, meta_info, writer_pid) do
    tracker_resp["peers"]
    |> :binary.bin_to_list
    |> Enum.split(6)
    |> Tuple.to_list
    |> Torrent.Parser.parse_all_peers
    |> Enum.map(fn(p) -> connect_peer(p, meta_info, writer_pid) end)
    |> manage_peers(writer_pid)
  end

  def manage_peers(peer_pids, writer_pid) do
    if length(peer_pids) != 0 do
      receive do
        { :EXIT, from, :normal } ->
          IO.puts "Peer shut down!"
          peer_pids = List.delete(peer_pids, from)
          manage_peers(peer_pids, writer_pid)
      end
    end
  end

  def connect_peer(peer, meta_info, writer_pid) do
    %{
      meta_info: meta_info, 
      peer: peer,
      writer_pid: writer_pid
    } |> Torrent.Peer.connect
  end

end
