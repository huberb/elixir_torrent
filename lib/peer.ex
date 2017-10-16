defmodule Torrent.Peer do

  def connect(peer_struct) do 

    { ip, port } = peer_struct[:peer]

    IO.puts ip

    try do
      socket = Socket.TCP.connect!(ip, port, packet: :line) 
      socket |> handshake(peer_struct[:handshake])
    rescue
      e -> IO.puts(e.message)
        if e.message != "host is unreachable" do
          raise e
        end
    end

  end

  def handshake(socket, hash) do
    IO.puts "init handshake: "

    socket |> Socket.Stream.send!(hash)
    message = socket |> Socket.Stream.recv!

    require IEx
    IEx.pry
    # IO.puts message
  end

end
