defmodule TorrentTest do
  use ExUnit.Case
  doctest Torrent

  test "greets the world" do
    assert Torrent.hello() == :world
  end
end
