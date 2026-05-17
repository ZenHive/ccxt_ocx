defmodule CcxtOcx.PromEx.PluginTest do
  use ExUnit.Case, async: true

  alias CcxtOcx.PromEx.Plugin
  alias PromEx.MetricTypes.Event
  alias PromEx.MetricTypes.Polling
  alias Telemetry.Metrics.Counter
  alias Telemetry.Metrics.Distribution
  alias Telemetry.Metrics.LastValue

  describe "event_metrics/1" do
    test "returns three Event groups covering runtime, rest, ws families" do
      groups = Plugin.event_metrics([])

      assert length(groups) == 3
      assert Enum.all?(groups, &match?(%Event{}, &1))

      names = Enum.map(groups, & &1.group_name)
      assert :ccxt_ocx_runtime_event_metrics in names
      assert :ccxt_ocx_rest_event_metrics in names
      assert :ccxt_ocx_ws_event_metrics in names
    end

    test "runtime memory group exposes three last_value metrics on [:ccxt_ocx, :runtime, :memory]" do
      group = group_by_name(:ccxt_ocx_runtime_event_metrics)

      assert length(group.metrics) == 3
      assert Enum.all?(group.metrics, &match?(%LastValue{}, &1))
      assert Enum.all?(group.metrics, &(&1.event_name == [:ccxt_ocx, :runtime, :memory]))

      measurements = group.metrics |> Enum.map(& &1.measurement) |> Enum.sort()
      assert measurements == [:malloc_size, :memory_used_size, :obj_count]

      assert Enum.all?(group.metrics, &(&1.tags == [:server, :pool, :phase]))
    end

    test "rest group exposes a duration distribution + total counter + exception counter" do
      group = group_by_name(:ccxt_ocx_rest_event_metrics)

      assert length(group.metrics) == 3

      [distribution] = Enum.filter(group.metrics, &match?(%Distribution{}, &1))
      assert distribution.event_name == [:ccxt_ocx, :rest, :stop]
      # `unit: {:native, :millisecond}` wraps the measurement atom in a converter fn
      # via `Telemetry.Metrics.maybe_convert_measurement/2` — assert the shape, not the atom.
      assert is_function(distribution.measurement, 1)
      assert distribution.tags == [:exchange, :method]
      assert distribution.reporter_options[:buckets] == [10, 50, 100, 250, 500, 1000, 5000]

      counters = Enum.filter(group.metrics, &match?(%Counter{}, &1))
      assert length(counters) == 2

      stop_counter = Enum.find(counters, &(&1.event_name == [:ccxt_ocx, :rest, :stop]))
      exception_counter = Enum.find(counters, &(&1.event_name == [:ccxt_ocx, :rest, :exception]))

      assert stop_counter.tags == [:exchange, :method]
      assert exception_counter.tags == [:exchange, :method, :kind]
    end

    test "ws group exposes a tick counter on [:ccxt_ocx, :ws, :tick]" do
      group = group_by_name(:ccxt_ocx_ws_event_metrics)

      [tick] = group.metrics
      assert match?(%Counter{}, tick)
      assert tick.event_name == [:ccxt_ocx, :ws, :tick]
      assert tick.tags == [:exchange, :stream, :type]
    end
  end

  describe "polling_metrics/1" do
    test "returns [] when no :pool opt is provided" do
      assert Plugin.polling_metrics([]) == []
    end

    test "returns a single Polling group with the configured MFA when :pool is set" do
      [group] = Plugin.polling_metrics(pool: :test_pool)

      assert %Polling{} = group
      assert group.group_name == :ccxt_ocx_runtime_pool_memory_polling_metrics
      assert group.poll_rate == 5_000
      assert group.measurements_mfa == {CcxtOcx.RuntimePool, :memory, [:test_pool]}
      assert group.metrics == []
    end

    test "honors a custom :poll_rate" do
      [group] = Plugin.polling_metrics(pool: :test_pool, poll_rate: 15_000)
      assert group.poll_rate == 15_000
    end
  end

  describe "tag normalization (live emission smoke)" do
    setup do
      handler = make_ref()
      test_pid = self()

      :telemetry.attach_many(
        handler,
        [[:ccxt_ocx, :runtime, :memory]],
        fn event, meas, meta, _ -> send(test_pid, {:saw, event, meas, meta}) end,
        %{}
      )

      on_exit(fn -> :telemetry.detach(handler) end)
      :ok
    end

    test "memory metric tag_values fills missing :pool and :phase with \"none\"" do
      # Simulate a CcxtOcx.Runtime.memory/1 emission shape (server-only metadata).
      meta = %{server: self()}
      CcxtOcx.Telemetry.execute([:runtime, :memory], %{malloc_size: 1, memory_used_size: 1, obj_count: 1}, meta)

      assert_receive {:saw, [:ccxt_ocx, :runtime, :memory], _meas, ^meta}

      [malloc_metric | _] = group_by_name(:ccxt_ocx_runtime_event_metrics).metrics
      normalized = malloc_metric.tag_values.(meta)

      assert is_binary(normalized.server)
      assert String.starts_with?(normalized.server, "#PID<")
      assert normalized.pool == "none"
      assert normalized.phase == "none"
    end

    test "memory metric tag_values stringifies atom :phase and atom :pool" do
      meta = %{server: self(), pool: :my_pool, phase: :init}
      [malloc_metric | _] = group_by_name(:ccxt_ocx_runtime_event_metrics).metrics
      normalized = malloc_metric.tag_values.(meta)

      assert normalized.pool == "my_pool"
      assert normalized.phase == "init"
    end

    test "rest metric tag_values defaults missing :exchange / :method to \"none\"" do
      [distribution] =
        Enum.filter(
          group_by_name(:ccxt_ocx_rest_event_metrics).metrics,
          &match?(%Distribution{}, &1)
        )

      normalized = distribution.tag_values.(%{})
      assert normalized == %{exchange: "none", method: "none"}
    end

    test "rest exception metric tag_values stringifies :kind and passes binaries through unchanged" do
      exception_counter =
        Enum.find(
          group_by_name(:ccxt_ocx_rest_event_metrics).metrics,
          &(match?(%Counter{}, &1) and &1.event_name == [:ccxt_ocx, :rest, :exception])
        )

      normalized =
        exception_counter.tag_values.(%{exchange: "binance", method: :fetch_ticker, kind: :error})

      # Binary :exchange stays unchanged (exercises the is_binary branch of stringify/1).
      assert normalized == %{exchange: "binance", method: "fetch_ticker", kind: "error"}
    end

    test "ws tick metric tag_values normalizes all three keys" do
      [tick] = group_by_name(:ccxt_ocx_ws_event_metrics).metrics

      assert tick.tag_values.(%{exchange: :binance, stream: "trades", type: :update}) ==
               %{exchange: "binance", stream: "trades", type: "update"}

      assert tick.tag_values.(%{}) == %{exchange: "none", stream: "none", type: "none"}
    end
  end

  ## Helpers

  defp group_by_name(name) do
    Enum.find(Plugin.event_metrics([]), &(&1.group_name == name))
  end
end
