defmodule Osc do
  defp encode_string(s) do
    terminator_size = 4 - rem(byte_size(s), 4)
    <<s::binary, 0::size(terminator_size)-unit(8)>>
  end

  defp decode_string(data), do: decode_string("", data)

  defp decode_string(acc, <<0, 0, 0, 0, data::binary>>) do
    {acc, data}
  end

  defp decode_string(acc, <<str::binary-size(1), 0, 0, 0, data::binary>>) do
    {acc <> str, data}
  end

  defp decode_string(acc, <<str::binary-size(2), 0, 0, data::binary>>) do
    {acc <> str, data}
  end

  defp decode_string(acc, <<str::binary-size(3), 0, data::binary>>) do
    {acc <> str, data}
  end

  defp decode_string(acc, <<str::binary-size(4), data::binary>>) do
    decode_string(acc <> str, data)
  end

  defp encode_argument(x) when is_integer(x), do: {"i", <<x::integer-big-32>>}
  defp encode_argument(x) when is_float(x), do: {"f", <<x::float-big-32>>}

  defp encode_argument({:string, x}) when is_binary(x) do
    {"s", encode_string(x)}
  end

  defp encode_argument({:blob, x}) when is_binary(x) do
    terminator_size = 3 - rem(byte_size(x) - 1, 4)
    {"b", <<byte_size(x)::integer-big-32, x::binary, 0::size(terminator_size)-unit(8)>>}
  end

  defp decode_argument({<<"i", types::binary>>, <<x::integer-big-32, data::binary>>}) do
    {x, {types, data}}
  end

  defp decode_argument({<<"f", types::binary>>, <<x::float-big-32, data::binary>>}) do
    {x, {types, data}}
  end

  defp decode_argument({<<"s", types::binary>>, data}) do
    {x, data} = decode_string(data)
    {x, {types, data}}
  end

  defp decode_argument(
         {<<"b", types::binary>>, <<size::integer-big-32, x::binary-size(size), data::binary>>}
       ) do
    terminator_size = 3 - rem(size - 1, 4)
    <<_::size(terminator_size)-unit(8), data::binary>> = data
    {x, {types, data}}
  end

  defp decode_argument({<<>>, <<>>}) do
    nil
  end

  def encode_message(address, arguments) do
    {types, arguments} = Enum.unzip(Enum.map(arguments, &encode_argument/1))
    types = Enum.into(types, <<",">>)
    arguments = Enum.into(arguments, <<>>)
    <<encode_string(address)::binary, encode_string(types)::binary, arguments::binary>>
  end

  def decode_message(data) do
    {address, data} = decode_string(data)
    {<<",", types::binary>>, data} = decode_string(data)
    arguments = Enum.to_list(Stream.unfold({types, data}, &decode_argument/1))
    {address, arguments}
  end

  def encode_bundle(messages) do
    # Immediately
    timetag = <<1::64>>

    Enum.into(messages, <<encode_string("#bundle")::binary, timetag::binary>>, fn message ->
      <<byte_size(message)::32, message::binary>>
    end)
  end
end
