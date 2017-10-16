defmodule Bencoder do
  defdelegate encode(data), to: Bencoder.Encode
  defdelegate decode(data), to: Bencoder.Decode
end

