defmodule Torrent.Client do

  def connect(torrent_path, output_path) do
    meta_info = torrent_path
                |> Torrent.Metainfo.parse

    body = meta_info["info"]
           |> Torrent.Tracker.request
           |> connect_all_peers(meta_info["info"])
  end

  def connect_all_peers(tracker_resp, meta_info) do
    tracker_resp["peers"]
    |> :binary.bin_to_list
    |> Enum.split(6)
    |> Tuple.to_list
    |> parse_all_peers
    |> Enum.each(fn(p)
      -> connect_peer(p, meta_info)
    end)
  end

  def connect_peer(peer, info_hash) do
    sha_info_hash = info_hash
                    |> Bencoder.encode
                    |> sha_sum

    handshake = sha_info_hash 
                |> generate_handshake

    %{
      sha_info_hash: sha_info_hash, 
      handshake: handshake, 
      peer: peer
    } |> Torrent.Peer.connect
  end

  def parse_all_peers(peer_list) do
    peer_list |> Enum.map(&parse_peer/1)
  end

  def parse_peer(peer) do
    # Bytes 0 to 3 are be IP Adress as Binary
    ip = peer 
         |> Enum.take(4) 
         |> Enum.join(".")

         # Byte 4 and 5 are the Port, 
         # this needs to be read as a 2 Byte Integer
    port = [ Enum.at(peer, 4), Enum.at(peer, 5) ] 
           |> parse_port

    { ip, port }
  end

  def parse_port(binary) do
    lower_byte = binary |> Enum.at(0) |> Integer.to_string(2)
    higher_byte = binary |> Enum.at(1) |> Integer.to_string(2)
    lower_byte <> higher_byte |> String.to_integer(2)
  end

  defp generate_handshake(sha_info_hash) do
    # The Number 19 in Binary followed by the Protocol String
    << 19, "BitTorrent protocol" :: binary >> <>
      # add 8 Zeros and the SHA Hash from the Tracker info, 20 Bytes long
    << 0, 0, 0, 0, 0, 0, 0, 0, sha_info_hash :: binary, >> <>
      # some Peer ID, also 20 Bytes long
    << generate_peer_id :: binary >>
  end

  defp generate_peer_id do
    # TODO: generate better Peer_id
    id = "BE"
    version = "0044"
    :random.seed(:erlang.now)
    number = :random.uniform(1000000000000)
    number = number |> Integer.to_string |> String.rjust(13, ?0)
    "-#{id}#{version}#{number}"
  end

  defp sha_sum(binary) do
    :crypto.hash(:sha, binary)
  end
end
