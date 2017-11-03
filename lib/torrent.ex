defmodule Torrent do

  @moduledoc """
  Documentation for Torrent.
  """

  @doc """
  Hello world.

  ## Examples


  """
  def init do
    torrent_path = './examples/ubuntu.torrent'
    output_path = './downloads/'
    Torrent.Client.connect torrent_path, output_path
  end

  def main(_) do
    Torrent.init
  end

end
