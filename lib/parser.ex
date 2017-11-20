defmodule Torrent.Parser do

  def parse_file(torrent_path) do

    # TODO: File Error
    { ok, content } = File.read(torrent_path)

    unless ok == :ok do
      raise "No Torrent File"
    end

    content = Bencoder.decode(content) |> keys_to_atom
    content = put_in(content, [:hash], 
              content[:info] |> Bencoder.encode |> sha_sum)
  end

  def keys_to_atom(map) do
    if is_list(map) do
      map
    else
      map |> Enum.reduce(%{}, fn({key, val}, acc) -> 
        if is_binary(val) || is_integer(val) do
          put_in(acc, [String.to_atom(key)], val)
        else
          put_in(acc, [String.to_atom(key)], keys_to_atom(val))
        end
      end)
    end
  end

  def parse_magnet(magnet_link) do
    magnet_parts = magnet_link
                   |> URI.decode
                   |> String.split("&")
                   |> parse_magnet_parts([])

    announce_list = Enum.filter(magnet_parts, &(elem(&1, 0) == "tr" ) )
                    |> Enum.map(&(elem(&1, 1)))

    announce = Enum.at(announce_list, 0)

    hash = Enum.filter(magnet_parts, &(elem(&1, 0) == "magnet:?xt" ) )
           |> Enum.map( &(elem(&1, 1)) )
           |> Enum.at(0)
           |> String.trim("urn:btih:")
           |> String.upcase
           |> Base.decode16
           |> elem(1)

    %{
      announce: announce,
      announce_list: announce_list,
      hash: hash
    }
  end

  def parse_magnet_parts(parts, list) do
    if Enum.empty?(parts) do
      list
    else
      { part, parts }  = List.pop_at(parts, 0)
      part = part |> String.split("=") |> List.to_tuple
      parse_magnet_parts(parts, list ++ [part])
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

    peers |> Enum.take(20)
  end

  def peer_extensions(options) do
    use Bitwise
    options_dec = :binary.decode_unsigned(options)
    extensions = :math.pow(2, 20) |> trunc
    %{
      extensions: (options_dec &&& extensions) != 0
    }
  end

  defp parse_peer(peer) do
    # Bytes 0 to 3 are be IP Adress as Binary
    ip = peer 
         |> Enum.take(4) 
         |> Enum.join(".")

         # Byte 4 and 5 are the Port, 
         # this needs to be read as a 2 Byte Integer
    port = Enum.slice(peer, 4..5) 
           |> :binary.list_to_bin
           |> :binary.decode_unsigned
    { ip, port }
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
