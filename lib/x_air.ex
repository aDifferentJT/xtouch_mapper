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

  defp get_address({:channel_name, ch}, state, callback) do
    callback.(ch <> "/config/name", state)
  end

  defp get_address({:gain, ch}, state, callback) do
    get_input_src(ch, state, fn
      nil, state ->
        callback.(nil, state)

      in_src, state ->
        address = "/headamp/" <> String.pad_leading(Integer.to_string(in_src), 2, "0") <> "/gain"

        callback.(address, state)
    end)
  end

  defp get_address({:solo, ch}, state, callback) do
    {_, ch} =
      Enum.find(list_channels_full(), fn
        {^ch, _} -> true
        _ -> false
      end)

    callback.("/-stat/solosw/" <> String.pad_leading(Integer.to_string(ch), 2, "0"), state)
  end

  defp get_address({:mute, ch}, state, callback) do
    callback.(ch <> "/mix/on", state)
  end

  defp get_address({:mix_fader, ch}, state, callback) do
    callback.(ch <> "/mix/fader", state)
  end

  defp process_value_send(:solo, value), do: bool_to_int(value)
  defp process_value_send(:mute, value), do: bool_to_int(!value)
  defp process_value_send(_type, value), do: value

  defp process_value_recv(:solo, value), do: int_to_bool(value)
  defp process_value_recv(:mute, value), do: !int_to_bool(value)
  defp process_value_recv(_type, value), do: value

  defp standing_replies_ch(ch, "/config/name", [value]) do
    GenServer.cast(Mapper, {:channel_name, :xair, ch, value})
  end

  defp standing_replies_ch(ch, "/mix/on", [value]) do
    GenServer.cast(Mapper, {:mute, :xair, ch, !int_to_bool(value)})
  end

  defp standing_replies_ch(ch, "/mix/fader", [value]) do
    GenServer.cast(Mapper, {:fader_moved, :xair, ch, value})
  end

  defp standing_replies_ch(_, _, _), do: nil

  defp standing_replies(<<"/ch/", ch::binary-size(2), param::binary>>, args) do
    standing_replies_ch("/ch/" <> ch, param, args)
  end

  defp standing_replies(<<"/rtn/aux", param::binary>>, args) do
    standing_replies_ch("/rtn/aux", param, args)
  end

  defp standing_replies(<<"/bus/", bus::binary-size(1), param::binary>>, args) do
    standing_replies_ch("/bus/" <> bus, param, args)
  end

  defp standing_replies(<<"/lr", param::binary>>, args) do
    standing_replies_ch("/lr", param, args)
  end

  defp standing_replies(<<"/headamp/", ch::binary-size(2), "/gain">>, [value]) do
    {ch, _} = Integer.parse(ch)

    GenServer.cast(Mapper, {:gain, :xair, ch, value})
  end

  defp standing_replies(<<"/-stat/solosw/", ch::binary-size(2)>>, [value]) do
    {ch, _} = Integer.parse(ch)

    case Enum.find(list_channels_full(), fn {_, solo_ch} -> solo_ch == ch end) do
      {ch, _} ->
        GenServer.cast(Mapper, {:solo, :xair, ch, int_to_bool(value)})

      nil ->
        nil
    end
  end

  defp standing_replies(_, _), do: nil

  defp send(address, args, %{socket: socket, ip: ip}) do
    :gen_udp.send(
      socket,
      ip,
      @port,
      Osc.encode_message(address, args)
    )
  end

  defp get_input_src(
         ch = <<"/ch/", _::binary>>,
         state = %{waiting_replies: waiting_replies},
         callback
       ) do
    address = ch <> "/config/insrc"

    :ok = send(address, [], state)

    on_reply = fn [in_src], state ->
      callback.(in_src + 1, state)
    end

    waiting_replies = Map.update(waiting_replies, address, [on_reply], &[on_reply | &1])

    %{state | waiting_replies: waiting_replies}
  end

  defp get_input_src(_ch, state, callback), do: callback.(nil, state)

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @impl GenServer
  def init(ip) do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: true])

    {:ok, timer} = :timer.send_interval(5000, :remote)

    {:ok, %{socket: socket, ip: ip, timer: timer, waiting_replies: %{}}}
  end

  @impl GenServer
  def handle_call(
        {:channel_name, ch},
        from,
        state = %{waiting_replies: waiting_replies}
      ) do
    address = ch <> "/config/name"

    :ok = send(address, [], state)

    on_reply = fn [name], state ->
      GenServer.reply(from, name)
      state
    end

    waiting_replies = Map.update(waiting_replies, address, [on_reply], &[on_reply | &1])

    {:noreply, %{state | waiting_replies: waiting_replies}}
  end

  @impl GenServer
  def handle_call({:input_src, ch}, from, state) do
    state =
      get_input_src(ch, state, fn in_src, state ->
        GenServer.reply(from, in_src)
        state
      end)

    {:noreply, state}
  end

  @impl GenServer
  def handle_call(
        {type, ch},
        from,
        state = %{waiting_replies: waiting_replies}
      ) do
    state =
      get_address({type, ch}, state, fn
        nil, state ->
          GenServer.reply(from, nil)
          state

        address, state ->
          :ok = send(address, [], state)

          on_reply = fn [value], state ->
            GenServer.reply(from, process_value_recv(type, value))
            state
          end

          waiting_replies = Map.update(waiting_replies, address, [on_reply], &[on_reply | &1])

          %{state | waiting_replies: waiting_replies}
      end)

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({type, ch}, state) do
    state =
      get_address({type, ch}, state, fn
        nil, state ->
          state

        address, state ->
          :ok = send(address, [], state)
          state
      end)

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({type, ch, value}, state) do
    state =
      get_address({type, ch}, state, fn
        nil, state ->
          state

        address, state ->
          :ok = send(address, [process_value_send(type, value)], state)
          state
      end)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(
        {:udp, _, _, _, data},
        state = %{waiting_replies: waiting_replies}
      ) do
    {address, arguments} = Osc.decode_message(data)
    standing_replies(address, arguments)
    {replies, waiting_replies} = Map.pop(waiting_replies, address, [])
    state = %{state | waiting_replies: waiting_replies}
    state = Enum.reduce(replies, state, & &1.(arguments, &2))
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:remote, state) do
    :ok = send("/xremote", [], state)
    {:noreply, state}
  end
end
