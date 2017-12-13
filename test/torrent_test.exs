defmodule TorrentTest do
  use ExUnit.Case
  doctest Torrent

  test "file size" do
    info = %{ length: 1277987, piece_length: 16384 }
    last_block_size = Torrent.Filehandler.last_block_size(info)
    num_pieces = Torrent.Filehandler.num_pieces(info)
    last_piece_size = Torrent.Filehandler.last_piece_size(info)
    blocks_in_last_piece = Torrent.Filehandler.blocks_in_last_piece(info)
    num_blocks_in_piece = Torrent.Filehandler.num_blocks_in_piece(info)

    assert last_piece_size == 35
    assert last_block_size == 35
    assert blocks_in_last_piece == 0 # TODO: fix this
    assert num_blocks_in_piece == 1
    assert num_pieces == 79
  end

  test "file size 2" do
    info = %{ length: 1513308160, piece_length: 524288 }
    assert Torrent.Filehandler.num_pieces(info) == 2887
    # assert Torrent.hello() == :world
  end
end
