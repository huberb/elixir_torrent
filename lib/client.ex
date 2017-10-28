defmodule Torrent.Client do

  def connect(torrent_path, output_path) do
    meta_info = torrent_path
                |> Torrent.Parser.parse_file

    pid = Torrent.Filehandler.start_link(output_path)
    client_info = %{ writer_process: pid, output_path: output_path }

    meta_info
    |> Torrent.Tracker.request
    |> connect_all_peers(meta_info["info"], client_info)
  end

  def connect_all_peers(tracker_resp, meta_info, client_info) do
    tracker_resp["peers"]
    |> :binary.bin_to_list
    |> Enum.split(6)
    |> Tuple.to_list
    |> Torrent.Parser.parse_all_peers
    |> Enum.each(fn(p) -> connect_peer(p, meta_info, client_info) end)
  end

  def connect_peer(peer, meta_info, client_info) do
    %{
      meta_info: meta_info, 
      peer: peer,
      client_info: client_info
    } |> Torrent.Peer.connect
  end


end
