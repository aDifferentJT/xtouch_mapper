defmodule Xtouch do
  use MidiServer, control_port: 5004, data_port: 5005

  def set_led_ring(ch, centre, mode, value) do
    centre = if centre, do: 1, else: 0

    mode =
      case mode do
        :single_dot -> 0
        :boost_cut -> 1
        :wrap -> 2
        :spread -> 3
      end

    <<val>> = <<0::1, centre::1, mode::2, value::4>>
    <<ch>> = <<3::4, ch::4>>
    {:control_change, 0, ch, val}
  end

  def set_lcd(ch, text1, text2) do
    text1 = String.slice(String.pad_trailing(text1, 7), 0, 7)
    text2 = String.slice(String.pad_trailing(text2, 7), 0, 7)

    [
      {:sysex, <<0x00, 0x00, 0x66, 0x15, 0x12, ch * 7, text1::binary>>},
      {:sysex, <<0x00, 0x00, 0x66, 0x15, 0x12, (ch + 8) * 7, text2::binary>>}
    ]
  end

  def set_button_led(channel, type, value) do
    type =
      case type do
        :rec -> 0
        :solo -> 1
        :mute -> 2
        :select -> 3
      end

    <<note::7>> = <<type::4, channel::3>>

    velocity =
      case value do
        false -> 0
        true -> 127
        :off -> 0
        :flash -> 1
        :on -> 127
      end

    {:note_on, 0, note, velocity}
  end

  def set_fader(channel, value) do
    <<max::14>> = <<-1::14>>
    value = round(value * max)
    {:pitch_bend, channel, value}
  end

  def decode_midi_command({:pitch_bend, channel, value}) do
    {:fader, channel, value}
  end

  def decode_midi_command({:control_change, _channel, controller, value}) do
    <<_::3, channel::4>> = <<controller::7>>

    value =
      case <<value::7>> do
        <<0::1, value::6>> -> value
        <<1::1, value::6>> -> -value
      end

    {:dial_turn, channel, value}
  end

  def decode_midi_command({:note_on, _channel, note, velocity}) do
    <<type::4, channel::3>> = <<note::7>>

    type =
      case type do
        0 -> :rec
        1 -> :solo
        2 -> :mute
        3 -> :select
        4 -> :dial_push
        13 -> :fader_touch
        _ -> {:unknown, type}
      end

    value =
      case velocity do
        0 -> :up
        127 -> :down
      end

    {:button, channel, type, value}
  end

  def decode_midi_command(command) do
    {:unknown, command}
  end

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @impl MidiServer
  def init2(_) do
    {:ok, %{depressed_buttons: MapSet.new()}}
  end

  @impl MidiServer
  def on_connect(state) do
    send(Mapper, :refresh)
    state
  end

  def handle_event2(
        {:dial_turn, channel, value},
        state = %{depressed_buttons: depressed_buttons}
      ) do
    if MapSet.member?(depressed_buttons, {channel, :dial_push}) do
      GenServer.cast(Mapper, {:increment_channel, channel, value})
      {:ok, state}
    else
      GenServer.cast(Mapper, {:increment_gain, :xtouch, channel, value})
      {:ok, state}
    end
  end

  def handle_event2(
        {:button, channel, :solo, :down},
        state
      ) do
    GenServer.cast(Mapper, {:toggle_solo_channel, :xtouch, channel})
    {:ok, state}
  end

  def handle_event2(
        {:button, channel, :mute, :down},
        state
      ) do
    GenServer.cast(Mapper, {:toggle_mute_channel, :xtouch, channel})
    {:ok, state}
  end

  def handle_event2({:fader, channel, value}, state) do
    <<max::14>> = <<-1::14>>
    value = value / max
    GenServer.cast(Mapper, {:fader_moved, :xtouch, channel, value})
    {:ok, state}
  end

  def handle_event2(command, state = %{depressed_buttons: depressed_buttons}) do
    IO.inspect(command)
    IO.inspect(depressed_buttons)
    {:ok, state}
  end

  def handle_event1(
        event = {:button, channel, type, :down},
        state = %{depressed_buttons: depressed_buttons}
      ) do
    depressed_buttons = MapSet.put(depressed_buttons, {channel, type})
    handle_event2(event, %{state | depressed_buttons: depressed_buttons})
  end

  def handle_event1(
        event = {:button, channel, type, :up},
        state = %{depressed_buttons: depressed_buttons}
      ) do
    depressed_buttons = MapSet.delete(depressed_buttons, {channel, type})
    handle_event2(event, %{state | depressed_buttons: depressed_buttons})
  end

  def handle_event1(event, state), do: handle_event2(event, state)

  @impl MidiServer
  def handle_midi_command(_delta_time, command, state) do
    handle_event1(decode_midi_command(command), state)
  end

  @impl GenServer
  def handle_cast({:set_led_ring, ch, centre, mode, value}, state) do
    GenServer.cast(
      self(),
      {:send_midi_commands, [{0, set_led_ring(ch, centre, mode, value)}]}
    )

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:set_lcd, ch, text1, text2}, state) do
    GenServer.cast(self(), {:send_midi_commands, Enum.map(set_lcd(ch, text1, text2), &{0, &1})})
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:set_button, ch, type, value}, state) do
    GenServer.cast(self(), {:send_midi_commands, [{0, set_button_led(ch, type, value)}]})
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:set_fader, ch, value}, state) do
    GenServer.cast(self(), {:send_midi_commands, [{0, set_fader(ch, value)}]})
    {:noreply, state}
  end
end
