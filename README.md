# ccxt_ocx

A macro-first Elixir wrapper around [CCXT](https://github.com/ccxt/ccxt)
that runs the JavaScript bundle inside [QuickBEAM](https://github.com/elixir-volt/quickbeam)
— no Node.js. Per-exchange/per-method wrappers (REST + WS, public + private)
are generated at compile time from CCXT's own type definitions.

> **Status: Phase 1 complete.** The project ships `CcxtOcx.Runtime`,
> `CcxtOcx.RuntimePool`, `CcxtOcx.Error`, `CcxtOcx.Tiers`,
> `CcxtOcx.BundleSurface` (+ `mix ccxt.verify_bundle`), and
> `CcxtOcx.Telemetry` — the foundation every later phase sits on. See
> [ROADMAP.md](ROADMAP.md) for what's next.

## Smoke test

```elixir
{:ok, server} = CcxtOcx.Runtime.start_link(name: :ccxt)

CcxtOcx.Runtime.info(:ccxt)
# => %{ccxt_version: "4.5.52", exchange_count: 122, bundle_path: "..."}

CcxtOcx.Runtime.eval(:ccxt, "self.ccxt.default.exchanges.length")
# => {:ok, 122}
```

The runtime applies browser stubs, loads
`node_modules/ccxt/dist/ccxt.browser.min.js` once, and exposes `eval/3`,
`call/4`, `with_runtime/2`, and `info/1`. Caller processes that crash
mid-call do not affect the runtime — see the "Isolation" tests in
`test/ccxt_ocx/runtime_test.exs`.

## Observability

Telemetry events are emitted under the `[:ccxt_ocx]` prefix:

- `[:ccxt_ocx, :runtime, :memory]` — QuickJS memory stats from any runtime
  or pool worker (see `CcxtOcx.Runtime.memory/1` and `CcxtOcx.RuntimePool.memory/1`).
- `[:ccxt_ocx, :rest, :start | :stop | :exception]` — reserved for Phase 2
  `defunified` (Task 7); metric definitions exist now so dashboards stay
  stable when emission lights up.
- `[:ccxt_ocx, :ws, :tick]` — reserved for Phase 3 `defstreaming` (Task 11).

Full event contract and handler examples live in `CcxtOcx.Telemetry`.

### PromEx (Prometheus / Grafana)

`ccxt_ocx` ships a first-class [PromEx](https://hex.pm/packages/prom_ex)
plugin that maps every event above to Prometheus metrics with zero glue.
PromEx is an **optional dependency** — consumers add it to their own app:

```elixir
# mix.exs (consumer app)
{:prom_ex, "~> 1.11"}
```

Then reference the plugin in PromEx config:

```elixir
defmodule MyApp.PromEx do
  use PromEx, otp_app: :my_app

  @impl true
  def plugins do
    [
      PromEx.Plugins.Application,
      PromEx.Plugins.Beam,
      # Optional :pool / :poll_rate opts enable periodic pool memory snapshots.
      {CcxtOcx.PromEx.Plugin, pool: MyApp.CcxtPool, poll_rate: 10_000}
    ]
  end
end
```

Provided metrics:

- `ccxt_ocx_runtime_memory_malloc_size_bytes` / `_used_size_bytes` / `_obj_count`
  (last_value, tags: `[:server, :pool, :phase]`)
- `ccxt_ocx_rest_duration_milliseconds` (distribution, buckets:
  10/50/100/250/500/1000/5000 ms)
- `ccxt_ocx_rest_total` (counter)
- `ccxt_ocx_rest_exceptions_total` (counter)
- `ccxt_ocx_ws_ticks_total` (counter)

See `CcxtOcx.PromEx.Plugin` for tag-stability details and polling config.

## Live Exploration with Tidewave

While building the macro layer, the fastest way to understand real behavior is to drive the system live:

```bash
iex -S mix tidewave
```

See [docs/tidewave_examples.md](docs/tidewave_examples.md) for copy-pasteable `project_eval` patterns, the critical "define global + call" technique, Deribit options exploration, memory/telemetry watching, and more.

These examples are maintained from actual Tidewave sessions and will evolve into the usage patterns for the generated macros.

## Installation

```elixir
def deps do
  [
    {:ccxt_ocx, "~> 0.1.0"}
  ]
end
```

You also need the ccxt JavaScript bundle on disk:

```bash
npm install
# installs ccxt to node_modules/ccxt/
```

## Development

```bash
mix deps.get
mix compile --warnings-as-errors
mix test.json
mix dialyzer.json --quiet
mix credo --strict --format json
mix sobelow
```

A Tidewave MCP server is wired in at port 4014:

```bash
iex -S mix tidewave
```

## License

TBD.
