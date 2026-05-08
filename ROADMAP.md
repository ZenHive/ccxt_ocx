# ccxt_ocx Roadmap

**Vision:** A macro-first Elixir wrapper around CCXT that runs the JS bundle inside QuickBEAM, with all per-exchange/per-method wrappers — REST and WS, data plane *and* trade plane — generated at compile time from CCXT's own type definitions, covering 100+ exchanges in idiomatic Elixir without hand-writing thousands of adapter functions.

**Scope:**

- **Full unified CCXT surface** — REST + WS, public + private, including `createOrder`, `cancelOrder`, `fetchBalance`, `setLeverage`, `watchMyTrades`, `watchBalance`. No carve-outs based on hypothetical risk.
- **Verification-first for the trade plane:** before signing against mainnet, run testnet harnesses (Binance, Deribit, OKX) and compare signed payloads byte-for-byte against known-good signers where one exists. Narrow scope *only* when concrete evidence of instability surfaces — not preemptively.
- **Recommended deployment shape:** the QuickBEAM pool runs in a dedicated OTP release / supervision tree so a NIF panic is isolated from anything else. This is a deployment recommendation, not a scope cut.

**Completed work:** See [CHANGELOG.md](CHANGELOG.md).

---

## 🎯 Current Focus

**Phase 1: Foundation — runtime lifecycle and supervision.**
The bundle loads, REST + WS verified live against Binance fapi/wss-fstream. Now we need a stable Elixir-side surface to manage runtimes before any wrapper macros can sit on top.

### 📋 Current Tasks

| Task | Status | Notes |
|------|--------|-------|
| Task 1: Runtime module + browser stubs | ⬜ | Foundation for everything else |
| Task 2: Pin quickbeam ~> 0.10.4 | ⬜ | Closure-GC fix is load-bearing for long-lived WS handlers |

---

## Phase 1: Foundation — Runtime Lifecycle ⬜

> Without this, every other phase is blocked. Goal: a supervised QuickBEAM runtime that loads ccxt once, exposes a stable handle, and survives transient JS errors.

- [ ] **Task 1: `CcxtOcx.Runtime` module** [D:4/B:9/U:9 → Eff:2.25] 🎯
      Wrap `QuickBEAM.start/1` in a GenServer that owns one runtime, applies the browser stubs (`globalThis.self = globalThis; globalThis.window = globalThis;`, `navigator`, `location`), loads the bundle, and exposes `eval/2`, `call/3`, and a `with_runtime/2` helper that doesn't die when the caller does. Verify against ccxt 4.5.51+ in the live tidewave session before declaring done.

- [ ] **Task 2: Pin `quickbeam ~> 0.10.4` and document why** [D:1/B:5/U:6 → Eff:5.5] 🎯
      QuickBEAM 0.10.3 fixed a closure GC bug specifically for handlers in long-lived runtimes — exactly the WS pattern. Tighten mix.exs and add a one-liner in CLAUDE.md so future sessions don't drift the floor.

- [ ] **Task 3: `CcxtOcx.RuntimePool` supervisor** [D:5/B:8/U:7 → Eff:1.5] 🚀
      `QuickBEAM.Pool.start_link/1` wired into the application supervision tree, sized per `(exchange, market_type)`. Init function loads the bundle once. Each pool checkout returns a runtime that already has ccxt evaluated. Pre-warmed; lazy spawn allowed for low-traffic exchanges.

- [ ] **Task 4: JS error → Elixir error normalization** [D:4/B:7/U:6 → Eff:1.6] 🚀
      Map `%QuickBEAM.JS.Error{name: "BadSymbol"}`, `"NetworkError"`, `"RateLimitExceeded"`, etc. to Elixir tagged tuples (`{:error, :bad_symbol, msg}`). One canonical error module so every downstream wrapper returns the same shape.

- [ ] **Task 5: Smoke test suite** [D:3/B:6/U:5 → Eff:1.8] 🚀
      ExUnit tag `:integration` (off by default), tagged `:network` for tests that hit Binance. Repeat the live verification done in tidewave: bundle loads, OXC parses, ticker/orderbook/OHLCV/trades arrive, WS streams 3 ticker pushes. Use `flunk/1` with actionable messages on missing-network — never skip silently.

- [ ] **Task 5b: Bundle-bump verification pipeline** [D:5/B:8/U:8 → Eff:1.6] 🚀
      CCXT releases multiple times per week. A `mix npm.update ccxt` must not silently regress codegen. Bake a `mix ccxt.verify_bundle` task that: re-parses `node_modules/ccxt/js/ccxt.d.ts` via OXC, diffs the unified-method list and the per-exchange `has` table against a checked-in manifest (`priv/ccxt_surface.exs`), and re-runs the testnet harnesses (T1–T3) before the bump can be merged. Manifest drift = explicit human review, not silent acceptance. Run on every PR that touches `node_modules/ccxt/` or `package.json`.

---

## Phase 2: Macro-Driven Method Generation ⬜

> The leverage point. Don't hand-write `fetch_ticker/2`, `fetch_order_book/3`, `fetch_ohlcv/4`. Generate them from CCXT's own surface.

- [ ] **Task 6: Parse `node_modules/ccxt/js/ccxt.d.ts` with OXC** [D:6/B:8/U:8 → Eff:1.33] 📋
      Build a compile-time module that reads CCXT's TypeScript definitions, walks the AST via `OXC.parse/2` + `OXC.collect/2`, and extracts: every unified method name, its parameter list, its return type. Output: an Elixir term (compile-time data structure) describing the full unified API. Validate by counting methods and comparing to ccxt's documented count.

- [ ] **Task 7: `defunified` macro** [D:7/B:10/U:9 → Eff:1.36] 📋
      Single declaration emits the QuickBEAM call, JSON encode of args, await + decode, struct hydration, and error normalization for one unified method *across all exchanges*. NimbleOptions schema validates the macro options at compile time (per `~/.claude/includes/development-philosophy.md` § "Cite Ecosystem Precedents"). Phoenix.Router and Ash.Resource are the precedents — single declarative line, full generated wrapper.

- [ ] **Task 8: Typed structs for unified return shapes** [D:5/B:8/U:7 → Eff:1.5] 🚀
      `CcxtOcx.Ticker`, `OrderBook`, `Candle`, `Trade`, `Market`, `Currency` — each generated by introspecting the `.d.ts` types. Use TypedStruct (or hand-roll if it fights with macro generation). String-typed money fields for everything that's a price/quantity (no float). Doctests covering shape; ExUnit covering edge cases (missing fields, empty arrays).

- [ ] **Task 9: `defexchange` macro** [D:6/B:7/U:6 → Eff:1.08] 📋
      Per-exchange module emitter. `defexchange :binance` walks `ex.urls`, `ex.has`, `ex.timeframes`, `ex.options.defaultType` once at compile time (booting a throwaway runtime during compile) and emits a struct + capability table. Generated module exposes `CcxtOcx.Binance.has?/1`, `urls/0`, `timeframes/0`. Compile-time bundle eval is the unusual move — vet first that the build environment can run QuickBEAM.

- [ ] **Task 10: Symbol normalization layer** [D:6/B:6/U:5 → Eff:0.92] ⚠️
      The `BTC/USDT` vs `BTC/USDT:USDT` quirk surfaced live. Some exchanges use `:` for perps, some use `-PERP`, some use venue-specific tickers. Document a mapping function `CcxtOcx.Symbol.normalize/3` and a counterpart `denormalize/3`. Don't over-engineer — start by accepting both forms and routing.

---

## Phase 3: Streaming (CCXT Pro) ⬜

> WS verified working in this session. Surface it as something usable from a Phoenix app or a GenStage pipeline.

- [ ] **Task 11: `defstreaming` macro** [D:7/B:9/U:8 → Eff:1.21] 📋
      Mirror `defunified` for the watch* family. Emits a subscribe function that takes a subscriber pid + symbol and forwards `{:ccxt, exchange_id, symbol, payload}` messages. Internally runs `await ex.watch*` in a loop inside the runtime; uses a Beam handler to push back to Elixir. Each watch is one runtime (CCXT pro multiplexes channels per WS connection).

- [ ] **Task 12: `CcxtOcx.Stream` GenStage producer** [D:6/B:7/U:6 → Eff:1.08] 📋
      For consumers that want backpressure: a GenStage producer that buffers ticks from a watch loop. Useful for downstream Broadway pipelines or persistence to TimescaleDB.

- [ ] **Task 13: Reconnect / heartbeat policy** [D:6/B:8/U:7 → Eff:1.25] 📋
      CCXT pro handles WS reconnect internally, but we need an Elixir-side watchdog: if no message in N seconds, restart the runtime. Don't trust the JS-side heartbeat alone — exchange WS endpoints occasionally accept connections but stop pushing.

---

## Phase 4: Trade-Plane Verification ⬜

> Trade-plane methods are macro-generated alongside data-plane methods in Phase 2. This phase **verifies** that signed/authenticated calls actually work end-to-end before anyone routes real money through them.

- [ ] **Task T1: Testnet harness — Binance USDT-M futures** [D:5/B:9/U:8 → Eff:1.7] 🚀
      `BINANCE_TESTNET_API_KEY` + `_SECRET` env vars (per `~/.claude/includes/critical-rules.md` § "INTEGRATION TESTS" — `flunk/1` with the exact export commands and the testnet signup URL when missing, never skip silently). Place a small test order, query balance, cancel the order, fetch fills. Tag `:integration`, `:network`, `:testnet`. Run on every PR via CI to catch ccxt bundle bumps that break signing.

- [ ] **Task T2: Testnet harness — Deribit options** [D:5/B:8/U:7 → Eff:1.5] 🚀
      Deribit testnet is the gold standard for options/perp signing edge cases. Same pattern as T1.

- [ ] **Task T3: Testnet harness — OKX** [D:5/B:7/U:6 → Eff:1.3] 📋
      Third venue with non-trivial signing (passphrase auth, distinct timestamp format). Catches ccxt regressions in the multi-auth code path.

- [ ] **Task T4: Signed-payload byte-comparison harness** [D:7/B:8/U:6 → Eff:1.0] 📋
      Where a native Elixir signer exists for a venue (e.g. for Binance HMAC, this is trivially expressible in pure Elixir), generate the same order via both the QuickBEAM-CCXT path and the native path, and assert byte equality of the signed payload + identical headers. Run on every CI build.

- [ ] **Task T5: WS authenticated streams (`watchBalance`, `watchMyTrades`, `watchOrders`)** [D:6/B:8/U:7 → Eff:1.25] 📋
      Verify ccxt.pro authenticated WS works under Mint-backed WebSocket — exactly the closure-in-handler pattern QuickBEAM 0.10.3 fixed. Long-running test (30+ min) on testnet to catch slow leaks.

- [ ] **Task T6: Document the actual stability surface** [D:2/B:6/U:7 → Eff:3.25] 🎯
      Once T1-T5 run green for a sustained period (~weeks), publish `docs/trade_plane_status.md` listing per-exchange signing verification status and any known limitations. If instability is found, *that* is when we narrow scope — with a repro and a justification, not preemptively.

---

## Phase 5: Production Hardening ⬜

- [ ] **Task 14: Telemetry events** [D:3/B:7/U:7 → Eff:2.33] 🎯
      `[:ccxt_ocx, :rest, :start | :stop | :exception]`, `[:ccxt_ocx, :ws, :tick]`, `[:ccxt_ocx, :runtime, :memory]`. Standard `:telemetry` shape so downstream metrics stacks (Prometheus, Datadog) plug in with no glue.

- [ ] **Task 15: Memory monitoring + restart policy** [D:5/B:8/U:7 → Eff:1.5] 🚀
      `QuickBEAM.memory_usage/1` polled per runtime; restart on threshold (default ~64MB resident). Long-running WS runtimes accumulate state via subscription buffers — a 24h restart cadence is cheap insurance.

- [ ] **Task 16: ApiToolkit integration** [D:4/B:6/U:6 → Eff:1.5] 🚀
      Wire `ApiToolkit.Cache` for OHLCV (highly cacheable), `ApiToolkit.RateLimiter` per exchange (CCXT has rate-limit info in `ex.rateLimit` we can read at compile time), `ApiToolkit.Metrics` per endpoint. Per the api-toolkit skill in CLAUDE.md.

- [ ] **Task 16b: Hoist rate-limit + nonce state into Elixir** [D:7/B:9/U:8 → Eff:1.21] 📋
      CCXT does throttling and nonce tracking *inside* each exchange instance. With a `RuntimePool` of N workers, each holds its own `binance()` instance — they don't share token buckets or nonce counters. Result: easy to trip exchange rate limits *or* get rejected signed orders ("nonce too low / reused"). Two-pronged fix: (1) for **public/unauth** calls, route through `ApiToolkit.RateLimiter` keyed by `(exchange, endpoint_class)` *outside* the QuickBEAM call so all pool workers share one bucket; (2) for **authenticated** calls, pin one runtime per `(exchange, account)` pair via a registry — same instance always handles the same account so its internal nonce monotonicity is preserved. Document the pinning contract; `createOrder` for account A *must* always hit the same runtime. Test under concurrent load (100 simultaneous orders) on testnet before claiming done.

- [ ] **Task 17: Sandboxed deployment shape** [D:5/B:8/U:5 → Eff:1.3] 📋
      Document (and provide a sample release config for) running the QuickBEAM pool in a dedicated OTP release / supervision tree, isolated from any trade-plane code. NIF crashes affect only the data-plane VM. Distillery / Mix release recipe in `docs/`.

---

## Phase 6: DX and Docs ⬜

- [ ] **Task 18: ex_doc + llms.txt** [D:2/B:5/U:5 → Eff:2.5] 🎯
      `mix docs` generates `doc/llms.txt` per the elixir-setup convention. AI agents pulling ccxt_ocx as a dependency get a structured summary.

- [ ] **Task 19: Descripex annotations on the public API** [D:3/B:5/U:4 → Eff:1.5] 🚀
      `api()` macro on `CcxtOcx.fetch_ticker/3`, `watch_ticker/2`, etc. so MCP-aware agents can introspect the surface. Per `~/.claude/includes/agent-economy` patterns.

- [ ] **Task 20: Tidewave examples** [D:2/B:4/U:5 → Eff:2.25] 🎯
      `docs/tidewave_examples.md` — copy-pasteable `project_eval` snippets for live exploration. The macros are most useful in IEx; show that.

---

## Phase 7: Native-Elixir Migration (Sketch) ⬜

> **Hypothetical, not yet committed.** Only worth pursuing for the 3–5 exchanges that actually matter to a given production system. The JS bundle is a permanent fallback for the long tail (~95 exchanges), not a stopgap. Don't migrate "for purity" — migrate when measured hot-path latency or supply-chain isolation justifies the per-exchange porting cost.
>
> Migration is exchange-by-exchange and method-family-by-method-family. The macro-generated public API is the *contract* and never changes; only the adapter behind the dispatch swaps from `:js` to `:native`.

- [ ] **Task N0: `defendpoint` macro + CCXT-JS source extractor** [D:7/B:9/U:8 → Eff:1.21] 📋
      *The leverage that makes the rest of Phase 7 tractable.* Two parts:
      (1) **Macro:** `defendpoint :fetch_ticker, "GET /api/v3/ticker/24hr", params: [symbol: :string], returns: Ticker.t(), parse: &parse_ticker/1` emits the Req call, signing dispatch (for private endpoints), response parser invocation, struct hydration into the Phase 2 typed structs, and error normalization. NimbleOptions schema validates the option keyword. The output of one declaration is a complete behaviour-callback implementation.
      (2) **Extractor:** at compile time, parse `node_modules/ccxt/js/src/<exchange>.js` via OXC to emit the per-exchange `defendpoint` table automatically. CCXT REST adapters are mostly URL templates + parameter maps + a `sign()` fn + per-method `parseX()` fns — all extractable. Output is committed to `priv/native_adapters/<exchange>.exs` so codegen is reproducible without running OXC at compile time. Hand-fixes for genuinely venue-specific quirks layered on top via override hooks.
      Without N0, every exchange in N4–N7 reimplements the same boilerplate. With N0, per-exchange porting becomes "extract → review → patch the hard 20%."

- [ ] **Task N1: `CcxtOcx.Adapter` behaviours** [D:5/B:7/U:7 → Eff:1.4] 🚀
      Generate three behaviours from the same `.d.ts` parse Phase 2 already does: `Adapter.Public` (unsigned REST), `Adapter.Private` (signed REST), `Adapter.Stream` (WS). Every method family gets a callback. The macro-generated wrapper dispatches to the configured adapter; caller code is unaware of which implementation it hits.

- [ ] **Task N2: Routing layer** [D:3/B:6/U:7 → Eff:2.17] 🎯
      `Application.get_env(:ccxt_ocx, :adapter_routing)` keyed by `{exchange, method_family}`, default `:js`. Macro emits a dispatch in every wrapper: native if configured, else fall back to the JS adapter. Per-method override so migration is incremental, not big-bang. No restart required to flip a method.

- [ ] **Task N3: Conformance harness** [D:6/B:9/U:9 → Eff:1.5] 🚀
      *The leverage point.* For any `(exchange, method)`, run the JS path *and* the native path against the same input in parallel; assert struct equality after normalization. Plus T4's byte-equal signing comparison for private methods. Before any method flips to `:native` in production, conformance must agree across N runs on testnet *and* mainnet read-only. ExUnit + property-based generators for the input space.

- [ ] **Task N4: Native Binance — REST public** [D:5/B:8/U:6 → Eff:1.4] 🚀
      Lowest blast radius first: `fetchMarkets`, `fetchCurrencies`, `fetchOHLCV`, `fetchTicker`, `fetchOrderBook`. With N0 in place, the bulk is auto-generated `defendpoint` declarations from CCXT's source; hand-work is reviewing the extracted parser functions and patching any quirks the extractor missed. Conformance harness must agree before ship. *Score reflects N0 leverage — without N0, this would be D:7/Eff:1.0.*

- [ ] **Task N5: Native Binance — WS public** [D:7/B:8/U:6 → Eff:1.0] 📋
      Mint.WebSocket directly. CCXT pro's WS impl is mostly subscription-message templates + orderbook diff-merge logic. N0's extractor handles the subscription-message templates and snapshot-fetch URLs; the **orderbook diff/snapshot reconciliation state machine remains hand-written per venue**. Get it wrong and you ship phantom liquidity. *Modest macro leverage — D drops from 8 to 7 because the boilerplate shrinks but the hard core (merge logic) doesn't.*

- [ ] **Task N6: Native Binance — REST private (signed)** [D:8/B:9/U:7 → Eff:1.0] 📋
      Highest stakes. Gated on T4 byte-equality passing for 1000+ randomized orders on testnet. N0 emits the request envelope, struct hydration, and the canonical query-string assembly — but **signing-quirk surface is hand-coded per venue** (recvWindow drift handling, listenKey rotation, subaccount header propagation, clock-skew tolerance). Read the CCXT `sign()` function line-by-line; don't paraphrase. *Modest macro leverage — D drops from 9 to 8.*

- [ ] **Task N7: Replicate to next 4 exchanges** [D:8/B:8/U:6 → Eff:0.88] ⚠️
      Pick the next 4 venues that matter (likely: Deribit, OKX, Bybit, Coinbase). Each one is a fresh signing dialect, fresh WS protocol, fresh quirk surface. With N0, the per-exchange boilerplate is auto-extracted; hand-work concentrates on each venue's signing quirks and orderbook merge logic. **Score is still moderate** — this is the long tail of porting work and the realistic stopping point for most projects, but the macro leverage shifts it from "infeasible" to "tractable." *D drops from 9 to 8 with N0.*

- [ ] **Task N8: CCXT-drift policy** [D:3/B:7/U:6 → Eff:2.17] 🎯
      Document the operational tax: every CCXT release ships adapter fixes (new fields, normalized formats, bug fixes for venue API changes). Once on native, those don't propagate. Either pin a CCXT version and accept drift, or subscribe to CCXT's git log and port relevant fixes per release for migrated exchanges. The honest framing is "native exchanges are now your responsibility to maintain"; budget engineering time accordingly.

---

## Risk Register (track but don't act on yet)

- **Bundle vs ESM entry**: this session used `dist/ccxt.browser.min.js` (5.4MB webpack bundle). The package's `import` entry `js/ccxt.js` is unbundled ESM and may behave differently — possibly smaller per-runtime memory if QuickBEAM can resolve the imports. Worth a one-off comparison before Phase 2 lands.
- **`self.ccxt.exchanges` is an Object, not an Array** in this bundle, but `self.ccxt.default.exchanges` is the Array. Pick one, document in `CcxtOcx.Runtime`, and don't drift.
- **Per-exchange pro WS endpoint quirks**: not every exchange in CCXT pro has been verified to work under Mint-backed WebSocket. Phase 3 should test a representative spread (Binance ✅, Kraken, OKX, Bybit, Coinbase) before claiming broad support.
- **Compile-time bundle eval (Task 9)**: spinning a QuickBEAM runtime *during compilation* is unusual. CI environments without precompiled NIFs may struggle. Vet before committing to the approach; fallback is to commit a generated `.exs` manifest to the repo and regenerate on bundle bumps.
