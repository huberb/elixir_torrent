defmodule Torrent.Tracker do

  def request(torrent) do
    query = torrent |> generate_query |> get_body
  end

  def generate_query(torrent_info) do

    # hash = torrent_info |> Bencoder.encode |> sha_sum

    # ret = "#{torrent["announce"]}?info_hash=#{String.to_string(hash)}#{params}"

    "http://thomasballinger.com:6969/announce?info_hash=%2B%15%CA%2B%FDH%CD%D7m9%ECU%A3%AB%1B%8AW%18%0A%09&peer_id=78742315344684734465&port=6881&uploaded=0&downloaded=0&left=10000&compact=1&no_peer_id=0&event=started"
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
