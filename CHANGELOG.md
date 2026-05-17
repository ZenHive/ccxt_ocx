# Changelog

All notable changes to `ccxt_ocx` are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Phase 2: Macro-Driven Method Generation

#### Task 6: Discover and parse CCXT declaration sources (`CcxtOcx.Declarations`)
**Completed** | [D:6/B:8/U:8 → Eff:1.33] 📋

Compile-time parser that turns CCXT's real TypeScript declarations into rich
per-method terms (name, params, return type, owning surface, overrides) for
the Phase 2 macro layer to consume.

- New `CcxtOcx.Declarations` facade + `CcxtOcx.Declarations.Compile` parser — walks `js/src/base/Exchange.d.ts`, the per-exchange `*.d.ts`, and `pro/*.d.ts` with `OXC.parse/2` + `OXC.collect/2`, classifying methods by `:base`, `:exchange`, or `:pro` surface and capturing per-exchange overrides.
- Filter ownership (verb-prefix allowlist, internal-prefix denylist, exact-name denylist, bare-name trade-plane allowlist) centralized here. `CcxtOcx.BundleSurface.Compile` now delegates to `Declarations.Compile.public_unified_method?/1` so the "what gets a `defunified` wrapper" decision lives in one place.
- Overrides map keyed by `"surface:exchange_id"` so a method declared in both `js/src/<id>.d.ts` and `js/src/pro/<id>.d.ts` (e.g. `kucoinfutures.fetchBidsAsks`) keeps both override entries.
- Loud layout guard raises with actionable instructions if CCXT bumps and the three smoke methods (`fetchTicker`, `createOrder`, `watchTicker`) disappear from the base surface.

### Phase 5: Production Hardening

#### Task 21: PromEx plugin (`CcxtOcx.PromEx.Plugin`)
**Completed** | [D:3/B:7/U:7 → Eff:2.33] 🎯

Ship-with-the-library PromEx plugin that maps every `[:ccxt_ocx, ...]` event to Prometheus metrics with zero glue.

- New `CcxtOcx.PromEx.Plugin` — `event_metrics/1` covers runtime memory (live), REST (Phase 2-reserved), and WS tick (Phase 3-reserved). `polling_metrics/1` is opt-in via `pool:` / `poll_rate:` opts and drives `CcxtOcx.RuntimePool.memory/1` on a timer.
- Tag normalizers default missing metadata keys to `"none"`, stringify atoms, and inspect PIDs — Prometheus labels stay stable across emission sites (Runtime, RuntimePool, future macro-generated callers).
- `{:prom_ex, "~> 1.11", optional: true}` — pulled in for compile but not forced on consumers. `:bandit` extended to `:test` so `PromEx.Plug` compiles. `:telemetry_metrics` added to dialyzer `plt_add_apps`.
- "Observability — PromEx" section in README with consumer config snippet.
- Tests cover plugin shape, polling gating, custom poll rates, and live-emission tag normalization.

#### Task 14: Telemetry events
**Completed** | [D:3/B:7/U:7 → Eff:2.33] 🎯

Canonical `:telemetry` events under the `[:ccxt_ocx]` prefix so Prometheus, Datadog, PromEx, etc. can attach with zero glue code.

- New `CcxtOcx.Telemetry` module — single owner of the prefix, event name constants, `span/3` + `execute/3` helpers, and full documentation of the three families (`:rest`, `:ws`, `:runtime`).
- `CcxtOcx.Runtime.memory/1` + `memory_usage/1` (raw) — emit `[:ccxt_ocx, :runtime, :memory]` with QuickJS stats; baseline snapshot on init, final snapshot on terminate.
- `CcxtOcx.RuntimePool.memory/1` — samples any worker and emits with `pool` metadata.
- Tests, moduledoc sections, and a short README blurb.
- `{:telemetry, "~> 1.3"}` added as a runtime dependency.

This is the first deliverable of Phase 5 and the observability seam for Task 15 (memory monitoring) and all future macro/WS work.

### Phase 1: Foundation — Runtime Lifecycle

#### Task 5b: Bundle-bump verification pipeline
**Completed** | [D:5/B:8/U:8 → Eff:1.6]

`mix ccxt.verify_bundle` + supporting `CcxtOcx.BundleSurface.*` modules that protect the compile-time generated surface from silent regressions when CCXT releases (multiple times per week).

- New persistent, human-reviewable manifest at `priv/ccxt_surface.exs` (unified public methods + sampled per-exchange `has` tables).
- `CcxtOcx.BundleSurface.Compile` – OXC extraction of the unified method list from `Exchange.d.ts` + throwaway QuickBEAM probe for live `has` tables (modeled on the existing `Tiers.Compile` pattern).
- `Mix.Tasks.Ccxt.VerifyBundle` – the CLI entry point (`mix ccxt.verify_bundle` and `--accept` for deliberate drift).
- `@external_resource` on the manifest so changing the committed surface forces recompilation of downstream macro modules.
- CI step added to the harness after `mix npm.ci` — every PR that touches the CCXT package now runs the verifier.
- Minimal test coverage for the extraction + manifest read paths.

This is the last piece of Phase 1. Future macro work (Tasks 6–9) and the testnet harnesses (T1–T3) can now safely ride on top of a verified CCXT bundle.

#### Task 3: `CcxtOcx.RuntimePool`
**Completed** | [D:5/B:8/U:7 → Eff:1.5]

Supervised pool of long-lived `CcxtOcx.Runtime` workers built on `NimblePool`.
Each worker keeps its QuickBEAM runtime alive across calls so the ~2s CCXT
bundle eval is paid once per worker boot rather than once per `run/3` call.

- `CcxtOcx.RuntimePool.start_link/1` (`:name`, `:size`, `:runtime_opts`).
- `run/3` — primary call path; checks out a worker, invokes
  `fun.(rt)` against the raw QuickBEAM handle, checks back in.
- `info/1` — diagnostic snapshot (`size`, `ccxt_version`, `exchange_count`)
  cached at start-up via a synchronous probe runtime.
- `stop/1` — cascading shutdown that unlinks, monitors, and casts; idempotent
  against an already-dead pid.
- Application supervisor conditionally starts `CcxtOcx.RuntimePool.Default`
  when `:start_default_pool` is true (default).
- Crash recovery: idle dead workers are caught lazily by
  `handle_checkout/4`'s `Process.alive?/1` check; checked-out worker deaths
  are caught via NimblePool's client monitor. Bundle-reload cost is paid on
  death, not per call.
- `pool_size/0` defaults to `System.schedulers_online()` (read at start time,
  not compile time).
- Adds `{:nimble_pool, "~> 1.1"}` to `mix.exs`.
- Tests cover the lifecycle (start, info, stop, invalid-size rejection,
  bogus-bundle-path init failure), `run/3` (happy path, concurrent N-task,
  callback-raise propagation, exit-reason discrimination, checkout timeout,
  long-lived JS state across runs), worker callback unit, and crash
  recovery (kill → replace → subsequent run succeeds).

#### Task 4: `CcxtOcx.Error`
**Completed** | [D:4/B:7/U:6 → Eff:1.62]

Canonical error handling for the entire library.

- Closed 9-tag taxonomy: `:bad_symbol | :network | :rate_limit | :auth | :not_found | :permission | :exchange | :timeout | :unknown`.
- `%CcxtOcx.Error{}` struct with required `:tag`, `:source`, `:source_name` plus optional `:exchange`, `:method`, `:original`, `:meta`.
- `:source` / `:source_name` discriminator future-proofs the shape for Phase 7 native adapters (e.g. `source: :binance`, `source_name: "51000"`).
- Three-function surface:
  - `tag_for_ccxt_class/1` — pure CCXT class → tag mapper (used by the gate).
  - `from_js_error/2` — turns `%QuickBEAM.JSError{}` or raw map into the struct.
  - `normalize/2` — primary wrapper API; accepts raw error / tag / struct + keyword opts for context injection.
- Compile-time drift gate: `@external_resource "ccxt/js/src/base/errors.d.ts"` + exhaustive check at compile time. New CCXT error subclasses fail the build until mapped.
- Full `Exception` behaviour (raise / `Exception.message/1` / rescue).
- Tests cover the pure mapping table plus real CCXT error objects constructed inside a QuickBEAM runtime.

#### Task 1: `CcxtOcx.Runtime`
**Completed** | [D:4/B:9/U:9 → Eff:2.25]

Added `CcxtOcx.Runtime` — a GenServer that owns one QuickBEAM runtime with
the ccxt browser bundle pre-loaded. The GenServer's job is lifecycle (start
→ apply browser stubs → load bundle → terminate); it does **not** proxy
every JS call. `eval/3`, `call/4`, `with_runtime/2`, and `info/1` fetch the
raw runtime handle once and dispatch through QuickBEAM directly, so call
latency matches calling QuickBEAM yourself.

Key decisions:

- Browser stubs are applied via `globalThis.self = globalThis;` etc. through
  `QuickBEAM.eval/3` — `set_global/3` would coerce atoms to strings and the
  ccxt webpack bundle would not recognize them.
- The Runtime depends on `self.ccxt.default.exchanges` being the Array (the
  Risk Register pin from `ROADMAP.md`). A test fails loud if a future ccxt
  release reshuffles this path.
- `with_runtime/2` is a plain function call — callers don't link to the
  runtime. A caller crash mid-call leaves the runtime alive (verified by
  test).
- The Runtime is **not** added to `Application.start/2`'s child list. That
  belongs to Task 3 (`RuntimePool`).

#### Task 2: Pin `quickbeam ~> 0.10.4`
**Completed** | [D:1/B:5/U:6 → Eff:5.5]

Lifted the `mix.exs` floor from `~> 0.10` to `~> 0.10.4`. QuickBEAM 0.10.3
fixed an upstream QuickJS-NG closure GC bug that affected handlers captured
in long-lived runtimes — exactly the streaming pattern in Phase 3 and the
authenticated WS streams in Task T5. Rationale recorded in CLAUDE.md
"Why these dependency floors" so the floor doesn't drift in future
sessions.

#### Task 5c: `CcxtOcx.Tiers`
**Completed** | [D:4/B:7/U:8 → Eff:1.88]

Added `CcxtOcx.Tiers` — priority-tier classification mirroring
`ccxt_extract`'s API surface (18 public functions). Tier roots are
hand-curated in `priv/priority_tiers.json` (5 tier1 / 6 tier2 / 13 tier3
/ 4 dex). Variant inheritance — `binance → binanceus`, `htx → huobi`,
`gate → gateio`, etc. — is derived at compile time by walking
`Object.getPrototypeOf` on every exchange class in the loaded CCXT
bundle.

Key decisions:

- Inheritance is **provable** from the JS class graph, not name-matched.
  The webpack-minified bundle returns mangled `constructor.name`, so the
  walk builds a `ctor → name` map keyed on the preserved IDs in
  `self.ccxt.default.exchanges` and compares prototypes by reference
  identity.
- Compile-time JS eval runs in a throwaway raw `QuickBEAM.start/1`,
  not via `CcxtOcx.Runtime` (which isn't supervised during `mix compile`).
- `@external_resource` annotations on both the bundle path and
  `priv/priority_tiers.json` mean recompile triggers when CCXT bumps
  *or* curation changes — no manual cache invalidation.
- First-compile cost is ~2.7s (much lower than the original ~30s
  estimate). CI cold builds pay it once.
- No runtime cache. The module attribute body freezes the variant map
  into a `%{id => tier}` lookup; runtime cost is zero JS, pure O(1)
  Elixir map lookups.

Curation drift policy: `ccxt_extract`'s `priv/priority_tiers.json` is
the inspiration but not the contract. `ccxt_ocx` ships to hex.pm and
cannot path-dep on its sibling, so curation changes are manually
ported.

#### Task 5: Smoke test suite
**Completed** | [D:3/B:6/U:5 → Eff:1.83]

Added `test/ccxt_ocx/smoke_test.exs` — automated replay of the Phase 1
Tidewave verification: CCXT bundle loads into QuickBEAM, OXC parses
`Exchange.d.ts` and confirms the smoke method surface, Binance public
REST returns ticker / order book / OHLCV / trades, and CCXT-pro streams
3 ticker pushes over WebSocket.

Tag scheme: offline tests (bundle + OXC) carry `:integration`; network
tests carry `:network`. Both are excluded by default in
`test/test_helper.exs` so `mix test` stays fast and offline. Opt-in via
`--include integration`, `--include network`, or both. `flunk/1` with
multi-line actionable messages on missing-bundle, missing CCXT-pro
surface, and network failure — no silent skips.

Key decisions:

- One `setup_all` runtime shared across all 7 tests amortizes the
  ~2-3s bundle-load cost; tests are sequential (`async: false`) but
  use a fresh CCXT exchange in JS so order is independent
  (verified with seeds 0 and 1).
- Symbol is `BTC/USDT:USDT` (USDT-margined linear perpetual). The
  default `self.ccxt.binance` in the browser bundle loads the
  derivatives market set; spot would need a different exchange class.
- The WebSocket test uses top-level await, not an IIFE — `(async () => {...})()`
  returns a Promise that `QuickBEAM.eval` doesn't resolve through.
  `JSON.stringify` on the final result also dodges `max_convert_depth`
  truncation on the nested ticker maps.
- CCXT constructor takes `timeout: 30000` to give margin over CCXT's
  default 10s internal fetch timeout, especially on cold loads.

### CI

Added `.github/workflows/harness.yml` — deterministic Elixir harness
gate for PRs targeting `development`. Steps: setup-beam from
`.tool-versions` → cache deps + node_modules → `mix deps.get` →
`mix npm.install` (CCXT bundle is a compile-time dep for
`CcxtOcx.Tiers`) → compile with warnings-as-errors → format check →
credo strict (excluding `TagTODO`/`TagFIXME`) → doctor → sobelow →
tests with ≥80% coverage gate → dialyzer.

[Unreleased]: https://github.com/efries/ccxt_ocx/compare/HEAD
