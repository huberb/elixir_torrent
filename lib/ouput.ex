defmodule Torrent.Output do

  def start_link() do
    { _, pid } = Task.start_link(fn ->
      output_loop(%{ completed: 0 })
    end)
    pid
  end

  def log(from, message) do
    IO.puts "#{from}: #{message}"
  end

  def output_loop(info) do
    IO.puts "got #{info[:completed]} / #{info[:needed]}"
    receive do
      { from, message } ->
        case from do
          :meta_info ->
            log(from, message)
            put_in(info, [:needed], message)
            |> output_loop
          :writer ->
            update_in(info, [:completed], &(&1 + 1))
            |> output_loop()
          _ ->
            log(from, message)
            output_loop(info)
        end
    end
  end
end
