defmodule Bencoder.Decode do
  @doc """
  Decodes a binary and translates it into elixir objects.

  Returns the decoded element.

  `number` -> `Integer`
  `string` -> `String`
  `list`   -> `List`
  `dict`   -> `Map`

  """
  @spec decode(binary) :: term
  def decode(data) do
    {:ok, decoded, _} = data |> :binary.bin_to_list |> decode_element
    decoded
  end

  @doc """
  Decodes each element and returns a list with the non-consumed input

  Returns `{ :ok, element, non_consumed }`

  """
  @spec decode_element(List.binary) :: { :ok, List.t | Map.t | Integer | binary, List.binary }
  defp decode_element(chars) do
    case hd(chars) do
      ?i ->
        decode_integer(chars)
      ?l ->
        decode_list(chars)
      ?d ->
        decode_dictionary(chars)
      _ ->
        decode_string(chars)
    end
  end

  defp decode_integer(chars) do
    digits = Enum.take_while(tl(chars), fn (x) -> x != ?e end)
    {number, _} = ('0' ++ digits) |> to_string |> Integer.parse
    {:ok, number, Enum.drop(chars, 2 + length(digits))}
  end

  defp decode_list(chars) do
    decode_list_elements(tl(chars), [])
  end

  defp decode_list_elements(chars, z) do
    case hd(chars) do
      ?e ->
        {:ok, z, tl(chars)}
      _ ->
        {:ok, decoded, remaining} = decode_element(chars)
        decode_list_elements(remaining, z ++ [decoded])
    end
  end

  defp decode_dictionary(chars) do
    decode_dictionary_elements(tl(chars), %{})
  end

  defp decode_dictionary_elements(chars, map) do
    case hd(chars) do
      ?e ->
        {:ok, map, tl(chars)}
      _ ->
        {:ok, decoded_key, remaining} = decode_element(chars)
        {:ok, decoded_value, remaining} = decode_element(remaining)
        decode_dictionary_elements(remaining, Map.put(map, decoded_key, decoded_value))
    end
  end

  defp decode_string(binary) do
    digits = Enum.take_while(binary, fn (x) -> x != ?: end)
    {s, _} = digits |> to_string |> Integer.parse
    word = Enum.drop(binary, length(digits) + 1)
    {:ok, :binary.list_to_bin(Enum.take(word, s)), Enum.drop(word, s)}
  end
end
