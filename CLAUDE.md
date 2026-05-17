# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`ccxt_ocx` is a **macro-first** Elixir wrapper around CCXT — the JS bundle runs inside QuickBEAM, and per-exchange/per-method wrappers are generated at compile time from CCXT's own type definitions. See [ROADMAP.md](ROADMAP.md) for the full vision. CCXT-family sibling of `ccxt_extract` and `ccxt_client`.

## Standard imports

@~/.claude/includes/across-instances.md
@~/.claude/includes/critical-rules.md
@~/.claude/includes/worktree-workflow.md
@~/.claude/includes/task-prioritization.md
@~/.claude/includes/task-writing.md
@~/.claude/includes/rmap.md
@~/.claude/includes/workflow-philosophy.md
@~/.claude/includes/web-command.md
@~/.claude/includes/elixir-setup.md
@~/.claude/includes/ex-unit-json.md
@~/.claude/includes/dialyzer-json.md
@~/.claude/includes/code-style.md
@~/.claude/includes/development-commands.md
@~/.claude/includes/development-philosophy.md
@~/.claude/includes/elixir-volt.md
@~/.claude/includes/oxc.md
@~/.claude/includes/quickbeam.md
@~/.claude/includes/reach.md
@~/.claude/includes/delegation.md

---

## Design philosophy: macros first

The public API is generated at compile time from CCXT's type definitions — **never hand-written**. CCXT's surface is ~100 exchanges × ~50 unified methods × (REST + WS) × (public + private); hand-written per-method wrappers don't scale. The macro layer is the contract; the adapter behind it (JS via QuickBEAM, or native Elixir for the venues that matter) is an implementation detail.

**Planned macro surface** (no macros implemented yet — Phase 1 foundation modules (`Runtime`, `RuntimePool`, `Error`, `Tiers`, `BundleSurface`, `Telemetry`) are in place, plus Phase 2's `Declarations` (Task 6) as the compile-time data source the macros below will consume; status per macro in [ROADMAP.md](ROADMAP.md)):

| Macro | Phase | Role |
|---|---|---|
| `use CcxtOcx, exchanges: [...]` | 2 (Task 6b) | Entrypoint — gates which per-exchange modules compile |
| `defunified` | 2 (Task 7) | Unified data-plane + trade-plane methods backed by JS |
| `defexchange` | 2 (Task 9) | Per-exchange capability metadata |
| `defstreaming` | 3 (Task 11) | WS subscription methods |
| `defendpoint` | 7 (Task N0) | Native-Elixir REST adapter declarations; declarative `:signed` option |
| `defconformance` | 7 (Task N3) | JS-vs-native pair specs (sample args, ignored fields, tolerance) |

**When proposing a new macro:** first check whether it folds into an existing macro's option surface. Signing variants belong on `defendpoint`'s `:signed` option, not a new `defsigner`. Rate-limit cost is metadata on `defunified`, not a new macro. New macros earn their cost only when the shape is declarative across **≥3 callsites with the same precedent in the Elixir ecosystem** — see `development-philosophy.md` § "Cite Ecosystem Precedents Before Crying Complexity" for the bar (Phoenix.Router, Ecto.Schema, NimbleOptions, TypedStruct, Ash.Resource).

**Scope is locked at "full unified CCXT surface."** Trade plane (`create_order`, signing, `setLeverage`, `watchMyTrades`) stays in the macro surface; verification (Phase 4 testnet harnesses + byte-equality signing comparison) gates it before mainnet. Don't propose narrowing scope based on hypothetical risk — see ROADMAP § Scope and the project memory on this.

**Companion tooling** Phase 2 leans on:
- **In the dep tree today:** OXC (parses CCXT's `.d.ts` and `js/src/<exchange>.js` to feed `defunified` / `defendpoint`), QuickBEAM (the macro-generated functions wrap runtime calls via `CcxtOcx.Runtime` — Task 1, done).
- **To be added when the macro that needs it lands:** NimbleOptions (validates every macro's option keyword per `~/.claude/includes/development-philosophy.md` § "Cite Ecosystem Precedents"). Add `{:nimble_options, "~> 1.x"}` to `mix.exs` as part of Task 7 (`defunified`) — the first macro to consume it.

---

## Tidewave

This project's Tidewave port is **4014** (registered in `~/.claude/tidewave-ports.md`).

```bash
iex -S mix tidewave   # listens on http://localhost:4014/tidewave/mcp
```

`.mcp.json` is project-scoped. After cloning, restart Claude Code so the MCP server registers.

See [docs/tidewave_examples.md](docs/tidewave_examples.md) for high-signal, copy-pasteable usage patterns discovered through live sessions (especially the define-then-call pattern and complex surface exploration).

## Common commands

```bash
mix deps.get
time mix compile --warnings-as-errors
mix test.json
mix dialyzer.json --quiet
mix credo --strict --format json
mix sobelow --mark-skip-all
```

## Dependency notes

- **Do not lower the `quickbeam` floor below 0.10.4.** quickbeam 0.10.3 fixed
  an upstream QuickJS-NG closure GC bug affecting handlers captured in
  long-lived runtimes — exactly the WS-streaming pattern this library uses.
  Bumps within 0.10.x are fine. Run `mix hex.outdated quickbeam` for the
  current state.
