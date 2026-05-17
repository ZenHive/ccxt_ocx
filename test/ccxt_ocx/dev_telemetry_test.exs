defmodule CcxtOcx.DevTelemetryTest do
  # async: false — DevTelemetry registers a named Agent and a global telemetry
  # handler, both of which would race other tests in this module if parallel.
  use ExUnit.Case, async: false

  alias CcxtOcx.DevTelemetry
  alias CcxtOcx.Telemetry

  setup do
    on_exit(fn ->
      DevTelemetry.detach()
      stop_agent_if_running()
    end)

    :ok
  end

  describe "watch/1" do
    test "attaches a handler and starts fresh state" do
      assert :ok = DevTelemetry.watch(print: false)

      summary = DevTelemetry.summary()
      assert summary.runtime_memory == %{count: 0, last_measurements: nil, last_metadata: nil}
      assert summary.rest_start.count == 0
      assert summary.rest_stop.count == 0
      assert summary.rest_exception.count == 0
      assert summary.ws_tick.count == 0
    end

    test "is idempotent — re-calling resets state and re-attaches without leaking handlers" do
      :ok = DevTelemetry.watch(print: false)

      Telemetry.execute([:runtime, :memory], %{malloc_size: 100}, %{server: self()})
      assert DevTelemetry.summary().runtime_memory.count == 1

      :ok = DevTelemetry.watch(print: false)

      # Re-attach clears counts.
      assert DevTelemetry.summary().runtime_memory.count == 0

      # And there's only one handler — emit once, count once (not twice).
      Telemetry.execute([:runtime, :memory], %{malloc_size: 100}, %{server: self()})
      assert DevTelemetry.summary().runtime_memory.count == 1
    end

    test ":filter restricts attached events" do
      :ok = DevTelemetry.watch(print: false, filter: [:runtime_memory])

      Telemetry.execute([:runtime, :memory], %{malloc_size: 100}, %{server: self()})
      Telemetry.execute([:ws, :tick], %{count: 1}, %{exchange: "binance", stream: "trade", type: "update"})

      summary = DevTelemetry.summary()
      assert summary.runtime_memory.count == 1
      # filtered events stay at zero
      assert summary.ws_tick.count == 0
    end

    test "invalid options do not detach an existing handler or reset state" do
      :ok = DevTelemetry.watch(print: false, filter: [:runtime_memory])
      Telemetry.execute([:runtime, :memory], %{malloc_size: 100}, %{server: self()})

      assert_raise NimbleOptions.ValidationError, fn ->
        DevTelemetry.watch(print: false, filter: [:unknown])
      end

      Telemetry.execute([:runtime, :memory], %{malloc_size: 200}, %{server: self()})

      assert DevTelemetry.summary().runtime_memory.count == 2
    end

    test ":io_device routes pretty-print output (captures the format string)" do
      {:ok, capture} = StringIO.open("")
      :ok = DevTelemetry.watch(print: true, io_device: capture)

      Telemetry.execute(
        [:runtime, :memory],
        %{malloc_size: 12_300_000, memory_used_size: 8_100_000, obj_count: 14_523},
        %{
          server: self()
        }
      )

      {_input, output} = StringIO.contents(capture)
      assert output =~ "[memory]"
      assert output =~ "malloc=12.3M"
      assert output =~ "used=8.1M"
      assert output =~ "objs=14523"
      assert output =~ "phase=manual"
    end

    test "print: false silences output but still updates counters" do
      {:ok, capture} = StringIO.open("")
      :ok = DevTelemetry.watch(print: false, io_device: capture)

      Telemetry.execute([:runtime, :memory], %{malloc_size: 1}, %{server: self()})

      {_input, output} = StringIO.contents(capture)
      assert output == ""
      assert DevTelemetry.summary().runtime_memory.count == 1
    end

    test "prints every event family format" do
      {:ok, capture} = StringIO.open("")
      :ok = DevTelemetry.watch(print: true, io_device: capture)

      Telemetry.execute([:runtime, :memory], %{malloc_size: 999, memory_used_size: 1_250, obj_count: 1}, %{pool: :pool})
      Telemetry.execute([:runtime, :memory], %{}, %{})
      Telemetry.execute([:rest, :start], %{}, %{exchange: "binance", method: "ticker"})
      Telemetry.execute([:rest, :stop], %{duration: 1_000_000}, %{exchange: "binance", method: "ticker"})
      Telemetry.execute([:rest, :stop], %{}, %{})
      Telemetry.execute([:rest, :exception], %{}, %{exchange: "binance", method: "ticker", kind: :error})
      Telemetry.execute([:ws, :tick], %{}, %{exchange: "binance", stream: "trade", type: "update"})

      {_input, output} = StringIO.contents(capture)
      assert output =~ "malloc=999B"
      assert output =~ "used=1.3K"
      assert output =~ "pool=:pool"
      assert output =~ "target=?"
      assert output =~ "[rest:start] exchange=binance method=ticker"
      assert output =~ "[rest:stop] exchange=binance method=ticker duration=1.0ms"
      assert output =~ "[rest:stop] exchange=? method=? duration=?"
      assert output =~ "[rest:exception] exchange=binance method=ticker kind=error"
      assert output =~ "[ws:tick] exchange=binance stream=trade type=update"
    end
  end

  describe ".iex.exs" do
    test "does not crash outside a Mix shell" do
      elixir = System.find_executable("elixir")
      assert is_binary(elixir)

      {output, status} =
        System.cmd(elixir, ["-e", "Code.eval_file(\".iex.exs\")"], stderr_to_stdout: true)

      assert status == 0, output
    end
  end

  describe "emission landing" do
    setup do
      :ok = DevTelemetry.watch(print: false)
      :ok
    end

    test "[:ccxt_ocx, :runtime, :memory] increments runtime_memory and stores last measurements/meta" do
      meas = %{malloc_size: 100, memory_used_size: 80, obj_count: 5}
      meta = %{server: self(), phase: :init}

      Telemetry.execute([:runtime, :memory], meas, meta)

      entry = DevTelemetry.summary().runtime_memory
      assert entry.count == 1
      assert entry.last_measurements == meas
      assert entry.last_metadata == meta
    end

    test "[:ccxt_ocx, :rest, :start|:stop|:exception] each route to their own bucket" do
      Telemetry.execute([:rest, :start], %{system_time: 1}, %{exchange: "binance", method: "ticker"})
      Telemetry.execute([:rest, :stop], %{duration: 1_000_000}, %{exchange: "binance", method: "ticker"})

      Telemetry.execute([:rest, :exception], %{duration: 1_000_000}, %{
        exchange: "binance",
        method: "ticker",
        kind: :error
      })

      summary = DevTelemetry.summary()
      assert summary.rest_start.count == 1
      assert summary.rest_stop.count == 1
      assert summary.rest_exception.count == 1
    end

    test "[:ccxt_ocx, :ws, :tick] increments ws_tick" do
      Telemetry.execute([:ws, :tick], %{count: 1}, %{exchange: "binance", stream: "trade", type: "update"})
      Telemetry.execute([:ws, :tick], %{count: 1}, %{exchange: "binance", stream: "trade", type: "update"})

      assert DevTelemetry.summary().ws_tick.count == 2
    end

    test "multiple emissions accumulate the count and overwrite last_*" do
      Telemetry.execute([:runtime, :memory], %{malloc_size: 1}, %{server: self()})
      Telemetry.execute([:runtime, :memory], %{malloc_size: 2}, %{server: self()})
      Telemetry.execute([:runtime, :memory], %{malloc_size: 3}, %{server: self()})

      entry = DevTelemetry.summary().runtime_memory
      assert entry.count == 3
      # last-wins
      assert entry.last_measurements == %{malloc_size: 3}
    end
  end

  describe "reset/0" do
    test "clears counts and last-values when Agent is running" do
      :ok = DevTelemetry.watch(print: false)
      Telemetry.execute([:runtime, :memory], %{malloc_size: 1}, %{server: self()})
      assert DevTelemetry.summary().runtime_memory.count == 1

      :ok = DevTelemetry.reset()
      assert DevTelemetry.summary().runtime_memory == %{count: 0, last_measurements: nil, last_metadata: nil}
    end

    test "is a no-op when watch/1 was never called" do
      assert :ok = DevTelemetry.reset()
    end
  end

  describe "summary/0" do
    test "returns the initial all-zeros state when watch/1 was never called" do
      summary = DevTelemetry.summary()
      assert summary.runtime_memory == %{count: 0, last_measurements: nil, last_metadata: nil}
      assert summary.rest_start == %{count: 0, last_measurements: nil, last_metadata: nil}
      assert summary.rest_stop == %{count: 0, last_measurements: nil, last_metadata: nil}
      assert summary.rest_exception == %{count: 0, last_measurements: nil, last_metadata: nil}
      assert summary.ws_tick == %{count: 0, last_measurements: nil, last_metadata: nil}
    end
  end

  describe "detach/0" do
    test "stops counting further emissions but preserves prior state" do
      :ok = DevTelemetry.watch(print: false)
      Telemetry.execute([:runtime, :memory], %{malloc_size: 1}, %{server: self()})
      assert DevTelemetry.summary().runtime_memory.count == 1

      :ok = DevTelemetry.detach()

      Telemetry.execute([:runtime, :memory], %{malloc_size: 2}, %{server: self()})

      # Count is unchanged after detach — handler is gone.
      assert DevTelemetry.summary().runtime_memory.count == 1
    end

    test "is idempotent" do
      assert :ok = DevTelemetry.detach()
      assert :ok = DevTelemetry.detach()
    end
  end

  # ------------------------------------------------------------------

  defp stop_agent_if_running do
    case Process.whereis(DevTelemetry) do
      nil -> :ok
      pid -> Agent.stop(pid)
    end
  end
end
