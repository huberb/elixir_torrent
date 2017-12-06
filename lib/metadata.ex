defmodule Torrent.Metadata do

  # this process can start in two ways
  # either we have the metadata and send it to everyone immediatly
  # or we need to wait for it and send it after we got it from a peer
  def start_link(meta_info) do
    { _, pid } = Task.start_link(fn ->
      if meta_info[:info] == nil do # we dont have the metadata
        IO.puts "wait for metadata"
        meta_info = wait_for_metadata()
        send_metadata(meta_info)
      else # we have the metadata
        send_metadata(meta_info)
      end
      stay_alive()
    end)
    pid
  end

  def stay_alive() do
    wait_for_metadata()
    stay_alive()
  end

  def send_metadata(meta_info) do
    send :request, { :meta_info, meta_info }
    send :writer, { :meta_info, meta_info }
    send :output, { :meta_info, meta_info }
    IO.puts "send all metadata"
  end

  def wait_for_metadata do
    receive do
      { :meta_info, meta_info } ->
        meta_info
    end
  end

end
