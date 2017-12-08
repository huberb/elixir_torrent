defmodule TorrentTest do
  use ExUnit.Case
  doctest Torrent

  test "file size" do
    info = %{ length: 1277987, piece_length: 16384 }
    assert Torrent.Filehandler.num_pieces(info) == 79
    # assert Torrent.hello() == :world

  end

  test "file size 2" do
    info = %{ length: 1513308160, piece_length: 524288 }
    Torrent.Filehandler.num_pieces(info) == 2887
    # assert Torrent.hello() == :world
  end
end
