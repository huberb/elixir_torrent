defmodule Torrent do

  def init(torrent, output_path) do

    meta_info = 
      case String.contains?(torrent, ".torrent") do
        true ->
          Torrent.Parser.parse_file(torrent)
        false ->
          Torrent.Parser.parse_magnet(torrent)
      end

    # :observer.start()
    put_in(meta_info, [:max_peers], 200)
    |> Torrent.Client.connect(output_path)
  end

  def init do
    init(torrent, "tmp")
  end

end
