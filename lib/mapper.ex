defmodule Mapper do
  use GenServer
  require Logger

  defp config_dir() do
    base =
      case :os.type() do
        {:unix, _} -> :filename.join(System.get_env("HOME"), ".config")
        {:win32, _} -> System.get_env("APPDATA")
      end

    :filename.join(base, "xtouch_mapper")
  end

  defp load_page(state = %{page: page}) do
    filename = :filename.join(config_dir(), Integer.to_string(page))

    channels =
      try do
        File.stream!(filename, [:utf8])
        |> Stream.map(&String.trim/1)
        |> Enum.to_list()
      rescue
        File.Error -> Enum.slice(XAir.list_channels(), 0, 8)
      end

    %{state | channels: channels}
  end

  defp save_page(state = %{channels: channels, page: page}) do
    filename = :filename.join(config_dir(), Integer.to_string(page))

    File.write!(filename, Enum.join(channels, "\n"), [:utf8])
  end

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
    Logger.info("Writing config files to #{config_dir()}")
    File.mkdir_p!(config_dir())

    {:ok, timer} = :timer.send_interval(5000, :refresh)

    state =
      %{channels: nil, page: 1, mode: :channels, timer: timer}
      |> load_page()

    {:ok, state}
  end

  @impl GenServer
  def handle_info(:refresh, state = %{channels: channels, page: page, mode: :channels}) do
    Enum.each(0..7, &GenServer.cast(Xtouch, {:set_button, &1, :rec, &1 == page}))

    _ =
      Enum.with_index(channels, fn channel, index ->
        GenServer.cast(XAir, {:refresh, {:gain, channel}})
        GenServer.cast(XAir, {:refresh, {:channel_name, channel}})
        GenServer.cast(XAir, {:refresh, {:solo, channel}})
        GenServer.cast(XAir, {:refresh, {:mute, channel}})
        GenServer.cast(XAir, {:refresh, {:mix_fader, channel}})
      end)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:refresh, state = %{channels: channels, mode: :recall}) do
    GenServer.cast(Xtouch, {:set_lcd, 0, "Recall:", "Scene :"})
    GenServer.cast(Xtouch, {:set_button, 0, :rec, :flash})

    GenServer.cast(XAir, {:refresh, :snapshot_index})
    Enum.each(1..7, &GenServer.cast(XAir, {:refresh, {:snapshot_name, &1}}))

    {:noreply, state}
  end

  @impl GenServer
  # Timed-out call
  def handle_info({_, _}, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(:toggle_recall_mode, state = %{mode: :channels}) do
    Enum.each(0..7, &GenServer.cast(Xtouch, {:set_lcd, &1, "", ""}))
    send(self(), :refresh)
    {:noreply, %{state | mode: :recall}}
  end

  @impl GenServer
  def handle_cast(:toggle_recall_mode, state = %{mode: :recall}) do
    Enum.each(0..7, &GenServer.cast(Xtouch, {:set_lcd, &1, "", ""}))
    send(self(), :refresh)
    {:noreply, %{state | mode: :channels}}
  end

  @impl GenServer
  def handle_cast({:recall, index}, state = %{mode: :channels}) do
    state = %{state | page: index} |> load_page()
    send(self(), :refresh)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:recall, index}, state = %{mode: :recall}) do
    GenServer.cast(XAir, {:recall_snapshot, index})
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:increment_channel, ch, by}, state = %{channels: channels, mode: :channels}) do
    channels =
      List.update_at(channels, ch, fn channel ->
        channel_list = XAir.list_channels()
        current_index = Enum.find_index(channel_list, &(&1 == channel))
        Enum.at(channel_list, rem(current_index + by, Enum.count(channel_list)))
      end)

    state = %{state | channels: channels}

    save_page(state)

    GenServer.cast(Xtouch, {:set_lcd, ch, Enum.at(channels, ch), ""})

    send(self(), :refresh)

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(
        {:channel_name, source, channel, value},
        state = %{channels: channels, mode: :channels}
      ) do
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

    if source != :xair, do: GenServer.cast(XAir, {:set, {:channel_name, xair_channel}, value})

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:gain, source, headamp_channel, value}, state = %{channels: channels}) do
    xtouch_indices =
      channels
      |> Enum.with_index(fn ch, index ->
        try do
          if GenServer.call(XAir, {:get, {:input_src, ch}}, 100) == headamp_channel, do: index
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

    case GenServer.call(XAir, {:get, {:gain, xair_channel}}) do
      nil ->
        nil

      current_gain ->
        new_gain = current_gain + value
        GenServer.cast(XAir, {:set, {:gain, xair_channel}, new_gain})
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

    if source != :xair, do: GenServer.cast(XAir, {:set, {:solo, xair_channel}, value})

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:toggle_solo_channel, source, channel}, state = %{channels: channels}) do
    xair_channel = xair_channel(source, channel, channels)

    current_solo = GenServer.call(XAir, {:get, {:solo, xair_channel}})
    new_solo = !current_solo
    GenServer.cast(XAir, {:set, {:solo, xair_channel}, new_solo})

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

    if source != :xair, do: GenServer.cast(XAir, {:set, {:mute, xair_channel}, value})

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:toggle_mute_channel, source, channel}, state = %{channels: channels}) do
    xair_channel = xair_channel(source, channel, channels)

    current_mute = GenServer.call(XAir, {:get, {:mute, xair_channel}})
    new_mute = !current_mute
    GenServer.cast(XAir, {:set, {:mute, xair_channel}, new_mute})

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:fader_moved, source, channel, value}, state = %{channels: channels}) do
    xair_channel = xair_channel(source, channel, channels)
    xtouch_indices = xtouch_indices(xair_channel, channels)

    Enum.each(xtouch_indices, &GenServer.cast(Xtouch, {:set_fader, &1, value}))
    if source != :xair, do: GenServer.cast(XAir, {:set, {:mix_fader, xair_channel}, value})

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:snapshot_index, source, index}, state = %{mode: :recall}) do
    Enum.each(1..7, &GenServer.cast(Xtouch, {:set_button, &1, :rec, &1 == index}))

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:snapshot_name, source, index, value}, state = %{mode: :recall}) do
    GenServer.cast(Xtouch, {:set_lcd, index, value, ""})

    {:noreply, state}
  end

  def handle_cast(message, state) do
    Logger.info("Ignoring message: #{inspect(message)}")
    {:noreply, state}
  end
end
