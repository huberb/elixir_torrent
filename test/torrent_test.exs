defmodule TorrentTest do
  use ExUnit.Case
  doctest Torrent

  test "file size" do
    info = %{ length: 1277987, piece_length: 16384 }
    num_pieces = Torrent.Filehandler.num_pieces(info)
    last_piece_size = Torrent.Filehandler.last_piece_size(info)

    assert last_piece_size == 35
    assert num_pieces == 79
  end

  test "file size 2" do
    info = %{ length: 623902720, piece_length: 524288 }
    num_pieces = Torrent.Filehandler.num_pieces(info)
    last_piece_size = Torrent.Filehandler.last_piece_size(info)

    assert last_piece_size == 524288
    assert num_pieces == 1190
  end

  test "file size 3" do
    info = %{ length: 1513308160, piece_length: 524288 }
    # assert Torrent.Filehandler.num_pieces(info) == 2887
    # assert Torrent.hello() == :world
  end
end
