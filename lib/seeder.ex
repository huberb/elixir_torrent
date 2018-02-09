defmodule Torrent.Seeder do

  @standart_port 6881

  def start_link do
    { socket, port } = open_port(@standart_port)

    { _, pid } = Task.start_link(fn ->
      client = Socket.accept!(socket)
      listen(client)
    end)

    { pid, port }
  end

  def open_port(port) do
    case Socket.TCP.listen(port) do
      { :ok, socket } -> 
        send :output, { :seeder, "opened port on #{port}" }
        { socket, port }
      { :error, _ } -> 
        open_port(port + 1)
    end
  end

  def listen(client) do
    _ = Socket.Stream.recv!(client)
    send :output, { :seeder, "incoming connection, haha" }
    listen(client)
  end

end
