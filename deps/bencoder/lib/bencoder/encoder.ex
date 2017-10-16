defmodule Bencoder.Encode do
  @spec encode(term) :: String
  def encode(data) do
    Bencoder.Encoder.encode(data)
  end
end

defprotocol Bencoder.Encoder do
  @fallback_to_any true

  def encode(self)
end


defimpl Bencoder.Encoder, for: List do
  def encode(self) do
    y = Enum.map_join self, fn element ->
      Bencoder.Encode.encode(element)
    end
    << ?l, y :: binary, ?e >>
  end
end

defimpl Bencoder.Encoder, for: Map do
  def encode(self) do
    y = Enum.map_join self, fn { key, value } ->
      Bencoder.Encode.encode(to_string(key)) <> Bencoder.Encode.encode(value)
    end
    << ?d, y :: binary, ?e >>
  end
end

defimpl Bencoder.Encoder, for: Atom do
  def encode(true) do
    "1"
  end

  def encode(false) do
    "0"
  end

  def encode(nil) do
    "0"
  end
end

defimpl Bencoder.Encoder, for: Integer do
  def encode(self) do
    << ?i, to_string(self) :: binary, ?e >>
  end
end

defimpl Bencoder.Encoder, for: BitString do
  def encode(self) do
    << (self |> byte_size |> to_string) :: binary, ?:, self :: binary >>
  end
end


