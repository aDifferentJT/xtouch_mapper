defmodule Midi do
  require Logger

  @type command ::
          {:note_off | :note_on, channel :: integer, note :: integer, velocity :: integer}
          | {:polyphonic_pressure, channel :: integer, note :: integer, pressure :: integer}
          | {:control_change, channel :: integer, controller :: integer, value :: integer}
          | {:program_change, channel :: integer, program :: integer}
          | {:channel_pressure, channel :: integer, pressure :: integer}
          | {:pitch_bend, channel :: integer, value :: integer}
          | {:sysex, data :: binary}
          | {:time_code_quarter, message_type :: integer, values :: integer}
          | {:song_position, value :: integer}
          | {:song_select, value :: integer}
          | :tune_request
          | :timing_clock
          | :start
          | :continue
          | :stop
          | :active_sensing
          | :reset

  def inc_seq(seq) do
    <<seq::16>> = <<seq + 1::16>>
    seq
  end

  defp encode_delta_time(x) do
    case <<x::32>> do
      <<0::25, d::7>> -> <<0::1, d::7>>
      <<0::18, c::7, d::7>> -> <<1::1, c::7, 0::1, d::7>>
      <<0::11, b::7, c::7, d::7>> -> <<1::1, b::7, 1::1, c::7, 0::1, d::7>>
      <<0::4, a::7, b::7, c::7, d::7>> -> <<1::1, a::7, 1::1, b::7, 1::1, c::7, 0::1, d::7>>
    end
  end

  defp decode_delta_time(<<0::1, d::7, rest::binary>>) do
    <<x::32>> = <<0::25, d::7>>
    {x, rest}
  end

  defp decode_delta_time(<<1::1, c::7, 0::1, d::7, rest::binary>>) do
    <<x::32>> = <<0::18, c::7, d::7>>
    {x, rest}
  end

  defp decode_delta_time(<<1::1, b::7, 1::1, c::7, 0::1, d::7, rest::binary>>) do
    <<x::32>> = <<0::11, b::7, c::7, d::7>>
    {x, rest}
  end

  defp decode_delta_time(<<1::1, a::7, 1::1, b::7, 1::1, c::7, 0::1, d::7, rest::binary>>) do
    <<x::32>> = <<0::4, a::7, b::7, c::7, d::7>>
    {x, rest}
  end

  @spec encode_command(command) :: binary

  def encode_command({:note_off, channel, note, velocity}) do
    <<0b1000::4, channel::4, 0::1, note::7, 0::1, velocity::7>>
  end

  def encode_command({:note_on, channel, note, velocity}) do
    <<0b1001::4, channel::4, 0::1, note::7, 0::1, velocity::7>>
  end

  def encode_command({:polyphonic_pressure, channel, note, pressure}) do
    <<0b1010::4, channel::4, 0::1, note::7, 0::1, pressure::7>>
  end

  def encode_command({:control_change, channel, controller, value}) do
    <<0b1011::4, channel::4, 0::1, controller::7, 0::1, value::7>>
  end

  def encode_command({:program_change, channel, program}) do
    <<0b1100::4, channel::4, 0::1, program::7>>
  end

  def encode_command({:channel_pressure, channel, pressure}) do
    <<0b1101::4, channel::4, 0::1, pressure::7>>
  end

  def encode_command({:pitch_bend, channel, value}) do
    <<high::7, low::7>> = <<value::14>>
    <<0b1110::4, channel::4, 0::1, low::7, 0::1, high::7>>
  end

  def encode_command({:sysex, data}) do
    <<0b11110000::8, data::binary, 0b11110111::8>>
  end

  def encode_command({:time_code_quarter, message_type, values}) do
    <<0b11110001::8, 0::1, message_type::3, values::4>>
  end

  def encode_command({:song_position, value}) do
    <<high::7, low::7>> = <<value::14>>
    <<0b11110010::8, 0::1, low::7, 0::1, high::7>>
  end

  def encode_command({:song_select, value}) do
    <<0b11110011::8, 0::1, value::7>>
  end

  def encode_command(:tune_request) do
    <<0b11110110::8>>
  end

  def encode_command(:timing_clock) do
    <<0b11111000::8>>
  end

  def encode_command(:start) do
    <<0b11111010::8>>
  end

  def encode_command(:continue) do
    <<0b11111011::8>>
  end

  def encode_command(:stop) do
    <<0b11111100::8>>
  end

  def encode_command(:active_sensing) do
    <<0b11111110::8>>
  end

  def encode_command(:reset) do
    <<0b11111111::8>>
  end

  @spec decode_command(binary) :: {command, binary}

  def decode_command(<<0b1000::4, channel::4, 0::1, note::7, 0::1, velocity::7, rest::binary>>) do
    {{:note_off, channel, note, velocity}, rest}
  end

  def decode_command(<<0b1001::4, channel::4, 0::1, note::7, 0::1, velocity::7, rest::binary>>) do
    {{:note_on, channel, note, velocity}, rest}
  end

  def decode_command(<<0b1010::4, channel::4, 0::1, note::7, 0::1, pressure::7, rest::binary>>) do
    {{:polyphonic_pressure, channel, note, pressure}, rest}
  end

  def decode_command(<<0b1011::4, channel::4, 0::1, controller::7, 0::1, value::7, rest::binary>>) do
    {{:control_change, channel, controller, value}, rest}
  end

  def decode_command(<<0b1100::4, channel::4, 0::1, program::7, rest::binary>>) do
    {{:program_change, channel, program}, rest}
  end

  def decode_command(<<0b1101::4, channel::4, 0::1, pressure::7, rest::binary>>) do
    {{:channel_pressure, channel, pressure}, rest}
  end

  def decode_command(<<0b1110::4, channel::4, 0::1, low::7, 0::1, high::7, rest::binary>>) do
    <<value::14>> = <<high::7, low::7>>
    {{:pitch_bend, channel, value}, rest}
  end

  def decode_command(<<0b11110000::8, rest::binary>>) do
    [data, rest] = :binary.split(rest, <<0b11110111>>)
    {{:sysex, data}, rest}
  end

  def decode_command(<<0b11110001::8, 0::1, message_type::3, values::4, rest::binary>>) do
    {{:time_code_quarter, message_type, values}, rest}
  end

  def decode_command(<<0b11110010::8, 0::1, low::7, 0::1, high::7, rest::binary>>) do
    <<value::14>> = <<high::7, low::7>>
    {{:song_position, value}, rest}
  end

  def decode_command(<<0b11110011::8, 0::1, value::7, rest::binary>>) do
    {{:song_select, value}, rest}
  end

  def decode_command(<<0b11110100::8, rest::binary>>) do
    {:undefined, rest}
  end

  def decode_command(<<0b11110101::8, rest::binary>>) do
    {:undefined, rest}
  end

  def decode_command(<<0b11110110::8, rest::binary>>) do
    {:tune_request, rest}
  end

  def decode_command(<<0b11111000::8, rest::binary>>) do
    {:timing_clock, rest}
  end

  def decode_command(<<0b11111001::8, rest::binary>>) do
    {:undefined, rest}
  end

  def decode_command(<<0b11111010::8, rest::binary>>) do
    {:start, rest}
  end

  def decode_command(<<0b11111011::8, rest::binary>>) do
    {:continue, rest}
  end

  def decode_command(<<0b11111100::8, rest::binary>>) do
    {:stop, rest}
  end

  def decode_command(<<0b11111101::8, rest::binary>>) do
    {:undefined, rest}
  end

  def decode_command(<<0b11111110::8, rest::binary>>) do
    {:active_sensing, rest}
  end

  def decode_command(<<0b11111111::8, rest::binary>>) do
    {:reset, rest}
  end

  def encode_commands(journalling, p, commands) do
    journalling = if journalling, do: 1, else: 0
    delta_time_0 = 1
    p = if p, do: 1, else: 0

    list =
      Enum.into(commands, <<>>, fn {delta_time, command} ->
        <<encode_delta_time(delta_time)::binary, encode_command(command)::binary>>
      end)

    <<max_small::4>> = <<-1::4>>

    {big, len} =
      if byte_size(list) > max_small do
        {1, <<byte_size(list)::12>>}
      else
        {0, <<byte_size(list)::4>>}
      end

    <<big::1, journalling::1, delta_time_0::1, p::1, len::bitstring, list::binary>>
  end

  def encode_rtp(sequence_number, timestamp, ssrc, commands) do
    header = %RTP.Header{
      marker: Enum.count(commands) > 0,
      payload_type: 97,
      sequence_number: sequence_number,
      timestamp: timestamp,
      ssrc: ssrc
    }

    <<RTP.Header.encode(header)::binary, encode_commands(false, false, commands)::binary>>
  end

  def decode_rtp(data) do
    {header, data} = RTP.Header.decode(data)

    {_journalling, delta_time_0, _p, list, data} =
      case data do
        <<0::1, journalling::1, delta_time_0::1, p::1, len::4, list::binary-size(len),
          data::binary>> ->
          {journalling, delta_time_0, p, list, data}

        <<1::1, journalling::1, delta_time_0::1, p::1, len::12, list::binary-size(len),
          data::binary>> ->
          {journalling, delta_time_0, p, list, data}
      end

    list =
      case delta_time_0 do
        0 -> <<0::8, list::binary>>
        1 -> list
      end

    commands =
      Stream.unfold(list, fn
        <<>> ->
          nil

        data ->
          case decode_delta_time(data) do
            {_delta_time, <<>>} ->
              nil

            {delta_time, data} ->
              {message, data} = decode_command(data)
              {{delta_time, message}, data}
          end
      end)

    _ = data

    {header, commands}
  end
end
