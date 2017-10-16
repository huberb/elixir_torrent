defmodule Bencoder.Mixfile do
  use Mix.Project

  def project do
    [app: :bencoder,
     version: "0.0.7",
     elixir: "~> 1.0.0",
     description: "a library to handle bencode in elixir",
     package: package,
     deps: deps]
  end

  defp package do
    [ contributors: ["alehander42"],
      licenses: ["MIT"],
      links: %{"Github" => "https://github.com/alehander42/bencoder"}]
  end

  defp deps do
    []
  end
end
