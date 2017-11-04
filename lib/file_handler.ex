defmodule Torrent.Filehandler do

  def start_link(tracker_info, requester_pid, output_path) do
    meta_info = tracker_info["info"]
    file_info = %{
      have: 0,
      pieces_needed: num_pieces(meta_info), 
      blocks_in_piece: num_blocks_in_piece(meta_info),
      piece_info: meta_info["pieces"],
      requester_pid: requester_pid
    }

    { ok, pid } = Task.start_link(fn -> 
      manage_files( %{}, file_info, meta_info)
    end)
    pid
  end

  defp manage_files(file_data, file_info, meta_info) do
    receive do
      {:output, pid } ->
        send pid, { :received, file_data |> Map.to_list |> length }
        manage_files(file_data, file_info, meta_info)

      {:put, block, index, offset } ->
        { file_data, file_info } = file_data |> add_block(file_info, index, offset, block)
        if download_complete?(file_data, file_info) do
          require IEx
          IEx.pry
          write_file(file_data, file_info)
        else
          manage_files(file_data, file_info, meta_info)
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

  def verify_piece(file_data, file_info, index, from) do
    recv_block_len = file_data[index] |> Map.keys |> length
    file_info = 
      cond do
        recv_block_len == file_info[:blocks_in_piece] -> 
          Torrent.Parser.validate_block(file_info[:piece_info], index, file_data[index])
          send file_info[:requester_pid], { :received, index, from }
          file_info

        true -> file_info
      end
    { file_data, file_info }
  end

  def write_file(file_data, count) do
    require IEx
    IEx.pry
  end

  def mkdir_tmp do
    if !File.exists?("tmp") do
      # IO.puts "creating tmp file"
      File.mkdir("tmp")
    end
  end

  defp download_complete?(file_data, file_info) do
    recv_count = file_data |> Map.to_list |> length
    if recv_count == file_info[:pieces_needed] do
      true
    else
      false
    end
  end

  def num_blocks(meta_info) do
    num_pieces(meta_info) * num_blocks_in_piece(meta_info)
    |> round
  end

  def num_blocks_in_piece(meta_info) do
    num = meta_info["piece length"] / Torrent.Request.data_request_len
    if num == trunc(num), do: num, else: trunc(num) + 1
  end

  def num_pieces(meta_info) do
    num = meta_info["length"] / meta_info["piece length"] - 1
    # if num == trunc(num), do: round(num), else: num + 1 |> trunc |> round
    if num == trunc(num) do
      num |> round
    else
      num + 1 |> round
    end
  end

  def last_block_size(meta_info) do
    piece_len = meta_info["piece length"]
    blocks_in_piece = num_blocks_in_piece(meta_info) - 1
    data_len = Torrent.Request.data_request_len
    piece_len - blocks_in_piece * data_len
  end

  def last_piece_size(meta_info) do 
    file_length = meta_info["length"] 
    piece_len = meta_info["piece length"] 
    num_pieces = num_pieces(meta_info)
    file_length - piece_len * num_pieces
  end

end
