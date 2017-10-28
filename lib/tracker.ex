defmodule Torrent.Tracker do

  def request(torrent) do
    query = torrent |> generate_query |> get_body
  end

  def generate_query(torrent_info) do
    # TODO: dont hardcode port
    port = 6881
    info_hash = torrent_info["info"]
                |> Bencoder.encode
                |> Torrent.Parser.sha_sum

    # TODO: less hardcode
    query = %{
      "info_hash"  => info_hash,
      "port"       => port,
      "peer_id"    => 78742315344684734465,
      "uploaded"   => 0,
      "downloaded" => 0,
      "event"      => "started",
      "left"       => 10000,
      "compact"    => 1,
      "no_peer_id" => 0,
      "event"      => "started"
    } |> URI.encode_query

    torrent_info["announce"] <> "?" <> query
  end

  defp get_body(query) do
    HTTPoison.start

    case HTTPoison.get(query) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        Bencoder.decode(body)

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        IO.puts "Not found :("
        raise "404"

      {:error, %HTTPoison.Error{reason: reason}} ->
        IO.inspect reason
        raise "TrackerError"
    end
  end

end
