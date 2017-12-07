defmodule Torrent.Seeder do

  @standart_port 6881

  def start_link do
    { socket, port } = open_port(@standart_port)

    { _, pid } = Task.start_link(fn ->
      listen(socket)
    end)

    { pid, port }
  end

  def open_port(port) do
    case Socket.TCP.listen(port) do
      { :ok, socket } -> 
        IO.puts "opened port on #{port}"
        { socket, port }
      { :error, _ } -> 
        open_port(port + 1)
    end
  end

  def listen(socket) do
    client = Socket.accept!(socket)
    data = Socket.Stream.recv!(client)
    IO.puts "incoming connection, haha"
  end

end
