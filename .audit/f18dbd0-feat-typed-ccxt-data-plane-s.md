---
sha: f18dbd0c8584df296b3f5d28161d8086ea4f6a8c
short_sha: f18dbd0
audited_at: 2026-05-18
auditor_model: claude-opus-4-7
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: feat: typed CCXT data-plane structs (Task 8)

**Original commit:** f18dbd0 — `feat: typed CCXT data-plane structs (Task 8)`
**Author:** E.FU
**Source PR:** (direct push to `development` — no PR review trail)
**Linked issue:** none
**Files touched:** 16 (lib/ccxt_ocx/{struct.ex, structs.ex, ticker.ex, order_book.ex, candle.ex, trade.ex, market.ex, currency.ex} new; lib/ccxt_ocx.ex, lib/ccxt_ocx/declarations/compile.ex, lib/ccxt_ocx/macros/use.ex updated; .doctor.exs, .sobelow-skips, CHANGELOG.md, roadmap/tasks.toml, test/ccxt_ocx/struct_test.exs new)
**LOC:** +898

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 8 | Bug | lib/ccxt_ocx/structs.ex:41 | `hydrate/2` regex stripped `[].*$` BEFORE unwrapping `Promise<...>`. Result: `Promise<Trade[]>` collapses to `"Promise<Trade"` (missing closing `>`), registry lookup misses, returns raw maps. **Affects every `fetchTrades`, `fetchOHLCV`, `fetchOrders` return shape** — the most common Phase 2 use case for v0.1. **Verified live** via `mix run` / Tidewave probe: pre-fix `Promise<Trade[]>` returned raw maps; post-fix returns list of `%CcxtOcx.Trade{}`. | Applied: reordered to unwrap `Promise<...>` first, then test for trailing `[]`. All seven shapes (`Promise<X>`, `Promise<X[]>`, `X[]`, `X`, etc.) now hydrate correctly. |
| 2 | 7 | Bug | lib/ccxt_ocx/struct.ex:74,95 | `field/2` macro was documented as a convenience but `__using__/1` imported only `field: 3`. Calling `field :symbol, :string` (the documented 2-arg form) raised `undefined function field/2`. Even if imported, it expanded to `field/3` with `[]` opts → `field/3` validated `from: nil` BEFORE applying the default, raising `NimbleOptions.ValidationError`. | Applied: removed `field/2` entirely (no call sites used it). Reordered `field/3` to compute default `from:` BEFORE NimbleOptions validation so the validator never sees a nil. |
| 3 | 5 | Missing extraction (test) | test/ccxt_ocx/struct_test.exs:114 | The Task 8 drift gate maps `Ticker / OrderBook / Trade` to their `__ccxt_fields__/0`, but returns `[]` for `MarketInterface` and `CurrencyInterface` — those struct's `from:` keys aren't actually checked against `types.d.ts`. Market/Currency rename would pass silently. | Applied: added Market/Currency cases to the test's interface→fields mapping; added Market/Currency to test aliases. |
| 4 | 3 | Missing TODO marker | lib/ccxt_ocx/order_book.ex:5,23 | OrderBook moduledoc + field comment describe "raw numbers passed through" as v0.1 behavior without `TODO:` prefix — Credo can't track. | Applied: added `TODO:` prefix on both the moduledoc note and the inline comment. |
| 5 | — | dropped (Codex over-flag) | .doctor.exs:1 | Codex flagged `.doctor.exs` ignoring `CcxtOcx.Struct` as a project-rule violation ("never suppress modules just to get green"). The file's comment documents this as a Doctor parser limitation: `Code.fetch_docs(CcxtOcx.Struct)` confirms every macro has `@doc`/`@spec`, but Doctor's parser only credits `def`. This is *exactly* the kind of documented limitation AGENTS.md asks for, not gaming. | Dropped. |
| 6 | — | informational | (process) | This commit was a direct push to `development` — no PR review trail. Two other commits in this audit batch (`2ea0bab`, this one) skipped PR; otherwise the project uses `(#NN)` squash merges. Bot ensemble didn't run on these. | Informational only — pre-existing `[BLOCK-MERGE]` / PR-workflow recommendation lives in `worktree-workflow.md`. |
| 7 | — | informational | git show f18dbd0:ROADMAP.md | At commit time, `roadmap/tasks.toml` flipped Task 8 to `done` but `ROADMAP.md` wasn't re-rendered. Already corrected on HEAD via subsequent `rmap render` (current ROADMAP shows Task 8 = ✅). | No fix needed — drift is closed on HEAD. |

## Auto-applied fixes

- lib/ccxt_ocx/structs.ex: fixed `hydrate/2` Promise<X[]> regex ordering — Promise wrapper stripped first, then `[]` suffix check. Verified live against 7 type shapes via Tidewave probe.
- lib/ccxt_ocx/struct.ex: removed broken `field/2` macro; reordered default-resolution before NimbleOptions validation in `field/3`.
- test/ccxt_ocx/struct_test.exs: added Market/Currency cases to drift-gate; added aliases.
- lib/ccxt_ocx/order_book.ex: added `TODO:` prefix on bid/ask money-string follow-up note.

## Discuss-tier resolutions

- (none — all findings either auto-applied, dropped as over-flag, or filed as direct-push informational.)

## Codex second-opinion

Status: dual-reviewer
Task: `task-mpb28ly2-n3kzoj` (5m 45s)
Corroborated findings: — (none with Claude; all were solo-Codex, but verified against actual code with one verified by live probe)
Codex-only findings (verified, applied): 1, 2, 3, 4
Codex-only findings (discarded as over-flag): 5
Codex-only findings (informational only): 6, 7
