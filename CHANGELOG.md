# Changelog

All notable changes to `ccxt_ocx` are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Phase 1: Foundation — Runtime Lifecycle

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

### CI

Added `.github/workflows/harness.yml` — deterministic Elixir harness
gate for PRs targeting `development`. Steps: setup-beam from
`.tool-versions` → cache deps + node_modules → `mix deps.get` →
`mix npm.install` (CCXT bundle is a compile-time dep for
`CcxtOcx.Tiers`) → compile with warnings-as-errors → format check →
credo strict (excluding `TagTODO`/`TagFIXME`) → doctor → sobelow →
tests with ≥80% coverage gate → dialyzer.

[Unreleased]: https://github.com/efries/ccxt_ocx/compare/HEAD
