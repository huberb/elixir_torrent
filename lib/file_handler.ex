defmodule Torrent.Filehandler do

  def start_link(tracker_info, output_path) do
    meta_info = tracker_info["info"]
    { ok, pid } = Task.start_link(fn -> 
      loop(%{}, %{have: 0, need: num_pieces(meta_info)}) 
    end)
    pid
  end

  defp loop(file_data, count) do
    receive do
      {:get, caller, index} ->
        send caller, file_data[index]
        loop(file_data, count)

      {:put, block, index} ->
        IO.puts "Filehandler recieved data block"
        IO.inspect block
        if complete?(count) do
          write_file(file_data, count)
        else
          loop(
            file_data |> Map.put(index, block),
            count |> Map.update!(:have, fn i -> i + 1 end)
          )
        end
    end
  end

  def write_file(file_data, count) do
    require IEx
    IEx.pry
  end

  # TODO: write the file while downloading
  def write_file2(file_data, meta_info) do
    mkdir_tmp
    file_path = "tmp/file.jpg"
    File.rm_rf! file_path
    File.touch! file_path
    # file = File.open! file_path

    data = file_data 
           |> Enum.map(fn(d) -> Map.get(d, :data) end)
           |> Enum.reduce("", fn(d, acc) -> acc <> d end)

    File.write! file_path, data
    IO.puts "finished writing file to disk"
  end

  def mkdir_tmp do
    if !File.exists?("tmp") do
      IO.puts "creating tmp file"
      File.mkdir("tmp")
    end
  end

  defp complete?(count) do
    IO.puts "got #{count[:have]} from #{count[:need]}"
    if count[:need] == count[:have] do
      true
    else
      false
    end
  end

  def num_pieces(meta_info) do
    meta_info["length"] / meta_info["piece length"] |> round
  end

  def last_piece_length(meta_info) do 
    meta_info["length"] - meta_info["piece length"] * num_pieces(meta_info)
  end

end
