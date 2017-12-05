defmodule Torrent do

  @moduledoc """
  Documentation for Torrent.
  """

  @doc """
  Hello world.

  ## Examples


  """
  def init do
    torrent = "./examples/arch.torrent"

    # ubuntu
    # torrent = "magnet:?xt=urn:btih:9f9165d9a281a9b8e782cd5176bbcc8256fd1871&dn=Ubuntu+16.04.1+LTS+Desktop+64-bit&tr=udp%3A%2F%2Ftracker.leechers-paradise.org%3A6969&tr=udp%3A%2F%2Fzer0day.ch%3A1337&tr=udp%3A%2F%2Fopen.demonii.com%3A1337&tr=udp%3A%2F%2Ftracker.coppersurfer.tk%3A6969&tr=udp%3A%2F%2Fexodus.desync.com%3A6969"
    
    # wallpapers
    torrent = "magnet:?xt=urn:btih:36fef15ba5642dc1db6fa59c1145d8c25095c348&dn=Most+Amazing+Collection+of+Computer+Desktop+HD+Wallpapers+282&tr=udp%3A%2F%2Ftracker.leechers-paradise.org%3A6969&tr=udp%3A%2F%2Fzer0day.ch%3A1337&tr=udp%3A%2F%2Fopen.demonii.com%3A1337&tr=udp%3A%2F%2Ftracker.coppersurfer.tk%3A6969&tr=udp%3A%2F%2Fexodus.desync.com%3A6969"

    output_path = 'tmp'

    meta_info = 
      case String.contains?(torrent, ".torrent") do
        true ->
          Torrent.Parser.parse_file(torrent)
        false ->
          Torrent.Parser.parse_magnet(torrent)
    end

    Torrent.Client.connect meta_info, output_path
  end

  def main(_) do
    Torrent.init
  end

end
