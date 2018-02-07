defmodule Torrent.Filehandler do

  def start_link(output_path) do

    { _, pid } = Task.start_link(fn -> 
      Process.flag(:priority, :high)

      %{ info: info } = Torrent.Metadata.wait_for_metadata()

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

      manage_files(%{}, file_info, info)
    end)
    pid
  end

  defp manage_files(file_data, file_info, info) do
    if download_complete?(file_info) do
      verify_file_length(file_data, file_info, info)
      send :client, { :finished }
    else
      receive do
        { :output } ->
          send :output, { :received, length(file_info[:recv_pieces]) }
          manage_files(file_data, file_info, info)

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

    if piece_size == byte_size(block) do
      send :request, { :received, index, from }
      send :client, { :received, index }

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

  def verify_file_length(file_data, file_info, meta_info) do
    path = "#{file_info[:output_path]}/#{meta_info[:name]}"
    %{ size: size } = File.stat! path
    if size != meta_info[:length] do
      require IEx
      IEx.pry
      raise "Wrong Filesize!"
    end
    IO.puts "Filesize correct: #{meta_info[:length]} bytes"
  end

  def mkdir_tmp do
    if !File.exists?("tmp") do
      # IO.puts "creating tmp file"
      File.mkdir("tmp")
    end
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
