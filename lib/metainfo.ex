defmodule Torrent.Metainfo do
  def parse(torrent_path) do

    # TODO: File Error
    { ok, content } = File.read(torrent_path)

    if ok == :ok do
      Bencoder.decode(content)
    else
      IO.puts "fail"
      IO.puts content
    end
  end

  def info_hash(torrent) do
    torrent["info"] |> Bencoder.encode |> sha_sum
  end

  def sha_sum(binary) do
    :crypto.hash(:sha, binary)
  end

end
