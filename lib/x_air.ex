defmodule XAir do
  use GenServer
  require Logger

  @port 10024

  def int_to_bool(0), do: false
  def int_to_bool(1), do: true

  def bool_to_int(false), do: 0
  def bool_to_int(true), do: 1

  def list_channels_full() do
    [
      {"/ch/01", 1},
      {"/ch/02", 2},
      {"/ch/03", 3},
      {"/ch/04", 4},
      {"/ch/05", 5},
      {"/ch/06", 6},
      {"/ch/07", 7},
      {"/ch/08", 8},
      {"/ch/09", 9},
      {"/ch/10", 10},
      {"/ch/11", 11},
      {"/ch/12", 12},
      {"/ch/13", 13},
      {"/ch/14", 14},
      {"/ch/15", 15},
      {"/ch/16", 16},
      {"/rtn/aux", 17},
      {"/bus/1", 40},
      {"/bus/2", 41},
      {"/bus/3", 42},
      {"/bus/4", 43},
      {"/bus/5", 44},
      {"/bus/6", 45},
      {"/lr", 50}
    ]
  end

  def list_channels() do
    Enum.map(list_channels_full(), fn {ch, _} -> ch end)
  end

  def standing_replies_ch(ch, "/mix/on", [value]) do
    GenServer.cast(Mapper, {:mute, :xair, ch, !int_to_bool(value)})
  end

  def standing_replies_ch(ch, "/mix/fader", [value]) do
    GenServer.cast(Mapper, {:fader_moved, :xair, ch, value})
  end

  def standing_replies_ch(_, _, _), do: nil

  def standing_replies(<<"/ch/", ch::binary-size(2), param::binary>>, args) do
    standing_replies_ch("/ch/" <> ch, param, args)
  end

  def standing_replies(<<"/rtn/aux", param::binary>>, args) do
    standing_replies_ch("/rtn/aux", param, args)
  end

  def standing_replies(<<"/bus/", bus::binary-size(1), param::binary>>, args) do
    standing_replies_ch("/rtn/aux", param, args)
  end

  def standing_replies(<<"/-stat/solosw/", ch::binary-size(2)>>, [value]) do
    {ch, _} = Integer.parse(ch)

    case Enum.find(list_channels_full(), fn {_, solo_ch} -> solo_ch == ch end) do
      {ch, _} ->
        GenServer.cast(Mapper, {:solo, :xair, ch, int_to_bool(value)})

      nil ->
        nil
    end
  end

  def standing_replies(_, _), do: nil

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  def init(ip) do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: true])

    {:ok, timer} = :timer.send_interval(5000, :remote)

    {:ok, %{socket: socket, ip: ip, timer: timer, waiting_replies: %{}}}
  end

  def handle_call(
        {:channel_name, ch},
        from,
        state = %{socket: socket, ip: ip, waiting_replies: waiting_replies}
      ) do
    address = ch <> "/config/name"

    :gen_udp.send(
      socket,
      ip,
      @port,
      Osc.encode_message(address, [])
    )

    on_reply = fn [name] -> GenServer.reply(from, name) end
    waiting_replies = Map.update(waiting_replies, address, [on_reply], &[on_reply | &1])

    {:noreply, %{state | waiting_replies: waiting_replies}}
  end

  def handle_call(
        {:solo, ch},
        from,
        state = %{socket: socket, ip: ip, waiting_replies: waiting_replies}
      ) do
    {_, ch} =
      Enum.find(list_channels_full(), fn
        {^ch, _} -> true
        _ -> false
      end)

    address = "/-stat/solosw/" <> String.pad_leading(Integer.to_string(ch), 2, "0")

    :gen_udp.send(
      socket,
      ip,
      @port,
      Osc.encode_message(address, [])
    )

    on_reply = fn [solo] -> GenServer.reply(from, int_to_bool(solo)) end

    waiting_replies = Map.update(waiting_replies, address, [on_reply], &[on_reply | &1])

    {:noreply, %{state | waiting_replies: waiting_replies}}
  end

  def handle_call(
        {:mute, ch},
        from,
        state = %{socket: socket, ip: ip, waiting_replies: waiting_replies}
      ) do
    address = ch <> "/mix/on"

    :gen_udp.send(
      socket,
      ip,
      @port,
      Osc.encode_message(address, [])
    )

    on_reply = fn [on] -> GenServer.reply(from, !int_to_bool(on)) end

    waiting_replies = Map.update(waiting_replies, address, [on_reply], &[on_reply | &1])

    {:noreply, %{state | waiting_replies: waiting_replies}}
  end

  def handle_call(
        {:mix_fader, ch},
        from,
        state = %{socket: socket, ip: ip, waiting_replies: waiting_replies}
      ) do
    address = ch <> "/mix/fader"

    :gen_udp.send(
      socket,
      ip,
      @port,
      Osc.encode_message(address, [])
    )

    on_reply = fn [level] -> GenServer.reply(from, level) end
    waiting_replies = Map.update(waiting_replies, address, [on_reply], &[on_reply | &1])

    {:noreply, %{state | waiting_replies: waiting_replies}}
  end

  def handle_cast(
        {:solo, ch, value},
        state = %{socket: socket, ip: ip}
      ) do
    {_, ch} =
      Enum.find(list_channels_full(), fn
        {^ch, _} -> true
        _ -> false
      end)

    address = "/-stat/solosw/" <> String.pad_leading(Integer.to_string(ch), 2, "0")

    :gen_udp.send(
      socket,
      ip,
      @port,
      Osc.encode_message(address, [bool_to_int(value)])
    )

    {:noreply, state}
  end

  def handle_cast(
        {:mute, ch, value},
        state = %{socket: socket, ip: ip}
      ) do
    address = ch <> "/mix/on"

    :gen_udp.send(
      socket,
      ip,
      @port,
      Osc.encode_message(address, [bool_to_int(!value)])
    )

    {:noreply, state}
  end

  def handle_cast(
        {:mix_fader, ch, value},
        state = %{socket: socket, ip: ip}
      ) do
    address = ch <> "/mix/fader"

    :gen_udp.send(
      socket,
      ip,
      @port,
      Osc.encode_message(address, [value])
    )

    {:noreply, state}
  end

  def handle_info(
        {:udp, socket, address, _, data},
        state = %{waiting_replies: waiting_replies}
      ) do
    {address, arguments} = Osc.decode_message(data)
    standing_replies(address, arguments)
    {replies, waiting_replies} = Map.pop(waiting_replies, address, [])
    Enum.each(replies, & &1.(arguments))
    {:noreply, %{state | waiting_replies: waiting_replies}}
  end

  def handle_info(:remote, state = %{socket: socket, ip: ip}) do
    :gen_udp.send(
      socket,
      ip,
      @port,
      Osc.encode_message("/xremote", [])
    )

    {:noreply, state}
  end
end
