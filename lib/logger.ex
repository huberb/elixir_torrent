defmodule Torrent.Logger do

  def log(from, message) do
    IO.puts "#{from}: #{message}"
  end

end
