defmodule Torrent do

  def init(torrent, output_path) do

    meta_info = 
      case String.contains?(torrent, ".torrent") do
        true ->
          Torrent.Parser.parse_file(torrent)
        false ->
          Torrent.Parser.parse_magnet(torrent)
    end

    :observer.start()
    put_in(meta_info, [:max_peers], 20)
    |> Torrent.Client.connect(output_path)
  end

  def init do
    torrent = "magnet:?xt=urn:btih:11bc35b9dcc7b16170bea84fe221607eae9a43b0&dn=80+Amazing+NASA+Pictures+Wallpapers+%5B1920+X+1200%5D+HQ+-+%7BRedDrago&tr=udp%3A%2F%2Ftracker.leechers-paradise.org%3A6969&tr=udp%3A%2F%2Fzer0day.ch%3A1337&tr=udp%3A%2F%2Fopen.demonii.com%3A1337&tr=udp%3A%2F%2Ftracker.coppersurfer.tk%3A6969&tr=udp%3A%2F%2Fexodus.desync.com%3A6969"
    init(torrent, "tmp")
  end

end
