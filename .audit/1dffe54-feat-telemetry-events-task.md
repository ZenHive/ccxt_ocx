---
sha: 1dffe54
short_sha: 1dffe54
audited_at: 2026-05-17
auditor_model: claude-opus-4-7
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: feat: Telemetry events (Task 14) (#6)

**Original commit:** `1dffe54` — merge of PR #6
**Author:** E.FU
**Files touched:** ~8
**LOC:** +~600 (production + test + doc)

## Findings

| #  | Pri | Category    | File:Line                                | Description                                                                                                                                                                | Resolution |
|----|-----|-------------|------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------|
| T1 | 4   | doc-gap     | `lib/ccxt_ocx/telemetry.ex` moduledoc    | `[:ccxt_ocx, :runtime, :start]` / `:stop` event names defined as module attributes but neither documented nor used; Task 14's surface doesn't actually emit them yet      | Applied: extended moduledoc to mark them as reserved-for-Task-15 (runtime lifecycle); added explicit metadata-shape table for `:memory` covering all three emission paths |
| T2 | 4   | doc-gap     | `lib/ccxt_ocx/telemetry.ex` accessors    | 8 internal `__name__` accessor functions had no `@spec` despite the project's "every function gets a @spec" mandate in `development-philosophy.md`                        | Applied: added 7 missing `@spec` annotations (one per accessor: `__rest_start__/0` … `__runtime_stop__/0`) |
| T3 | 3   | doc-gap     | `CHANGELOG.md`                            | Listed `{:telemetry, "~> 1.0"}` but `mix.exs` pins `{:telemetry, "~> 1.3"}` (Task 14 needed 1.3 features)                                                                  | Applied: fixed to `~> 1.3` |
| T4 | 3   | doc-gap     | `lib/ccxt_ocx/runtime_pool.ex` moduledoc | Telemetry section said pool emits `%{pool: name}` — vague: pool refs can be atoms, pids, or `{:via, ...}` tuples per `t:pool/0`                                            | Applied: rewrote to describe the actual pool_ref shape and cite the type alias |

## Auto-applied fixes

- **`lib/ccxt_ocx/telemetry.ex` moduledoc** — Extended the Runtime section to mark `[:ccxt_ocx, :runtime, :start]` and `:stop` as Task-15-reserved (so a future audit doesn't flag them as dead attributes), and added an explicit "Metadata shape for `:memory`" table covering all three emission sites: explicit `Runtime.memory/1` call (`%{server: pid()}`), lifecycle emit from `Runtime.init/1` and `terminate/2` (`%{server: pid(), phase: :init | :terminate}`), and pool sample from `RuntimePool.memory/1` (`%{pool: pool_ref}`).
- **`lib/ccxt_ocx/telemetry.ex` `@spec` additions** — One-liner `@spec` for each of 7 internal `__name__` accessors. Return types follow the event-list shape: `[:ccxt_ocx | :rest | :start, ...]`, etc. `prefix/0` already had a `@spec`.
- **`CHANGELOG.md`** — `~> 1.0` → `~> 1.3`. Single line.
- **`lib/ccxt_ocx/runtime_pool.ex` moduledoc** — Telemetry section's pool-metadata sentence updated to: "with the caller's pool reference in the `pool` metadata key (an atom, pid, or `{:via, ...}` tuple, per `t:pool/0`)".

## Discuss-tier resolutions

(none — all findings were doc-only and clearly auto-applicable)

## Codex second-opinion

Status: **dual-reviewer** (full audit dispatched in parallel).

Corroborated findings: T1, T2, T3, T4 (all four).
Codex-only findings (verified): one additional moduledoc nit on `runtime_pool.ex` that overlapped with T4; rolled into T4's resolution.
Codex-only findings (discarded as over-flag): Codex flagged `:telemetry.span/3` as "dropping start metadata" in the wrapper at `telemetry.ex:106-121` — verified against the `telemetry` hex docs: `span/3` merges `start_metadata` into `stop_metadata` automatically, so the wrapper's empty stop-meta default does not drop the caller's start meta. Discarded.

## Acceptance criteria cross-reference

Task 14 acceptance criteria (from `roadmap/tasks.toml`):

- ✅ `CcxtOcx.Telemetry` module with stable `[:ccxt_ocx]` prefix
- ✅ Event family constants (REST, WS, Runtime) defined as module attributes
- ✅ `span/3` wrapper supporting bare-result, `{:telemetry_span, result, stop_meta}`, and `{:telemetry_span, result, extra, stop_meta}` return shapes
- ✅ `execute/3` wrapper for direct emission
- ✅ `[:ccxt_ocx, :runtime, :memory]` emitted on demand by `Runtime.memory/1` + `RuntimePool.memory/1` + lifecycle baseline/final
- ✅ Test coverage for emission paths
- ✅ Moduledoc documents the contract for downstream consumers (PromEx, TelemetryMetrics, Datadog, custom handlers)

## Notes for future drift audits

- `[:ccxt_ocx, :runtime, :start]` / `:stop` are reserved-for-Task-15. The next audit pass after Task 15 ships should confirm they're emitted at `Runtime.init/1` (success) and `terminate/2` (with reason) per the lifecycle pattern, and the moduledoc's "Task 15" note should be replaced with the actual contract.
- REST and WS event families (`:rest, :start|:stop|:exception` and `:ws, :tick`) are similarly defined but not yet emitted — they're the contract Phase 2/3 macros (`defunified`, `defstreaming`) will fulfill. Same drift-check applies when those macros land.
