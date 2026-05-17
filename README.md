# ccxt_ocx

A macro-first Elixir wrapper around [CCXT](https://github.com/ccxt/ccxt)
that runs the JavaScript bundle inside [QuickBEAM](https://github.com/elixir-volt/quickbeam)
— no Node.js. Per-exchange/per-method wrappers (REST + WS, public + private)
are generated at compile time from CCXT's own type definitions.

> **Status: Phase 1.** Currently the project ships only `CcxtOcx.Runtime`,
> the foundation handle every later phase sits on. See
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
  or pool worker (see `CcxtOcx.Runtime.memory/1` and `RuntimePool.memory/1`).

Full event contract and handler examples live in `CcxtOcx.Telemetry`.

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
