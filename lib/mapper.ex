defmodule Mapper do
  use GenServer

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

  def init(_) do
    channels = Enum.slice(XAir.list_channels(), 0, 8)
    {:ok, %{channels: channels}}
  end

  def handle_cast(:refresh, state = %{channels: channels}) do
    Enum.with_index(channels, fn channel, index ->
      name = GenServer.call(XAir, {:channel_name, channel})
      solo = GenServer.call(XAir, {:solo, channel})
      mute = GenServer.call(XAir, {:mute, channel})
      fader = GenServer.call(XAir, {:mix_fader, channel})
      IO.inspect({channel, fader})
      GenServer.cast(Xtouch, {:set_lcd, index, name, ""})
      GenServer.cast(Xtouch, {:set_button, index, :solo, solo})
      GenServer.cast(Xtouch, {:set_button, index, :mute, mute})
      GenServer.cast(Xtouch, {:set_fader, index, fader})
    end)

    {:noreply, state}
  end

  def handle_cast({:increment_channel, ch, by}, state = %{channels: channels}) do
    channels =
      List.update_at(channels, ch, fn channel ->
        channel_list = XAir.list_channels()
        current_index = Enum.find_index(channel_list, &(&1 == channel))
        Enum.at(channel_list, rem(current_index + by, Enum.count(channel_list)))
      end)

    GenServer.cast(self, :refresh)

    {:noreply, %{state | channels: channels}}
  end

  def handle_cast({:increment_gain, source, channel, value}, state = %{channels: channels}) do
    xair_channel = xair_channel(source, channel, channels)
    xtouch_indices = xtouch_indices(xair_channel, channels)

    current_gain = GenServer.call(XAir, {:gain, xair_channel})
    new_gain = current_gain + value
    #GenServer.cast(XAir, {:solo, xair_channel, new_solo})

    {:noreply, state}
  end

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

  def handle_cast({:toggle_solo_channel, source, channel}, state = %{channels: channels}) do
    xair_channel = xair_channel(source, channel, channels)

    current_solo = GenServer.call(XAir, {:solo, xair_channel})
    new_solo = !current_solo
    GenServer.cast(XAir, {:solo, xair_channel, new_solo})

    {:noreply, state}
  end

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

  def handle_cast({:toggle_mute_channel, source, channel}, state = %{channels: channels}) do
    xair_channel = xair_channel(source, channel, channels)

    current_mute = GenServer.call(XAir, {:mute, xair_channel})
    new_mute = !current_mute
    GenServer.cast(XAir, {:mute, xair_channel, new_mute})

    {:noreply, state}
  end

  def handle_cast({:fader_moved, source, channel, value}, state = %{channels: channels}) do
    xair_channel = xair_channel(source, channel, channels)
    xtouch_indices = xtouch_indices(xair_channel, channels)

    Enum.each(xtouch_indices, &GenServer.cast(Xtouch, {:set_fader, &1, value}))
    if source != :xair, do: GenServer.cast(XAir, {:mix_fader, xair_channel, value})

    {:noreply, state}
  end
end
