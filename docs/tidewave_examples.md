# Tidewave Examples for ccxt_ocx

Copy-pasteable, battle-tested examples for live exploration of a running `ccxt_ocx` application.

These examples come from real Tidewave-driven sessions (including heavy use of Deribit options chains and telemetry).

## Recommended Workflow

1. Start the app with Tidewave:
   ```bash
   iex -S mix tidewave
   ```
2. Connect your AI client to the MCP endpoint (`http://localhost:4014/tidewave/mcp`).
3. Use a **named runtime** so state survives across multiple `project_eval` calls.
4. **Define helpers once with `eval`**, then invoke them with `call/4` (this pattern is critical — see below).

## The Most Important Pattern: Define + Call

Directly evaluating code that contains `await` often returns an empty map.  
**Always** define async helpers as globals, then call them.

```elixir
# 1. Define once (can be large and complex)
CcxtOcx.Runtime.eval(:rt, """
  globalThis.getTicker = async (exchangeId, symbol) => {
    const ex = new ccxt[exchangeId]();
    const t = await ex.fetchTicker(symbol);
    return {
      symbol: t.symbol,
      last: t.last,
      bid: t.bid,
      ask: t.ask,
      timestamp: t.timestamp
    };
  };
  "getTicker defined"
""")

# 2. Call as many times as you want (auto-awaits + converts result)
CcxtOcx.Runtime.call(:rt, "getTicker", ["bybit", "ETH/USDT"])
CcxtOcx.Runtime.call(:rt, "getTicker", ["deribit", "ETH-PERPETUAL"])
```

This pattern was discovered through extensive live use and is the recommended way to work with CCXT inside QuickBEAM.

## Starting and Managing Runtimes

```elixir
# Start a named runtime (recommended)
{:ok, _pid} = CcxtOcx.Runtime.start_link(name: :rt)

# Inspect it
CcxtOcx.Runtime.info(:rt)
# => %{ccxt_version: "4.5.51", exchange_count: 111, ...}

# Get the raw QuickBEAM pid (for low-level QuickBEAM.* calls)
rt = CcxtOcx.Runtime.rt(:rt)

# Stop when done (frees the JS context)
CcxtOcx.Runtime.stop(:rt)
```

## Fetching Market Data

```elixir
# After defining getTicker as shown above
CcxtOcx.Runtime.call(:rt, "getTicker", ["binance", "BTC/USDT"])
CcxtOcx.Runtime.call(:rt, "getTicker", ["okx", "ETH/USDT"])
```

## Exploring Complex Surfaces (Deribit Options)

Deribit option symbols look like `ETH/USD:ETH-260519-2200-C`.  
Strike, expiry, and side live in the symbol string on bulk responses.

```elixir
CcxtOcx.Runtime.eval(:rt, """
  globalThis.getEthFrontOptions = async (window = 100) => {
    const d = new ccxt.deribit();
    const chain = await d.fetchOptionChain('ETH');
    const vals = Object.values(chain || {});

    // Parse YYMMDD dates from symbols
    const dates = [...new Set(vals.map(v => {
      const m = (v.symbol || '').match(/-(\\d{6})-/);
      return m ? m[1] : null;
    }).filter(Boolean))].sort();

    const now = new Date();
    const today = (now.getUTCFullYear()%100) + 
                  String(now.getUTCMonth()+1).padStart(2,'0') +
                  String(now.getUTCDate()).padStart(2,'0');

    const front = dates.find(e => e >= today) || dates[0];

    let spot = 2180;
    try {
      const p = await d.fetchTicker('ETH-PERPETUAL');
      spot = p.last || spot;
    } catch (_) {}

    const near = vals.filter(v => {
      const m = (v.symbol || '').match(/-(\\d{6})-(\\d+)-([CP])$/);
      if (!m || m[1] !== front) return false;
      const strike = parseFloat(m[2]);
      return Math.abs(strike - spot) <= window;
    });

    const byStrike = {};
    for (const v of near) {
      const m = v.symbol.match(/-(\\d+)-([CP])$/);
      const k = parseFloat(m[1]);
      if (!byStrike[k]) byStrike[k] = { strike: k, call: null, put: null };
      const side = m[2] === 'C' ? 'call' : 'put';
      byStrike[k][side] = {
        symbol: v.symbol,
        last: v.lastPrice,
        bid: v.bidPrice,
        ask: v.askPrice,
        mark: v.markPrice,
        iv: v.impliedVolatility
      };
    }

    return {
      spot: Math.round(spot * 10) / 10,
      frontExpiry: front,
      strikes: Object.keys(byStrike).map(Number).sort((a,b)=>a-b)
    };
  };
  "getEthFrontOptions defined"
""")

CcxtOcx.Runtime.call(:rt, "getEthFrontOptions", [120])
```

This kind of exploration is extremely valuable before writing `defunified` support for non-trivial return shapes.

## Memory and Telemetry

```elixir
# One-shot
CcxtOcx.Runtime.memory(:rt)          # emits [:ccxt_ocx, :runtime, :memory]
CcxtOcx.Runtime.memory_usage(:rt)    # same map, no telemetry side-effect

# Watch live while driving load from Tidewave
:telemetry.attach("watch", [:ccxt_ocx, :runtime, :memory], fn event, meas, meta, _ ->
  IO.puts("Memory: #{meas.memory_used_size} bytes")
end, %{})
```

## Dev Telemetry Loop (Dogfooding)

`CcxtOcx.DevTelemetry` is the maintainer-side companion to `CcxtOcx.Telemetry`: one
call attaches a handler to every `[:ccxt_ocx, ...]` event family, pretty-prints each
emission to stdout, and keeps running counts + last-values in an `Agent` you can
`summary/0` at any time. Use it as the validation loop for new emission sites
(Task 7 `defunified`, Task 11 `defstreaming`, Task 15 memory monitor) before
downstream consumers (`CcxtOcx.PromEx.Plugin`, Grafana dashboards) bake in
assumptions about the contract.

```elixir
# Attach once per session — idempotent (re-attach detaches the prior handler
# and resets counts).
CcxtOcx.DevTelemetry.watch()

# Drive load. Every emission lands as a one-line print + an Agent bump.
{:ok, _} = CcxtOcx.Runtime.start_link(name: :rt)
CcxtOcx.Runtime.memory(:rt)
# => [memory] malloc=12.3M used=8.1M objs=14523 server=#PID<0.345.0> phase=manual

# Snapshot when you want to assert the shape.
CcxtOcx.DevTelemetry.summary()
# => %{
#      runtime_memory: %{count: 2, last_measurements: %{...}, last_metadata: %{...}},
#      rest_start: %{count: 0, last_measurements: nil, last_metadata: nil},
#      rest_stop: %{count: 0, last_measurements: nil, last_metadata: nil},
#      rest_exception: %{count: 0, last_measurements: nil, last_metadata: nil},
#      ws_tick: %{count: 0, last_measurements: nil, last_metadata: nil}
#    }

# Clear counters without re-attaching.
CcxtOcx.DevTelemetry.reset()

# Detach when you're done.
CcxtOcx.DevTelemetry.detach()
```

`watch/1` takes a few options for ad-hoc filtering:

```elixir
# Silence pretty-print, keep counters only (handy when driving high-frequency
# WS load and the prints would scroll past too fast to read).
CcxtOcx.DevTelemetry.watch(print: false)

# Restrict to a subset of event families.
CcxtOcx.DevTelemetry.watch(filter: [:runtime_memory, :ws_tick])

# Send pretty-print to a different IO device (e.g. a log file).
{:ok, log} = File.open("/tmp/ccxt_ocx.log", [:write])
CcxtOcx.DevTelemetry.watch(io_device: log)
```

In dev, `iex -S mix` (and therefore `iex -S mix tidewave`) auto-attaches
`DevTelemetry` via the project's `.iex.exs`, so you can drop straight into
`summary/0` without a manual `watch/0` call.

## Using Other Tidewave Tools Together

While you have a runtime running, combine it with Tidewave's other MCP tools:

```elixir
# From your AI client (not in project_eval)
# get_docs("CcxtOcx.Runtime")
# get_source_location("CcxtOcx.Runtime.call")
# search_package_docs("quickbeam", packages: ["quickbeam"])
```

This combination (live runtime + static docs + source location) is extremely powerful during development.

## Error Handling & Resilience

`CcxtOcx.Runtime.call/4` always returns `{:ok, result}` or `{:error, reason}` — it does not raise. Pattern-match the tuple to handle failures:

```elixir
case CcxtOcx.Runtime.call(:rt, "getTicker", ["deribit", "NONEXISTENT"]) do
  {:ok, ticker} ->
    ticker

  {:error, %QuickBEAM.JSError{name: name, message: msg}} ->
    # e.g. name "BadSymbol", msg "deribit does not have market symbol NONEXISTENT"
    {:error, name, msg}
end
```

Runtimes are isolated — a crashing helper or JS error does not kill the GenServer.

## What This Will Look Like After the Macros

Once Phase 2 lands, the above exploration will become:

```elixir
use CcxtOcx, exchanges: [:bybit, :deribit]

Bybit.fetch_ticker("ETH/USDT")
Deribit.fetch_option_chain("ETH")          # or a dedicated option surface
```

The Tidewave examples above are intentionally written so they can later become the implementation + conformance tests for `defunified`.

## Tips

- Always use **named runtimes** when working interactively.
- **Define once, call many times** is the golden pattern for async CCXT work.
- Project large results down in JavaScript before returning them.
- Complex surfaces (options, structured products, funding rates) are the best way to discover what the macros actually need to handle.
- Keep this document updated with every interesting new surface you explore via Tidewave.

---

**Contributing**: When you discover something new while using Tidewave on this project, add a minimal, copy-pasteable example here. Future AI sessions (and humans) will thank you.