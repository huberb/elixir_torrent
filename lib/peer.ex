defmodule Torrent.Peer do

  def connect(peer_struct) do 

    { ip, port } = peer_struct[:peer]

    IO.puts ip

    try do
      socket = Socket.TCP.connect!(ip, port, packet: :line) 
      socket |> say_hello(peer_struct[:handshake])
    rescue
      e -> IO.puts(e.message)
        if e.message != "host is unreachable" do
          raise e
        end
    end

  end

  def say_hello(socket, handshake) do
    IO.puts "init handshake: "
    socket |> Socket.Stream.send!(handshake)
    socket |> Socket.Stream.recv! |> hear_hello
  end

  def hear_hello(message) do 
    require IEx
    IEx.pry
    start_talking
  end

  def start_talking do
  end

end
