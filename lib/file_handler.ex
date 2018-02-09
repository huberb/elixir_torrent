defmodule Torrent.Filehandler do

  def start_link(output_path) do

    { _, pid } = Task.start_link(fn -> 
      Process.flag(:priority, :high)

      %{ info: info } = Torrent.Metadata.wait_for_metadata()
      info = update_in(info, [:name], &(escape_filename(&1)))

      mkdir_tmp()
      path = "#{output_path}/#{info[:name]}"
      File.rm(path)
      File.touch(path)
      { _, file } = :file.open(path, [:read, :write, :binary])

      file_info = %{
        pieces_needed: num_pieces(info),
        last_piece_size: last_piece_size(info),
        piece_info: info[:pieces],
        output_path: output_path,
        file: file,
        piece_length: info[:piece_length],
        recv_pieces: []
      }

      send :output, { :meta_info, file_info[:pieces_needed] }

      manage_files(%{}, file_info, info)
    end)
    pid
  end

  defp manage_files(file_data, file_info, info) do
    if download_complete?(file_info) do
      send :torrent, { :finished }
      verify_file_length(file_data, file_info, info)
    else
      receive do
        { :tracker } ->
          send :tracker, { :received, length(file_info[:recv_pieces]) }
          manage_files(file_data, file_info, info)

        { :put, block, index, offset } ->
          if index in file_info[:recv_pieces] do # already have this
            manage_files(file_data, file_info, info)
          else
            { file_data, file_info } = add_block(file_data, file_info, index, offset, block)
            manage_files(file_data, file_info, info)
          end
      end
    end
  end

  def add_block(file_data, file_info, index, offset, block) do
    file_data = 
      case file_data[index] do
        nil ->
          file_data |> Map.put(index, %{})
        _ ->
          file_data
      end

    put_in(file_data, [index, offset], block)
    |> block_completed(file_info, index, block[:peer])
  end

  def add_piece(file_data, index, block, from) do
    file_data
    |> pop_in([index]) 
    |> elem(1)
    |> put_in([index], %{})
    |> put_in([index, :data], block)
    |> put_in([index, :peer], from)
  end

  def block_completed(file_data, file_info, index, from) do
    piece_size = cond do
      index == file_info[:pieces_needed] - 1 -> file_info[:last_piece_size]
      true -> file_info[:piece_length]
    end
    block = concat_block(file_data[index])

    # piece complete?
    if piece_size == byte_size(block) do
      send :request, { :received, index, from }
      send :torrent, { :received, index }
      send :output, { :writer, "piece #{index} complete" }

      Torrent.Parser.verify_piece(file_info[:piece_info], index, block)
      file_info = update_in(file_info, [:recv_pieces], &(&1 ++ [index]))
      file_data = add_piece(file_data, index, block, from)
      file_data = write_piece(file_data, file_info, index)
      { file_data, file_info }
    else
      { file_data, file_info }
    end
  end

  def concat_block(block) do
    block 
    |> Enum.sort_by(fn({offset, _}) -> offset end)
    |> Enum.map(fn({_, block}) -> block[:data] end)
    |> Enum.join("")
  end

  def write_piece(file_data, file_info, index) do
    offset = file_info[:piece_length] * index
    :file.position(file_info[:file], offset)
    :file.write(file_info[:file], file_data[index][:data])
    # remove data from struct to save memory
    # IO.puts "free up space.."
    pop_in(file_data, [index]) |> elem(1)
  end

  defp verify_file_length(file_data, file_info, meta_info) do
    path = "#{file_info[:output_path]}/#{meta_info[:name]}"
    %{ size: size } = File.stat! path
    if size != file_length(meta_info) do
      require IEx
      IEx.pry
      raise "Wrong Filesize!"
    end
    if multi_file?(meta_info) do
      split_into_files(path, meta_info)
    end
    send :output, { :finish, "Filesize correct: #{file_length(meta_info)} bytes" }
  end

  # TODO: not good enough
  defp split_into_files(source_file_path, meta_info) do
    tmp_source_file_name = source_file_path <> "tmp"
    File.rename(source_file_path, tmp_source_file_name)
    File.mkdir(source_file_path)
    split_into_files(source_file_path, tmp_source_file_name, meta_info, 0)
  end

  defp split_into_files(dest_folder, source_file, meta_info, written_bytes) do
    if length(meta_info[:files]) != 0 do
      file = List.first(meta_info[:files])
      path = escape_filename(dest_folder <> "/" <> Enum.join(file[:path], "/"))
      File.mkdir_p(Path.dirname(path))
      File.touch(path)

      { _, src_fileIO } = :file.open(source_file, [:read, :write, :binary])
      { _, dst_fileIO } = :file.open(path, [:read, :write, :binary])

      :file.position(src_fileIO, written_bytes)
      { _, data } = :file.read(src_fileIO, file[:length])
      :file.write(dst_fileIO, data)

      meta_info = update_in(meta_info, [:files], &(List.delete_at(&1, 0)))
      split_into_files(dest_folder, source_file, meta_info, written_bytes + file[:length])
    else
      File.rm_rf(source_file)
    end
  end

  defp mkdir_tmp do
    unless File.exists?("tmp") do
      # IO.puts "creating tmp file"
      File.mkdir("tmp")
    end
  end

  defp escape_filename(name) do
    name 
    |> String.downcase 
    |> String.replace(" ", "_")
    |> String.replace(".", "_")
    |> String.replace(",", "_")
    |> String.replace(":", "_")
    |> String.replace(";", "_")
    |> String.replace("(", "_")
    |> String.replace(")", "_")
    |> String.replace("[", "_")
    |> String.replace("]", "_")
    |> String.replace("}", "_")
    |> String.replace("{", "_")
  end

  defp download_complete?(file_info) do
    length(file_info[:recv_pieces]) == file_info[:pieces_needed]
  end

  def num_pieces(meta_info) do
    num = file_length(meta_info) / meta_info[:piece_length]
    if trunc(num) == num, do: trunc(num), else: trunc(num) + 1
  end

  def file_length(meta_info) do
    if multi_file?(meta_info) do
      len = Enum.map(meta_info[:files], fn(file) -> file[:length] end)
            |> Enum.reduce(0, fn(len, acc) -> acc + len end)
    else
      meta_info[:length]
    end
  end

  def multi_file?(meta_info) do
    if meta_info[:length] == nil, do: true, else: false
  end

  def last_piece_size(meta_info) do
    piece_len = meta_info[:piece_length] 
    num_pieces = num_pieces(meta_info) - 1
    file_length(meta_info) - piece_len * num_pieces
  end

end
