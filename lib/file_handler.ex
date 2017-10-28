defmodule Torrent.Filehandler do

  def start_link(file_path) do
    { ok, pid } = Task.start_link(fn -> loop([]) end)
    if ok != :ok do raise "Could not start File Process" end
    pid
  end

  defp loop(list) do

    receive do

      {:get, index, caller} ->
        send caller, Enum.at(list, index)
        loop(list)

      {:put, block} ->
        IO.puts "received block"
        loop(list ++ [block])

    end

  end
end
