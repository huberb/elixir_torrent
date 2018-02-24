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
        Torrent.Logger.log :seeder, "opened port on #{port}"
        { socket, port }
      { :error, _ } -> 
        open_port(port + 1)
    end
  end

  def listen(client) do
    _ = Socket.Stream.recv(client)
    Torrent.Logger.log :seeder, "incoming connection, haha"
    :timer.sleep 1000
    listen(client)
  end

end
