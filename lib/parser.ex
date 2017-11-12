defmodule Torrent.Parser do

  def parse_file(torrent_path) do

    # TODO: File Error
    { ok, content } = File.read(torrent_path)

    if ok == :ok do
      Bencoder.decode(content)
    else
      raise "No Torrent File"
    end
  end

  def parse_all_peers(peer_list) do
    # the delete_at(0) is to delete my own ip
    peers = peer_list 
            |> :binary.bin_to_list
            |> Enum.split(6)
            |> Tuple.to_list
            |> List.delete_at(0)
            |> Enum.at(0)
            |> Enum.chunk(6)
            |> Enum.map(&parse_peer/1) 

    # this is a development hack to debug a low number of peers
    # peers |> Enum.take(10)
  end

  defp parse_peer(peer) do
    # Bytes 0 to 3 are be IP Adress as Binary
    ip = peer 
         |> Enum.take(4) 
         |> Enum.join(".")

    # Byte 4 and 5 are the Port, 
    # this needs to be read as a 2 Byte Integer
    # TODO: use kernel methods here
    port = [ Enum.at(peer, 4), Enum.at(peer, 5) ] 
           |> parse_port

    { ip, port }
  end

  def parse_port(binary) do
    lower_byte = binary |> Enum.at(0) |> Integer.to_string(2)
    higher_byte = binary |> Enum.at(1) |> Integer.to_string(2)
    lower_byte <> higher_byte |> String.to_integer(2)
  end

  def parse_bitfield(bitfield) do
    bitfield
    |> :binary.bin_to_list
    |> Enum.map(fn(i) -> Integer.to_string(i, 2) end)
    |> Enum.map(&make_len_8/1)
    |> Enum.join("")
    |> String.graphemes
  end

  def validate_block(pieces, index, data) do
    foreign_hash = data |> sha_sum
    real_hash = pieces |> binary_part(index * 20, 20)
    if foreign_hash != real_hash do
      raise "Hash Validation failed on Piece! Abort!"
    else
      # IO.puts "validated piece Nr: #{index}"
    end
  end

  defp make_len_8(binary_str) do
    if binary_str |> String.length == 8 do
      binary_str
    else
      make_len_8("0" <> binary_str)
    end
  end

  def sha_sum(binary) do
    :crypto.hash(:sha, binary)
  end

end
