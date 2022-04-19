defmodule AppleMidi do
  require Logger

  def encode_exchange_packet(command, token, ssrc, name) do
    <<0xFF, 0xFF, command::binary-size(2), 2::32, token::32, ssrc::32, name::binary, 0>>
  end

  def decode_exchange_packet(
        <<0xFF, 0xFF, command::binary-size(2), 2::32, token::32, ssrc::32, name::binary>>
      ) do
    {command, token, ssrc, name}
  end

  def decode_timestamp_sync(
        <<0xFF, 0xFF, "CK", _sender_ssrc::32, 0::8, padding::24, timestamp1::64, _timestamp2::64,
          timestamp3::64>>,
        ssrc,
        current_timestamp
      ) do
    {:reply,
     <<0xFF, 0xFF, "CK", ssrc::32, 1::8, padding::24, timestamp1::64, current_timestamp::64,
       timestamp3::64>>}
  end

  def decode_timestamp_sync(
        <<0xFF, 0xFF, "CK", _sender_ssrc::32, 1::8, padding::24, timestamp1::64, timestamp2::64,
          _timestamp3::64>>,
        ssrc,
        current_timestamp
      ) do
    {:reply,
     <<0xFF, 0xFF, "CK", ssrc::32, 2::8, padding::24, timestamp1::64, timestamp2::64,
       current_timestamp::64>>}
  end

  def decode_timestamp_sync(
        <<0xFF, 0xFF, "CK", _sender_ssrc::32, 2::8, _padding::24, timestamp1::64, timestamp2::64,
          timestamp3::64>>,
        _ssrc,
        _current_timestamp
      ) do
    {:offset, (timestamp3 + timestamp1) / 2 - timestamp2}
  end
end
