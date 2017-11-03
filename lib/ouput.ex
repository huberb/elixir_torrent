defmodule Torrent.Output do

  def start_link(parent, requester, num_pieces) do
    { ok, pid } = Task.start_link(fn ->
      output = %{ num_peers: 0, requests: 0, received: 0, max: num_pieces }
      pipe_output(output, %{ parent: parent, requester: requester })
    end)
    pid
  end

  def get_outputs_from_processes(output, count) do
    if count != 0 do
      receive do
        { :peers, num_peers } ->
          put_in(output, [:num_peers], num_peers)
          |> get_outputs_from_processes(count - 1)

        { :requested , num_requested, num_received } ->
          put_in(output, [:requests], num_requested)
          |> put_in([:received], num_received)
          |> get_outputs_from_processes(count - 1)
      end
    else
      output
    end
  end

  def pipe_output(output, processes) do
    :timer.sleep(1000)
    send processes[:parent], { :output, self() }
    send processes[:requester], { :output, self() }

    output = get_outputs_from_processes(output, 2)

    IO.puts "peers: #{output[:num_peers]}, received: #{output[:received]}, requested: #{output[:requests]}, left: #{output[:max] - output[:received]}"

    pipe_output(output, processes)
  end

end
