---
sha: dc8971960122d3847d838ef2673fe3f618cfc68f
short_sha: dc89719
audited_at: 2026-05-17
auditor_model: claude-opus-4-7
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: feat(Task 3): CcxtOcx.RuntimePool — supervised CCXT runtime pool (#3)

**Original commit:** `dc89719` — merge of PR #3
**Author:** E.FU
**Files touched:** 10
**LOC:** +631 / −15 (production-code delta: +309 runtime_pool.ex + +46 worker.ex + +24/-3 application.ex)

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 5   | doc-gap  | lib/ccxt_ocx/runtime_pool.ex:32-37 | Moduledoc claims "NimblePool monitors each worker"; actually NimblePool only monitors clients/async-init, not idle workers | Applied: moduledoc rewritten to describe lazy detection via `handle_checkout`'s alive-check |
| 2 | 4   | bug      | lib/ccxt_ocx/runtime_pool.ex:287-291 | TOCTOU: pool can die between `pool_pid/1` alive-check and `Process.monitor/1`; `await_stop` then exits caller with `:noproc` instead of `:ok` | Applied: added `:noproc` to `expected_shutdown_reason?` |
| 3 | 6   | doc-gap  | CHANGELOG.md:9   | No `## [Unreleased]` entry for the Task 3 RuntimePool feature | Applied: added Task 3 entry under Phase 1 (above existing Task 4 entry) |
| 4 | 7   | doc-gap  | ROADMAP.md:42    | Task 3 marker left as `🔄` in this commit | **Already resolved within audit range** by `1ce2280` (next commit) — no action |
| 5 | 7   | doc-gap  | roadmap/tasks.toml:117 | Task 3 source status left as `in_progress` in this commit | **Already resolved within audit range** by `1ce2280` — no action |

## Auto-applied fixes

- **`lib/ccxt_ocx/runtime_pool.ex:32-37`** — Rewrote "Crash semantics" paragraph. Old text claimed "NimblePool monitors each worker. A worker death is caught, the dead worker is replaced…", implying real-time detection of any worker death. Verified against `deps/nimble_pool/lib/nimble_pool.ex`: NimblePool's `Process.monitor/1` calls are on (a) clients during checkout (`handle_checkout` site monitors the caller) and (b) async-init workers during start. Idle workers sitting in the `:queue` resource list are NOT monitored. The `Worker.handle_checkout/4` callback in this commit (`if Process.alive?(server), do: {:ok, ...}, else: {:remove, :dead_worker, ...}`) IS the load-bearing detection for idle deaths. New text describes both paths (idle-death = lazy via handle_checkout; checked-out-death = via client monitor) so the reader matches the actual recovery model.

- **`lib/ccxt_ocx/runtime_pool.ex:289`** — Added `defp expected_shutdown_reason?(:noproc), do: true` with a comment naming the TOCTOU. Race: `pool_pid/1` returns the pid (alive at check), pool exits between that return and the caller's `Process.monitor/1`, monitor fires `{:DOWN, _, _, _, :noproc}` immediately, `await_stop` calls `expected_shutdown_reason?(:noproc)` which was `false` → `exit(:noproc)`. The existing test `"stop/1 treats an already-stopped pid as stopped"` covers the post-death `pool_pid → nil` short-circuit but not this racing-dying window. Caller-asked-us-to-stop + pid-already-gone IS the post-condition of `stop/1`, so the `:ok` return is correct. Single-line addition, contract-preserving (`:ok` instead of `exit(:noproc)` on the race), no new public surface.

- **`CHANGELOG.md`** — Added `#### Task 3: CcxtOcx.RuntimePool` block under `## [Unreleased]` → `### Phase 1: Foundation — Runtime Lifecycle` (above the existing Task 4 entry, matching the file's most-recently-added-on-top pattern). Body covers the `start_link/1` / `run/3` / `info/1` / `stop/1` surface, application-supervisor wiring, crash recovery model, the new `nimble_pool ~> 1.1` dep, and the test surface.

## Findings dropped from auto-apply

- Findings #4 and #5 — ROADMAP.md and roadmap/tasks.toml Task-3-still-🔄/in_progress. Both legitimate against the commit `dc89719` in isolation, but the very next commit in the audit range (`1ce2280` — "roadmap: mark Task 3 done") resolved them via `rmap status 3 done`. At HEAD they are no longer drift. Re-applying would either be a no-op (if rmap is idempotent) or conflict with the existing ✅ state. Dropping is the correct action.

## Discuss-tier resolutions

- (none — finding #2's race fix was classified `discuss-trivial` and auto-applied per the skill's "single coherent change, no new public surface, auditable in one read" criterion)

## Codex second-opinion

Status: **dual-reviewer**
Corroborated findings: 3 (CHANGELOG.md missing Task 3 entry — both reviewers raised independently)
Codex-only findings (verified): 1 (NimblePool monitoring claim — verified against `deps/nimble_pool/lib/nimble_pool.ex` line 578 client monitor + line 451 async-init monitor; no idle-worker monitor), 4, 5 (verified at commit dc89719 but resolved by subsequent in-range commit)
Codex-only findings (discarded as over-flag): —
Claude-only findings (kept): 2 (the `stop/1` TOCTOU `:noproc` race — verified by reading the codepath against Erlang's documented `Process.monitor/1` behavior on dead pids)

Codex pre-flight verification: ran `mix test.json --cover` offline (RuntimePool 80.6% / Worker 83.33% — meets ≥80% standard-business-logic tier), confirmed NimblePool callback tuple shapes against `deps/nimble_pool`, confirmed the moduledoc's "~2s per call" claim against `deps/quickbeam/lib/quickbeam/pool.ex` (`Pool.run/3` does call `QuickBEAM.reset/1` between checkouts, which re-evals — claim is true).

## Acceptance criteria cross-reference

PR #3 / Task 3 acceptance criteria (from `roadmap/tasks.toml`, derived):
- ✅ `CcxtOcx.RuntimePool` GenServer-wrapped NimblePool with long-lived workers
- ✅ `run/3` primary API; `info/1` diagnostic snapshot; `stop/1` cascading shutdown
- ✅ `:size` defaults to `System.schedulers_online()` (runtime read, not module attribute — verified line 127)
- ✅ Application-supervisor wiring conditional on `:start_default_pool`
- ✅ Crash recovery: kill worker → pool replaces → next `run/3` succeeds (test `crash recovery` block)
- ✅ Coverage ≥80% on RuntimePool + Worker (Codex measured 80.6 / 83.33)
- ✅ `nimble_pool ~> 1.1` added to `mix.exs`
- ⚠ `CHANGELOG.md` entry was missing — **fixed by this audit**
- ⚠ ROADMAP/tasks.toml status flip was missing in this commit — **fixed by the next commit in the audit range (`1ce2280`)**

## Notes for future audits

- `.codex/config.toml` was added in this commit pointing at `localhost:4014/tidewave/mcp`. Not in `.gitignore`. Intentional shared MCP config (mirroring Cursor's `.cursor/mcp.json` shared-config pattern per CLAUDE.md). No finding.
- `.sobelow-skips` change is a benign line-fingerprint regen (line `runtime.ex:221` → `runtime.ex:234` because runtime.ex picked up an unrelated edit elsewhere in the file).
- `TODO(Task 9)` marker on lines 61-63 (defstruct migration) is properly formatted and references an out-of-range future task — not actionable in this audit.
