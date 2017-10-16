defmodule Torrent.Client do

  def connect(torrent_path, output_path) do

    meta_info = torrent_path |> 
    Torrent.Metainfo.parse

    body = meta_info["info"] |>
    Torrent.Tracker.request

    connect_all_peers(body, meta_info["info"])

    # peer_id = generate_peer_id
    # @meta_info = Torrent.Metainfo.parse(torrent_path, output_path)
    # Torrent.Tracker.request(listening_port: 6600, peer_id: peer_id)
  end

  defp generate_peer_id do
    id = "YI"
    version = "0020"
    :random.seed(:erlang.now)
    number = :random.uniform(1000000000000)
    number = number |> Integer.to_string |> String.rjust(13, ?0)
    "-#{id}#{version}#{number}"
  end

  def connect_all_peers(body, meta_info) do

    peers = body["peers"] |>
            :binary.bin_to_list |>
            Enum.split(6) |>
            Tuple.to_list |>
            parse_all_peers

    peers |> Enum.each(fn(p) ->
      connect_peer(p, meta_info)
    end)

  end

  def sha_sum(binary) do
    :crypto.hash(:sha, binary)
  end

  def parse_all_peers(peer_list) do
    peer_list |> Enum.map(&parse_peer/1)
  end

  def parse_peer(peer) do
    ip = peer |> Enum.take(4) |> Enum.join(".")
    port = [ Enum.at(peer, 4), Enum.at(peer, 5) ] |> parse_port
    { ip, port }
  end

  def parse_port(binary) do
    lower_byte = binary |> Enum.at(0) |> Integer.to_string(2)
    higher_byte = binary |> Enum.at(1) |> Integer.to_string(2)
    lower_byte <> higher_byte |> String.to_integer(2)
  end

  def connect_peer(peer, info_hash) do
    # generate a hash
    # first encode info_hash with bencode
    bencode = Bencoder.encode(info_hash)
    # then make a sha512 over it
    sha_info_hash = bencode |> sha_sum

    # handshake = "\x19BitTorrent protocol\x00\x00\x00\x00\x00\x00\x00\x00#{sha_info_hash}#{generate_peer_id}"
    handshake = sha_info_hash |> generate_handshake


    %{sha_info_hash: sha_info_hash, handshake: handshake, peer: peer}
    |> Torrent.Peer.connect
  end

  def generate_handshake(sha_info_hash) do
    bett = 19
    pstr = "BitTorrent protocol"
    peer_id = generate_peer_id

    << bett, pstr :: binary >> <>
    << 0, 0, 0, 0, 0, 0, 0, 0, sha_info_hash :: binary, peer_id :: binary >>
  end

end
