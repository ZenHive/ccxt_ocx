# AGENTS.md — Grok Instructions for ccxt_ocx

**This file is the primary instruction source for Grok sessions on this project.**

Claude Code sessions continue to use `CLAUDE.md` + its `@~` includes. Do not force Grok sessions through the `load-claude-includes` skill or the Claude include expansion process — it does not fit Grok's context model and leads to confusion.

## Project Overview

`ccxt_ocx` is a **macro-first** Elixir library that wraps CCXT. The JS bundle runs inside QuickBEAM. Per-exchange and per-method wrappers are generated at compile time from CCXT's own TypeScript declarations (via OXC).

- Phase 1 (foundation: `Runtime`, `RuntimePool`, `Error`, `Tiers`, `BundleSurface`, `Telemetry`) is complete.
- Phase 2 (macro-driven method generation: `use CcxtOcx`, `defunified`, typed structs, `defexchange`) is the current focus.
- Phase 7 (native-Elixir adapters for Tier-1 venues with byte-for-byte signing verification) is the long-term direction. The JS path stays forever as the conformance oracle.

The public API contract is generated. Hand-written per-method code is a smell.

## Core Domain Knowledge (Must Internalize)

### QuickBEAM Patterns Used Here
- Long-lived runtimes inside a supervised `CcxtOcx.RuntimePool` (not `QuickBEAM.Pool` per-call, because the ~5.4 MB CCXT browser bundle makes reset expensive).
- Browser stubs (`globalThis.self = globalThis`, `window`, `navigator`, `location`) before loading the CCXT bundle.
- "Define-then-call" pattern: `eval` to define async helpers/globals, then `call/3,4` to invoke them.
- Direct `eval` of the CCXT browser bundle inside the runtime at startup.
- Memory monitoring + restart policy on the pool workers (Task 15).
- Authenticated WS streams will use closure-capturing handlers (the pattern QuickBEAM 0.10.3+ fixed).

Re-read `~/.claude/includes/quickbeam.md` when designing anything that touches runtimes, pools, or WS.

### OXC Usage
- Compile-time parsing of `node_modules/ccxt/js/ccxt.d.ts`, `js/src/base/Exchange.d.ts`, per-exchange `.d.ts`, and pro `.d.ts` files.
- Also used for extracting REST endpoint + signing logic from `js/src/<exchange>.js` in Phase 7 (N0).
- Atom-keyed AST is the contract.

Re-read `~/.claude/includes/oxc.md` before touching `Declarations.Compile` or the `defendpoint` extractor.

### Macro Design Rules (Non-Negotiable)
- Cite real Elixir ecosystem precedents before designing new macros or adding complexity: `Phoenix.Router`, `Ecto.Schema`, `TypedStruct`, `Ash.Resource`, `NimbleOptions`, `Joken.Config`.
- Every macro that accepts options must use `NimbleOptions` for validation at compile time.
- The declarative surface (`defunified`, `defendpoint`, `defconformance`, `defstreaming`) is the contract. The backend (JS vs native) is an implementation detail that can change per `(exchange, method)`.
- Capability gating (`has?` checks) happens at emission time, not runtime.

Re-read the "Cite Ecosystem Precedents" and macro-related sections of `~/.claude/includes/development-philosophy.md` before proposing or implementing any new macro surface.

### Documentation & `mix doctor` Expectations (Strict)
- **Real `@doc` and `@spec` are mandatory** on all public functions and macros.
- **Never** use `@doc false` as a workaround to make `mix doctor` pass.
- **Never** suppress modules via `.doctor.exs` just to get a green status. Hiding poor documentation is worse than having it.
- `mix doctor` must pass cleanly through **honest, high-quality documentation**.
- LLMs and future agents will mirror whatever patterns exist in the codebase. Low-effort or gamed docs actively damage future code quality.

When adding new public surface (especially in macros or struct generators), write proper documentation first. Getting doctor green is a side effect of good work, not the goal.

### Reach + Cross-Language Analysis
- `Reach.Plugins.QuickBEAM` automatically stitches `QuickBEAM.eval` / `call` sites with JS function definitions when the source is a literal.
- Useful for architecture review of the macro-generated code and the JS ↔ Elixir boundary.

### Roadmap & Task System
- All work is declared in `roadmap/tasks.toml`.
- `rmap render` regenerates the tables in `ROADMAP.md`.
- Tasks have D/B/U scores and effectiveness. Use `rmap status`, `rmap mark`, `rmap new`.
- Never hand-edit the `<!-- TASKS:BEGIN -->` sections in `ROADMAP.md`.
- Current focus is Phase 2 (Tasks 7–10) moving toward v0.1 data plane.

### Verification-First Trade Plane
- Signed methods are generated in Phase 2 but only become usable after Phase 4 (testnet harnesses + T4 byte-equality signing comparison).
- Native ports (N4–N7) are gated on N3 conformance + T4.
- Never claim a signed path is safe without the verification harnesses passing.

## Grok-Specific Guidance on This Codebase

**Strengths** (lean on these):
- Macro design and implementation (`defunified`, `defendpoint`, typed struct hydration, capability gating).
- Compile-time introspection + caching strategy (`priv/exchange_caps/`, `priv/ccxt_surface.exs`).
- Architecture that keeps JS and native paths behind the same public contract.
- Large-scale refactoring while preserving the generated surface.

**Weaknesses** (do not own these without heavy review):
- Final implementation or audit of real signing logic (N6/N7) and the byte-equality harness (T4). Subtle canonical-string, recvWindow, listenKey, clock-skew, and nonce issues are easy to get wrong in ways that only surface on mainnet.
- Deep production debugging of long-running authenticated WS under load (T5 + Task 15).
- Conformance harness edge cases (N3) where struct equality after normalization must hold across real venue responses.

When the work touches "can this signed request ever be rejected or replayed?", treat it as high-stakes and insist on human + multi-model review (Opus 4.7 is particularly strong here).

## Practical Rules

- Always run the project's standard gates after changes: `mix format`, `mix compile --warnings-as-errors`, `mix test.json`, `mix credo --strict`, `mix dialyzer.json --quiet`.
- Before mutating any module with significant logic, ensure its coverage is at the required tier (see `critical-rules.md`).
- Use `TODO:` prefix (with colon) for any temporary or uncertain code so Credo can track it.
- Explore real surfaces with Tidewave (`project_eval`) before writing parsers or mappers for complex responses (option chains, order books, etc.).
- The `use CcxtOcx` contract (Task 6b) is now stable for v0.1. Do not change the public surface without updating the macro contract and all downstream emission.

## When to Pull in More Context

- Designing or modifying any Phase 2 macro → read relevant parts of `development-philosophy.md`
- Anything touching runtimes, pools, or the CCXT bundle load → re-read `quickbeam.md`
- Working on compile-time declaration extraction or the native extractor → re-read `oxc.md`
- Changing task tracking or roadmap process → re-read `rmap.md` and `task-prioritization.md`
- Unsure about error taxonomy or source discrimination → re-read `critical-rules.md` and the `Error` module

## Memory & Session Notes

This workspace has a persistent memory file at `~/.grok/memory/ccxt-ocx-fc69fb04/MEMORY.md`. Important architectural decisions and gotchas discovered across sessions are recorded there. Use `memory_search` when you suspect prior context exists.

---

**Goal**: Make every Grok session on this repo immediately effective without repeating the same context-loading dance. Update this file as the project evolves.
