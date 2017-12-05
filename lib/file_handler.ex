defmodule Torrent.Filehandler do

  def start_link(requester_pid, parent, output_path) do

    { _, pid } = Task.start_link(fn -> 

      %{ info: info } = Torrent.Metadata.wait_for_metadata()

      mkdir_tmp()
      path = "#{output_path}/#{info[:name]}"
      File.rm(path)
      File.touch(path)
      { _, file } = :file.open(path, [:read, :write, :binary])

      file_info = %{
        pieces_needed: num_pieces(info),
        blocks_in_piece: num_blocks_in_piece(info),
        piece_info: info[:pieces],
        requester_pid: requester_pid,
        parent_pid: parent,
        output_path: output_path,
        file: file,
        piece_length: info[:"piece length"],
        recv_pieces: []
      }

      manage_files(%{}, file_info, info)
    end)
    pid
  end

  defp manage_files(file_data, file_info, info) do
    if download_complete?(file_info) do
      send file_info[:parent_pid], { :finished }
      verify_file_length(file_data, file_info, info)
    else
      receive do
        {:output, pid } ->
          send pid, { :received, length(file_info[:recv_pieces]) }
          manage_files(file_data, file_info, info)

        {:put, block, index, offset } ->
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
    |> verify_piece(file_info, index, block[:peer])
  end

  def add_piece(file_data, index, block, from) do
    file_data
    |> pop_in([index]) 
    |> elem(1)
    |> put_in([index], %{})
    |> put_in([index, :data], block)
    |> put_in([index, :peer], from)
  end

  def verify_piece(file_data, file_info, index, from) do
    recv_block_len = file_data[index] |> Map.keys |> length

    if recv_block_len == file_info[:blocks_in_piece] do
      send file_info[:requester_pid], { :received, index, from }
      block = concat_block(file_data[index])
      Torrent.Parser.validate_block(file_info[:piece_info], index, block)

      file_info = update_in(file_info, [:recv_pieces], &(&1 ++ [index]))

      file_data = add_piece(file_data, index, block, from)
      file_data = write_piece(file_data, file_info, index)

      { file_data, file_info }
    else
      { file_data, file_info }
    end
  end

  def concat_data(file_data) do
    file_data
    |> Enum.sort_by(fn({index, _}) -> index end)
    |> Enum.map(fn({_, block}) -> block[:data] end)
    |> Enum.reduce("", fn(data, acc) -> acc <> data end)
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

  def num_blocks(meta_info) do
    num_pieces(meta_info) * num_blocks_in_piece(meta_info)
    |> round
  end

  def num_blocks_in_piece(meta_info) do
    meta_info[:"piece length"] / Torrent.Request.data_request_len
  end

  def num_pieces(meta_info) do
    num = meta_info[:length] / meta_info[:"piece length"]
    if trunc(num) == num do
      round(num)
    else
      round(num) + 1
    end
  end

  def last_piece_size(meta_info) do
    file_length = meta_info[:length] 
    piece_len = meta_info[:"piece length"] 
    num_pieces = num_pieces(meta_info) - 1
    file_length - piece_len * num_pieces
  end

  def last_block_size(meta_info) do 
    data_request_len = Torrent.Request.data_request_len
    last_piece_size(meta_info) - (num_blocks_in_piece(meta_info) - 1) * data_request_len
    |> round
  end

end
