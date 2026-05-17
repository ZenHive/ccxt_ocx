defmodule CcxtOcx.TelemetryTest do
  use ExUnit.Case, async: true

  alias CcxtOcx.Telemetry

  describe "prefix and event contracts" do
    test "prefix/0 returns the stable top-level namespace" do
      assert Telemetry.prefix() == [:ccxt_ocx]
    end

    test "internal accessors return the documented event names" do
      assert Telemetry.__runtime_memory__() == [:ccxt_ocx, :runtime, :memory]
      assert Telemetry.__rest_start__() == [:ccxt_ocx, :rest, :start]
      assert Telemetry.__ws_tick__() == [:ccxt_ocx, :ws, :tick]
    end
  end

  describe "thin wrappers" do
    test "execute/3 and span/3 delegate under the ccxt_ocx prefix" do
      handler = make_ref()
      test_pid = self()

      # We emit several events under [:ccxt_ocx, :test, ...] — attach_many is the right tool
      events = [
        [:ccxt_ocx, :test, :event],
        [:ccxt_ocx, :test, :span, :start],
        [:ccxt_ocx, :test, :span, :stop]
      ]

      :telemetry.attach_many(
        handler,
        events,
        fn event, meas, meta, _ -> send(test_pid, {:saw, event, meas, meta}) end,
        %{}
      )

      on_exit(fn -> :telemetry.detach(handler) end)

      # execute path
      Telemetry.execute([:test, :event], %{count: 1}, %{foo: "bar"})
      assert_receive {:saw, [:ccxt_ocx, :test, :event], %{count: 1}, %{foo: "bar"}}

      # span path — return the 2-tuple form so the metadata we care about appears on the :stop event
      result =
        Telemetry.span([:test, :span], %{op: "demo"}, fn ->
          send(test_pid, :inside_span)
          {:telemetry_span, :ok, %{op: "demo"}}
        end)

      assert result == :ok
      assert_receive :inside_span
      assert_receive {:saw, [:ccxt_ocx, :test, :span, :start], _, %{op: "demo"}}
      assert_receive {:saw, [:ccxt_ocx, :test, :span, :stop], %{duration: _}, %{op: "demo"}}
    end

    test "span wrapper normalizes bare result and tagged metadata returns from user fun" do
      handler = make_ref()
      test_pid = self()

      events = [
        [:ccxt_ocx, :norm, :bare, :start],
        [:ccxt_ocx, :norm, :bare, :stop],
        [:ccxt_ocx, :norm, :two, :start],
        [:ccxt_ocx, :norm, :two, :stop],
        [:ccxt_ocx, :norm, :three, :start],
        [:ccxt_ocx, :norm, :three, :stop]
      ]

      :telemetry.attach_many(handler, events, fn e, m, meta, _ -> send(test_pid, {:norm, e, m, meta}) end, %{})
      on_exit(fn -> :telemetry.detach(handler) end)

      # bare result
      assert :bare == Telemetry.span([:norm, :bare], %{}, fn -> :bare end)

      # tagged stop metadata
      assert :two == Telemetry.span([:norm, :two], %{}, fn -> {:telemetry_span, :two, %{custom: 1}} end)

      # tagged extra measurements + stop metadata
      assert :three ==
               Telemetry.span([:norm, :three], %{}, fn ->
                 {:telemetry_span, :three, %{extra: true}, %{custom: 2}}
               end)

      # We don't assert the exact events here (to keep the test tiny), just that the wrapper didn't crash on any form.
      # The previous test already proves emission works.
    end

    test "span wrapper preserves bare tuple results whose second element is a map" do
      result =
        Telemetry.span([:norm, :tuple_result], %{}, fn ->
          {:ok, %{response: "payload"}}
        end)

      assert {:ok, %{response: "payload"}} = result
    end
  end
end
