defmodule Mapper do
  use GenServer
  require Logger

  defp xair_channel(:xair, channel, _channels), do: channel
  defp xair_channel(:xtouch, channel, channels), do: Enum.at(channels, channel)

  defp xtouch_indices(channel, channels) do
    channels
    |> Enum.with_index(fn
      ^channel, index -> index
      _, _ -> nil
    end)
    |> Enum.filter(&(&1 != nil))
  end

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @impl GenServer
  def init(_) do
    channels = Enum.slice(XAir.list_channels(), 0, 8)

    {:ok, timer} = :timer.send_interval(5000, :refresh)

    {:ok, %{channels: channels, timer: timer}}
  end

  @impl GenServer
  def handle_info(:refresh, state = %{channels: channels}) do
    _ =
      Enum.with_index(channels, fn channel, index ->
        GenServer.cast(XAir, {:gain, channel})
        GenServer.cast(XAir, {:channel_name, channel})
        GenServer.cast(XAir, {:solo, channel})
        GenServer.cast(XAir, {:mute, channel})
        GenServer.cast(XAir, {:mix_fader, channel})
      end)

    {:noreply, state}
  end

  @impl GenServer
  # Timed-out call
  def handle_info({_, _}, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:increment_channel, ch, by}, state = %{channels: channels}) do
    channels =
      List.update_at(channels, ch, fn channel ->
        channel_list = XAir.list_channels()
        current_index = Enum.find_index(channel_list, &(&1 == channel))
        Enum.at(channel_list, rem(current_index + by, Enum.count(channel_list)))
      end)

    GenServer.cast(Xtouch, {:set_lcd, ch, Enum.at(channels, ch), ""})

    send(self(), :refresh)

    {:noreply, %{state | channels: channels}}
  end

  @impl GenServer
  def handle_cast({:channel_name, source, channel, value}, state = %{channels: channels}) do
    xair_channel = xair_channel(source, channel, channels)
    xtouch_indices = xtouch_indices(xair_channel, channels)

    value =
      case value do
        "" -> xair_channel
        value -> value
      end

    Enum.each(
      xtouch_indices,
      &GenServer.cast(Xtouch, {:set_lcd, &1, value, ""})
    )

    if source != :xair, do: GenServer.cast(XAir, {:channel_name, xair_channel, value})

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:gain, source, headamp_channel, value}, state = %{channels: channels}) do
    xtouch_indices =
      channels
      |> Enum.with_index(fn ch, index ->
        try do
          if GenServer.call(XAir, {:input_src, ch}, 100) == headamp_channel, do: index
        catch
          :exit, {:timeout, _} ->
            Logger.info("get_input_src timed out")
            nil
        end
      end)
      |> Enum.filter(&(&1 != nil))

    xtouch_value = round(value * 10) + 1

    Enum.each(
      xtouch_indices,
      &GenServer.cast(Xtouch, {:set_led_ring, &1, false, :single_dot, xtouch_value})
    )

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:increment_gain, source, channel, value}, state = %{channels: channels}) do
    xair_channel = xair_channel(source, channel, channels)

    value = value / 144

    case GenServer.call(XAir, {:gain, xair_channel}) do
      nil ->
        nil

      current_gain ->
        new_gain = current_gain + value
        GenServer.cast(XAir, {:gain, xair_channel, new_gain})
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:solo, source, channel, value}, state = %{channels: channels}) do
    xair_channel = xair_channel(source, channel, channels)
    xtouch_indices = xtouch_indices(xair_channel, channels)

    Enum.each(
      xtouch_indices,
      &GenServer.cast(Xtouch, {:set_button, &1, :solo, value})
    )

    if source != :xair, do: GenServer.cast(XAir, {:solo, xair_channel, value})

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:toggle_solo_channel, source, channel}, state = %{channels: channels}) do
    xair_channel = xair_channel(source, channel, channels)

    current_solo = GenServer.call(XAir, {:solo, xair_channel})
    new_solo = !current_solo
    GenServer.cast(XAir, {:solo, xair_channel, new_solo})

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:mute, source, channel, value}, state = %{channels: channels}) do
    xair_channel = xair_channel(source, channel, channels)
    xtouch_indices = xtouch_indices(xair_channel, channels)

    Enum.each(
      xtouch_indices,
      &GenServer.cast(Xtouch, {:set_button, &1, :mute, value})
    )

    if source != :xair, do: GenServer.cast(XAir, {:mute, xair_channel, value})

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:toggle_mute_channel, source, channel}, state = %{channels: channels}) do
    xair_channel = xair_channel(source, channel, channels)

    current_mute = GenServer.call(XAir, {:mute, xair_channel})
    new_mute = !current_mute
    GenServer.cast(XAir, {:mute, xair_channel, new_mute})

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:fader_moved, source, channel, value}, state = %{channels: channels}) do
    xair_channel = xair_channel(source, channel, channels)
    xtouch_indices = xtouch_indices(xair_channel, channels)

    Enum.each(xtouch_indices, &GenServer.cast(Xtouch, {:set_fader, &1, value}))
    if source != :xair, do: GenServer.cast(XAir, {:mix_fader, xair_channel, value})

    {:noreply, state}
  end
end
