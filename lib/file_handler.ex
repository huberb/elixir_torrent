defmodule Torrent.Filehandler do

  def start_link(tracker_info, output_path) do
    meta_info = tracker_info["info"]
    { ok, pid } = Task.start_link(fn -> loop([], meta_info) end)
    if ok != :ok do raise "Could not start File Process" end
    pid
  end

  defp loop(file_data, meta_info) do
    if complete?(file_data, meta_info) do
      IO.puts "file download complete"
      write_file(file_data, meta_info)
    end

    receive do
      {:get, index, caller} ->
        send caller, Enum.at(file_data, index)
        loop(file_data, meta_info)

      {:put, block} ->
        IO.puts "Filehandler recvieved data block"
        IO.inspect block
        IO.puts file_data |> length
        loop(file_data ++ [block], meta_info)
    end
  end

  # TODO: write the file while downloading
  def write_file(file_data, meta_info) do
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

  defp complete?(file_data, meta_info) do
    if length(file_data) == num_pieces(meta_info) + 1 do
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
