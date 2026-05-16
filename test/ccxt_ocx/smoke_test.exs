defmodule CcxtOcx.SmokeTest do
  @moduledoc """
  End-to-end smoke verification for the Phase 1 substrate.

  Replays the manual Tidewave verification as an automated suite: CCXT bundle loads
  into QuickBEAM, OXC parses real CCXT TypeScript source, Binance public REST returns
  ticker/orderbook/OHLCV/trades, and CCXT-pro streams 3 ticker pushes over WebSocket.

  The default `self.ccxt.binance` in the browser bundle loads the USDT-margined
  linear-perpetual market set; symbols are `BASE/QUOTE:SETTLE` (e.g. `BTC/USDT:USDT`).
  Spot would require a different exchange-class build — out of scope for Phase 1.

  Offline tests (bundle load + OXC parse) carry `:integration`; network-hitting
  tests carry `:network`. Both tags are excluded by default — opt in per surface.

  Run modes:

      mix test                                                  # smoke skipped
      mix test --include integration                            # offline subset
      mix test --include network                                # network only
      mix test --include integration --include network          # full smoke
  """

  use ExUnit.Case, async: false

  @bundle_path "node_modules/ccxt/dist/ccxt.browser.min.js"
  @ts_path "node_modules/ccxt/js/src/base/Exchange.d.ts"
  @symbol "BTC/USDT:USDT"
  @rest_timeout 15_000
  @ws_timeout 30_000
  @load_markets_timeout 30_000
  @required_methods ~w[fetchTicker fetchOrderBook fetchOHLCV fetchTrades watchTicker]

  setup_all do
    if !File.exists?(@bundle_path) do
      flunk("""
      CCXT bundle missing at #{@bundle_path}.

      Install dependencies before running smoke tests:

        npm install ccxt

      Or, if you use a different package manager, install ccxt into ./node_modules so
      #{@bundle_path} exists. CcxtOcx.Runtime loads this bundle into QuickBEAM at boot.
      """)
    end

    {:ok, server} = CcxtOcx.Runtime.start_link(name: :smoke_runtime)
    on_exit(fn -> CcxtOcx.Runtime.stop(server) end)
    {:ok, server: server}
  end

  describe "bundle loads (offline)" do
    @describetag :integration

    test "Runtime.info/1 reports CCXT version and >100 exchanges", %{server: server} do
      info = CcxtOcx.Runtime.info(server)
      assert info.ccxt_version =~ ~r/^4\.\d+\./
      assert info.exchange_count > 100
      assert File.exists?(info.bundle_path)
    end
  end

  describe "OXC parses CCXT source (offline)" do
    @describetag :integration

    test "Exchange.d.ts declares the smoke method surface" do
      source = File.read!(@ts_path)
      assert {:ok, ast} = OXC.parse(source, "Exchange.d.ts")
      assert ast.type == :program

      method_names =
        ast
        |> OXC.collect(fn
          %{type: :method_definition, key: %{name: name}} -> {:keep, name}
          _ -> :skip
        end)
        |> MapSet.new()

      missing = Enum.reject(@required_methods, &MapSet.member?(method_names, &1))

      assert missing == [],
             "OXC parsed Exchange.d.ts but did not find: #{inspect(missing)}. " <>
               "Either the bundle layout changed or the AST match pattern needs updating."
    end
  end

  describe "Binance public REST (network)" do
    @describetag :network

    setup %{server: server} do
      js = """
      globalThis.__smoke_ex ||= new self.ccxt.binance({enableRateLimit: true, timeout: 30000});
      await globalThis.__smoke_ex.loadMarkets();
      true
      """

      assert_ok_or_flunk(
        CcxtOcx.Runtime.eval(server, js, timeout: @load_markets_timeout),
        "binance().loadMarkets()",
        fn _ -> :ok end
      )

      :ok
    end

    test "fetchTicker returns price fields", %{server: server} do
      js = ~s|await globalThis.__smoke_ex.fetchTicker("#{@symbol}")|

      assert_ok_or_flunk(
        CcxtOcx.Runtime.eval(server, js, timeout: @rest_timeout),
        "fetchTicker #{@symbol}",
        fn ticker ->
          assert ticker["symbol"] == @symbol
          assert is_number(ticker["last"]) or is_number(ticker["bid"])
        end
      )
    end

    test "fetchOrderBook returns bids and asks", %{server: server} do
      js = ~s|await globalThis.__smoke_ex.fetchOrderBook("#{@symbol}", 5)|

      assert_ok_or_flunk(
        CcxtOcx.Runtime.eval(server, js, timeout: @rest_timeout),
        "fetchOrderBook #{@symbol}",
        fn ob ->
          assert is_list(ob["bids"]) and ob["bids"] != []
          assert is_list(ob["asks"]) and ob["asks"] != []
        end
      )
    end

    test "fetchOHLCV returns the requested candle count", %{server: server} do
      js = ~s|await globalThis.__smoke_ex.fetchOHLCV("#{@symbol}", "1m", undefined, 2)|

      assert_ok_or_flunk(
        CcxtOcx.Runtime.eval(server, js, timeout: @rest_timeout),
        "fetchOHLCV #{@symbol} 1m limit 2",
        fn candles ->
          assert length(candles) == 2

          for [ts, o, h, l, c, _v] <- candles do
            assert is_integer(ts)
            assert is_number(o) and is_number(h) and is_number(l) and is_number(c)
          end
        end
      )
    end

    test "fetchTrades returns a non-empty list", %{server: server} do
      js = ~s|await globalThis.__smoke_ex.fetchTrades("#{@symbol}", undefined, 2)|

      assert_ok_or_flunk(
        CcxtOcx.Runtime.eval(server, js, timeout: @rest_timeout),
        "fetchTrades #{@symbol}",
        fn trades ->
          assert trades != []
          for t <- trades, do: assert(t["symbol"] == @symbol)
        end
      )
    end
  end

  describe "Binance public WebSocket (network)" do
    @describetag :network

    test "watchTicker streams 3 pushes", %{server: server} do
      case CcxtOcx.Runtime.eval(server, "typeof self?.ccxt?.pro?.binance", timeout: 5_000) do
        {:ok, "function"} ->
          :ok

        other ->
          flunk("""
          CCXT-pro Binance surface unreachable.

          Expected `self.ccxt.pro.binance` to be a constructor; got: #{inspect(other)}.

          Likely cause: the CCXT browser bundle no longer exposes the pro namespace at
          this path, or the bundle is an older build. Confirm with:

            node -e "console.log(typeof require('ccxt').pro?.binance)"

          and update the smoke test to match the current pro surface.
          """)
      end

      # NOTE: top-level await form, not IIFE-wrapped — QuickBEAM.eval returns the
      # final expression value, and an `(async () => {...})()` Promise comes back
      # as `%{}` instead of resolving. The final JSON.stringify also sidesteps
      # max_convert_depth truncation on the nested ticker maps.
      js = """
      const ex = new self.ccxt.pro.binance({enableRateLimit: true, timeout: 30000});
      const tickers = [];
      try {
        for (let i = 0; i < 3; i++) {
          tickers.push(await ex.watchTicker("#{@symbol}"));
        }
      } finally {
        await ex.close();
      }
      JSON.stringify(tickers.map(t => ({symbol: t.symbol, last: t.last, timestamp: t.timestamp})))
      """

      assert_ok_or_flunk(
        CcxtOcx.Runtime.eval(server, js, timeout: @ws_timeout),
        "watchTicker #{@symbol} (3 pushes)",
        fn payload ->
          pushes = Jason.decode!(payload)
          assert length(pushes) == 3

          for t <- pushes do
            assert t["symbol"] == @symbol
            assert is_number(t["last"])
          end
        end
      )
    end
  end

  @spec assert_ok_or_flunk({:ok, term()} | {:error, term()}, String.t(), (term() -> term())) ::
          term()
  defp assert_ok_or_flunk({:ok, value}, _label, on_ok), do: on_ok.(value)

  defp assert_ok_or_flunk({:error, err}, label, _on_ok) do
    msg = error_message(err)

    if network_failure?(msg) do
      flunk("""
      Network failure during "#{label}".

      Smoke tests require public-internet reachability to Binance:
        REST: https://api.binance.com
        WS:   wss://stream.binance.com:9443

      No API keys are required (public endpoints only).

      Re-run online:
        mix test test/ccxt_ocx/smoke_test.exs --include integration

      Offline (skip network, keep bundle + OXC checks):
        mix test test/ccxt_ocx/smoke_test.exs --include integration --exclude network

      Underlying error: #{msg}
      """)
    else
      flunk(~s|Unexpected error during "#{label}": #{msg}|)
    end
  end

  @spec error_message(term()) :: String.t()
  defp error_message(%QuickBEAM.JSError{message: m}), do: m
  defp error_message(other), do: inspect(other)

  @spec network_failure?(term()) :: boolean()
  defp network_failure?(msg) when is_binary(msg) do
    msg =~ ~r/ECONNREFUSED|ETIMEDOUT|ENOTFOUND|getaddrinfo|fetch failed|NetworkError|EAI_AGAIN/i
  end

  defp network_failure?(_), do: false
end
