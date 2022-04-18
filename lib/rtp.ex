defmodule RTP do
  defmodule Header do
    @enforce_keys [
      :marker,
      :payload_type,
      :sequence_number,
      :timestamp,
      :ssrc
    ]
    defstruct [
      :marker,
      :payload_type,
      :sequence_number,
      :timestamp,
      :ssrc,
      csrcs: [],
      extension: nil
    ]

    def encode(%Header{
          marker: marker,
          payload_type: payload_type,
          sequence_number: sequence_number,
          timestamp: timestamp,
          ssrc: ssrc,
          csrcs: csrcs,
          extension: extension
        }) do
      version = 2
      padding = false

      padding = if padding, do: 1, else: 0
      marker = if marker, do: 1, else: 0

      csrc_count = Enum.count(csrcs)
      csrcs = Enum.into(csrcs, <<>>, fn csrc -> <<csrc::32>> end)

      extension_flag = if extension, do: 1, else: 0

      extension =
        case extension do
          nil ->
            <<>>

          {id, data} ->
            length = div(bit_size(data), 32)
            <<id::16, length::16, data::binary>>
        end

      <<version::2, padding::1, extension_flag::1, csrc_count::4, marker::1, payload_type::7,
        sequence_number::16, timestamp::32, ssrc::32, csrcs::binary, extension::binary>>
    end

    def decode(
          <<version::2, padding::1, extension_flag::1, csrc_count::4, marker::1, payload_type::7,
            sequence_number::16, timestamp::32, ssrc::32, csrcs::binary-size(csrc_count)-unit(32),
            rest::bitstring>>
        ) do
      csrcs =
        Stream.unfold(csrcs, fn
          <<>> -> nil
          <<csrc::32, rest::bitstring>> -> {csrc, rest}
        end)

      {extension, rest} =
        case extension_flag do
          0 ->
            {nil, rest}

          1 ->
            <<id::16, length::16, data::binary-size(length)-unit(32), rest::bitstring>> = rest
            {{id, data}, rest}
        end

      rest =
        case padding do
          0 ->
            rest

          1 ->
            init_size = byte_size(rest) - 1
            <<_::binary-size(init_size), padding>> = rest
            data_size = byte_size(rest) - padding
            <<rest::binary-size(data_size), _::binary-size(padding)>> = rest
            rest
        end

      {%Header{
         marker: marker,
         payload_type: payload_type,
         sequence_number: sequence_number,
         timestamp: timestamp,
         ssrc: ssrc,
         csrcs: csrcs,
         extension: extension
       }, rest}
    end
  end
end
