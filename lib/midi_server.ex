defmodule MidiServer do
  @callback init2(init_arg :: term) ::
              {:ok, state}
              | {:ok, state, timeout | :hibernate | {:continue, term}}
              | :ignore
              | {:stop, reason :: any}
            when state: any

  @callback on_connect(state :: term) ::
              {:ok, new_state}
            when new_state: term

  @callback handle_midi_command(delta_time :: integer, command :: Midi.command(), state :: term) ::
              {:ok, new_state}
            when new_state: term

  defmacro __using__(control_port: control_port, data_port: data_port) do
    quote location: :keep, bind_quoted: [control_port: control_port, data_port: data_port] do
      @behaviour MidiServer

      use GenServer
      require Logger

      defp timestamp() do
        {s, us} = DateTime.to_gregorian_seconds(DateTime.utc_now())
        s * 10_000 + div(us, 100)
      end

      @impl GenServer
      def init(init_arg) do
        {:ok, control_socket} = :gen_udp.open(unquote(control_port), [:binary, active: true])
        {:ok, data_socket} = :gen_udp.open(unquote(data_port), [:binary, active: true])
        ssrc = Enum.random(0..0xFFFFFFFF)

        case init2(init_arg) do
          {:ok, state} ->
            {:ok,
             %{
               control_socket: control_socket,
               data_socket: data_socket,
               ssrc: ssrc,
               offset: 0,
               address: nil,
               state: state
             }}

          {:ok, state, timeout} ->
            {:ok,
             %{
               control_socket: control_socket,
               data_socket: data_socket,
               ssrc: ssrc,
               offset: 0,
               address: nil,
               state: state
             }, timeout}

          :ignore ->
            :ignore

          {:stop, reason} ->
            {:stop, reason}
        end
      end

      @impl GenServer
      def handle_info({:udp, socket, address, unquote(control_port), data}, %{ssrc: ssrc} = state) do
        {command, token, _sender_ssrc, name} = AppleMidi.decode_exchange_packet(data)

        Logger.info("Received #{command} request from #{name} on control")

        case command do
          "IN" ->
            :ok =
              :gen_udp.send(
                socket,
                address,
                unquote(control_port),
                AppleMidi.encode_exchange_packet("OK", token, ssrc, name)
              )
        end

        {:noreply, %{state | address: address}}
      end

      # Handle timestamp sync messages
      @impl GenServer
      def handle_info(
            {:udp, socket, address, unquote(data_port), <<0xFF, 0xFF, "CK", _::binary>> = data},
            %{ssrc: ssrc} = state
          ) do
        state =
          case AppleMidi.decode_timestamp_sync(data, ssrc, timestamp()) do
            {:reply, data} ->
              :ok = :gen_udp.send(socket, address, unquote(data_port), data)
              state

            {:offset, offset} ->
              Logger.info("Timestamp offset is #{offset}")
              %{state | offset: offset}
          end

        {:noreply, %{state | address: address}}
      end

      # Handle session start messages
      @impl GenServer
      def handle_info(
            {:udp, socket, address, unquote(data_port), <<0xFF, 0xFF, _::binary>> = data},
            state = %{data_socket: data_socket, ssrc: ssrc, state: nested_state}
          ) do
        {command, token, _other_ssrc, name} = AppleMidi.decode_exchange_packet(data)

        Logger.info("Received #{command} request from #{name} on data")

        case command do
          "IN" ->
            :ok =
              :gen_udp.send(
                socket,
                address,
                unquote(data_port),
                AppleMidi.encode_exchange_packet("OK", token, ssrc, name)
              )
        end

        nested_state =
          if command == "IN" and socket == data_socket do
            on_connect(nested_state)
          else
            nested_state
          end

        {:noreply, %{state | address: address, state: nested_state}}
      end

      # Handle MIDI messages
      @impl GenServer
      def handle_info(
            {:udp, socket, address, unquote(data_port), data},
            state = %{ssrc: ssrc, state: nested_state}
          ) do
        {header, commands} = Midi.decode_rtp(data)

        nested_state =
          Enum.reduce(commands, nested_state, fn {delta_time, command}, state ->
            {:ok, state} = handle_midi_command(delta_time, command, state)
            state
          end)

        {:noreply, %{state | address: address, state: nested_state}}
      end

      @impl GenServer
      def handle_cast(
            {:send_midi_commands, commands},
            state = %{data_socket: data_socket, ssrc: ssrc, address: address}
          ) do
        case :gen_udp.send(
               data_socket,
               address,
               unquote(data_port),
               Midi.encode_rtp(0, timestamp(), ssrc, commands)
             ) do
          :ok -> nil
          {:error, e} -> Logger.info("Could not send midi commands #{e}")
        end

        {:noreply, state}
      end
    end
  end
end
