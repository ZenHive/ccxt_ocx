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

[Unreleased]: https://github.com/efries/ccxt_ocx/compare/HEAD
