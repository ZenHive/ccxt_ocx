defmodule CcxtOcx.DevTelemetry do
  @moduledoc """
  Maintainer-side dogfooding helpers for ccxt_ocx telemetry.

  Attach to every `[:ccxt_ocx, ...]` event family in one call, pretty-print
  each emission to a configurable IO device, keep running counts plus the
  last-seen measurements/metadata in an `Agent`, dump the summary on demand.

  For Tidewave / IEx sessions only — this module owns a named process and
  prints to stdout by default, so it has no business in `start/0` /
  `Application.start/2`. There is no supervisor entry; `watch/1` starts the
  Agent lazily.

  ## Usage

      iex> CcxtOcx.DevTelemetry.watch()
      :ok
      iex> CcxtOcx.Runtime.memory(:rt)
      [memory] malloc=12.3M used=8.1M objs=14523 server=#PID<0.345.0> phase=manual
      iex> CcxtOcx.DevTelemetry.summary()
      %{
        runtime_memory: %{count: 1, last_measurements: %{...}, last_metadata: %{...}},
        rest_start: %{count: 0, last_measurements: nil, last_metadata: nil},
        rest_stop: %{count: 0, last_measurements: nil, last_metadata: nil},
        rest_exception: %{count: 0, last_measurements: nil, last_metadata: nil},
        ws_tick: %{count: 0, last_measurements: nil, last_metadata: nil}
      }

  See `docs/tidewave_examples.md` § "Dev Telemetry Loop" for the
  observe-while-driving cycle this module is designed for.

  ## Options for `watch/1`

    * `:print` — print each emission to `:io_device`. Default: `true`.
    * `:filter` — restrict to a subset of event keys (see `t:event_key/0`).
      Default: all events.
    * `:io_device` — where to write pretty-print output. Default: `:stdio`.

  Idempotent — re-calling `watch/1` detaches the previous handler and
  resets state before re-attaching with the new options.
  """

  @handler_id "ccxt-ocx-dev-telemetry"

  @events %{
    runtime_memory: [:ccxt_ocx, :runtime, :memory],
    rest_start: [:ccxt_ocx, :rest, :start],
    rest_stop: [:ccxt_ocx, :rest, :stop],
    rest_exception: [:ccxt_ocx, :rest, :exception],
    ws_tick: [:ccxt_ocx, :ws, :tick]
  }

  @type event_key ::
          :runtime_memory | :rest_start | :rest_stop | :rest_exception | :ws_tick

  @type entry :: %{
          count: non_neg_integer(),
          last_measurements: map() | nil,
          last_metadata: map() | nil
        }

  @type state :: %{event_key() => entry()}

  @type opts :: [
          print: boolean(),
          filter: [event_key()],
          io_device: IO.device()
        ]

  @doc """
  Attach a single handler to every `[:ccxt_ocx, ...]` event family.

  Idempotent — re-calling detaches the previous handler and resets the
  in-memory state before re-attaching.
  """
  @spec watch(opts()) :: :ok
  def watch(opts \\ []) do
    print? = Keyword.get(opts, :print, true)
    io_device = Keyword.get(opts, :io_device, :stdio)
    filter = Keyword.get(opts, :filter, Map.keys(@events))

    :ok = detach()
    :ok = ensure_agent()
    :ok = Agent.update(__MODULE__, fn _ -> initial_state() end)

    events = Enum.map(filter, &Map.fetch!(@events, &1))

    :ok =
      :telemetry.attach_many(
        @handler_id,
        events,
        &__MODULE__.handle_event/4,
        %{print?: print?, io_device: io_device}
      )

    :ok
  end

  @doc """
  Detach the dev-telemetry handler. Idempotent.

  Leaves the Agent (and its accumulated counts) alone — call `reset/0` to
  clear, or `summary/0` to inspect post-detach.
  """
  @spec detach() :: :ok
  def detach do
    _ = :telemetry.detach(@handler_id)
    :ok
  end

  @doc """
  Current in-memory state.

  Returns the initial all-zeros state if `watch/1` was never called.
  """
  @spec summary() :: state()
  def summary do
    case Process.whereis(__MODULE__) do
      nil -> initial_state()
      _pid -> Agent.get(__MODULE__, & &1)
    end
  end

  @doc """
  Reset all counts and last-values to the initial state.

  No-op if `watch/1` was never called.
  """
  @spec reset() :: :ok
  def reset do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      _pid -> Agent.update(__MODULE__, fn _ -> initial_state() end)
    end
  end

  @doc false
  @spec handle_event([atom()], map(), map(), map()) :: :ok
  def handle_event(event, measurements, metadata, config) do
    key = event_to_key(event)

    if Process.whereis(__MODULE__) do
      Agent.update(__MODULE__, fn state ->
        entry = Map.fetch!(state, key)

        new_entry = %{
          entry
          | count: entry.count + 1,
            last_measurements: measurements,
            last_metadata: metadata
        }

        Map.put(state, key, new_entry)
      end)
    end

    if Map.get(config, :print?, false) do
      io_device = Map.get(config, :io_device, :stdio)
      IO.puts(io_device, format(key, measurements, metadata))
    end

    :ok
  end

  # ------------------------------------------------------------------
  # private
  # ------------------------------------------------------------------

  @spec ensure_agent() :: :ok
  defp ensure_agent do
    case Agent.start(fn -> initial_state() end, name: __MODULE__) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  @spec initial_state() :: state()
  defp initial_state do
    @events
    |> Map.keys()
    |> Map.new(fn key -> {key, %{count: 0, last_measurements: nil, last_metadata: nil}} end)
  end

  @spec event_to_key([atom()]) :: event_key()
  defp event_to_key([:ccxt_ocx, :runtime, :memory]), do: :runtime_memory
  defp event_to_key([:ccxt_ocx, :rest, :start]), do: :rest_start
  defp event_to_key([:ccxt_ocx, :rest, :stop]), do: :rest_stop
  defp event_to_key([:ccxt_ocx, :rest, :exception]), do: :rest_exception
  defp event_to_key([:ccxt_ocx, :ws, :tick]), do: :ws_tick

  @spec format(event_key(), map(), map()) :: String.t()
  defp format(:runtime_memory, meas, meta) do
    malloc = format_bytes(Map.get(meas, :malloc_size))
    used = format_bytes(Map.get(meas, :memory_used_size))
    objs = Map.get(meas, :obj_count, "?")
    phase = Map.get(meta, :phase, :manual)

    target =
      cond do
        Map.has_key?(meta, :server) -> "server=#{inspect(meta.server)}"
        Map.has_key?(meta, :pool) -> "pool=#{inspect(meta.pool)}"
        true -> "target=?"
      end

    "[memory] malloc=#{malloc} used=#{used} objs=#{objs} #{target} phase=#{phase}"
  end

  defp format(:rest_start, _meas, meta) do
    "[rest:start] exchange=#{Map.get(meta, :exchange, "?")} method=#{Map.get(meta, :method, "?")}"
  end

  defp format(:rest_stop, meas, meta) do
    duration = format_duration(Map.get(meas, :duration))

    "[rest:stop] exchange=#{Map.get(meta, :exchange, "?")} method=#{Map.get(meta, :method, "?")} duration=#{duration}"
  end

  defp format(:rest_exception, _meas, meta) do
    "[rest:exception] exchange=#{Map.get(meta, :exchange, "?")} method=#{Map.get(meta, :method, "?")} kind=#{Map.get(meta, :kind, "?")}"
  end

  defp format(:ws_tick, _meas, meta) do
    "[ws:tick] exchange=#{Map.get(meta, :exchange, "?")} stream=#{Map.get(meta, :stream, "?")} type=#{Map.get(meta, :type, "?")}"
  end

  @spec format_bytes(integer() | nil) :: String.t()
  defp format_bytes(nil), do: "?"

  defp format_bytes(n) when is_integer(n) and n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"

  defp format_bytes(n) when is_integer(n) and n >= 1_000, do: "#{Float.round(n / 1_000, 1)}K"

  defp format_bytes(n) when is_integer(n), do: "#{n}B"

  @spec format_duration(integer() | nil) :: String.t()
  defp format_duration(nil), do: "?"

  defp format_duration(n) when is_integer(n) do
    us = System.convert_time_unit(n, :native, :microsecond)
    "#{Float.round(us / 1000, 2)}ms"
  end
end
