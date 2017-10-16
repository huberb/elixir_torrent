defmodule Torrent.Client do

  def connect(torrent_path, output_path) do
    meta_info = torrent_path
                |> Torrent.Parser.parse_file

    body = meta_info["info"]
           |> Torrent.Tracker.request
           |> connect_all_peers(meta_info["info"])
  end

  def connect_all_peers(tracker_resp, meta_info) do
    tracker_resp["peers"]
    |> :binary.bin_to_list
    |> Enum.split(6)
    |> Tuple.to_list
    |> Torrent.Parser.parse_all_peers
    |> Enum.each(fn(p)
      -> connect_peer(p, meta_info)
    end)
  end

  def connect_peer(peer, info_hash) do
    %{
      info_hash: info_hash, 
      peer: peer
    } |> Torrent.Peer.connect
  end


end
