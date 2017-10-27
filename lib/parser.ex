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
    peers = peer_list |> Enum.map(&parse_peer/1) |> List.delete_at(0)
  end

  defp parse_peer(peer) do
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

end
