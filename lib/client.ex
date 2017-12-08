defmodule Torrent.Client do

  def connect(meta_info, output_path) do
    Process.flag(:trap_exit, true)

    self()                                      |> Process.register(:client)
    Torrent.Request.start_link()                |> Process.register(:request)
    Torrent.Filehandler.start_link(output_path) |> Process.register(:writer)
    Torrent.Output.start_link()                 |> Process.register(:output)
    Torrent.Metadata.start_link(meta_info)      |> Process.register(:metadata)
    Torrent.Tracker.start_link(meta_info)       |> Process.register(:tracker)

    { seeder_pid, port } = Torrent.Seeder.start_link()
    Process.register seeder_pid, :seeder
    

    # peer_pids = connect_all_peers peers, meta_info
    manage_peers [], meta_info
  end

  def connect_all_peers(tracker_resp, meta_info) do
    peers = Torrent.Parser.parse_all_peers tracker_resp[:peers]

    Enum.map(peers, fn(peer) -> 
      %{ meta_info: meta_info, peer: peer }
      |> Torrent.Peer.connect
    end)

  end

  def manage_peers(peer_pids, meta_info) do
    unless Enum.empty? peer_pids do
      receive do
        { :EXIT, from, :normal } -> # peer died
          peer_pids = List.delete peer_pids, from
          manage_peers peer_pids, meta_info

        { :output } -> # output process needs info
          send :output, { :peers, peer_pids |> length }
          manage_peers peer_pids, meta_info

        { :tracker, tracker_resp } -> # tracker cycle serves new peers
          new_pids = connect_all_peers(tracker_resp, meta_info)
          manage_peers peer_pids ++ new_pids, meta_info

        { :meta_info, new_meta_info } -> # peer send the metainfo
          if meta_info[:info] do
            manage_peers peer_pids, meta_info
          else
            send_metadata_to_peers peer_pids, new_meta_info
            manage_peers peer_pids, new_meta_info
          end

        { :received, index } -> # piece is finished
          Enum.shuffle(peer_pids)
          |> Enum.take(1) # TODO: how many?
          |> Enum.each(&(send(&1, { :received, index })))
          manage_peers peer_pids, meta_info

        { :finished } -> # download is finished
          Enum.each peer_pids, &(Process.exit(&1, :kill))
          shutdown()
          IO.puts "shutting down!"
      end
    else # if we dont have peers we can only wait for the tracker to send more
      receive do
        { :tracker, tracker_resp } -> # tracker cycle serves new peers
          new_pids = connect_all_peers(tracker_resp, meta_info)
          manage_peers peer_pids ++ new_pids, meta_info
      end
    end
  end

  def shutdown do
    processes = [:output, :tracker, :metadata, :request, :seeder]
    Enum.each processes, fn(name) ->
      pid = Process.whereis name
      Process.unregister name
      Process.exit pid, :kill
    end
    Process.unregister :client
  end

  def send_metadata_to_peers(peer_pids, meta_info) do
    Enum.each peer_pids, &(send(&1, { :meta_info, meta_info }))
  end

end
