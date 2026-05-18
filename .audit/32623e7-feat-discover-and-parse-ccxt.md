---
sha: 32623e742d606bb0d653982db07589bc30572def
short_sha: 32623e7
audited_at: 2026-05-18
auditor_model: claude-opus-4-7
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: feat: discover and parse CCXT declarations (Task 6) (#9)

**Original commit:** 32623e7 — `feat: discover and parse CCXT declarations (Task 6) (#9)`
**Author:** E.FU
**Source PR:** [#9](https://github.com/ZenHive/ccxt_ocx/pull/9)
**Linked issue:** none parsed
**Files touched:** several (lib/ccxt_ocx/declarations.ex + lib/ccxt_ocx/declarations/compile.ex new, lib/ccxt_ocx/bundle_surface/compile.ex updated, test/ccxt_ocx/declarations_test.exs new, .sobelow-skips, CHANGELOG.md, ROADMAP.md, roadmap/{data.json,tasks.toml})
**LOC:** +669

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 3 | Missing extraction (test) | test/ccxt_ocx/declarations_test.exs:113 | Brittle `> 50` magic-number threshold for exchange/pro `.d.ts` counts — tracks upstream CCXT catalog churn instead of catching real parser regressions. Corroborated by CodeRabbit (PR review) and Codex second-opinion. | Applied: replaced with `!=  []` + explicit `binance.d.ts` membership assertions. |

Pre-merge bot-finding triage (PR #9):

| Bot finding | Status |
|---|---|
| Copilot + CodeRabbit + Codex GH bot: smoke-method base validation uses `Enum.any?` instead of per-method check | ✅ Addressed at shipped SHA — `Enum.reject(@required_smoke_methods, ...)` with per-method `%{primary: %{surface: :base, source: ...Exchange.d.ts}}` check. Comment in source explicitly notes the previous `Enum.any?` failure mode. |
| Copilot + CodeRabbit: override-surface test flattens KEYS not surface values | ✅ Addressed at shipped SHA — `test/ccxt_ocx/declarations_test.exs:94-101` now uses `Map.values()` + `& &1.surface`, asserts both `:exchange` and `:pro` present. |
| Codex second-opinion: `Path.rootname/1` bug at commit time | ✅ Fixed in subsequent commit (documented in CHANGELOG under "Fix shipped with Task 6b") — switched to `Path.basename(p, ".d.ts")`. |
| Codex second-opinion: `render_type/1` missing real `@doc` at commit time | ✅ Fixed in subsequent commits — public `render_type/1` now has a real `@doc` describing the recursive TS type renderer behavior. |

## Auto-applied fixes

- test/ccxt_ocx/declarations_test.exs: replaced `length(...) > 50` with `!= []` + canonical-exchange membership checks (`binance.d.ts`).

## Discuss-tier resolutions

- (none)

## Codex second-opinion

Status: dual-reviewer
Task: `task-mpb285rv-9nxoc3` (8m 28s)
Corroborated findings: 1 (with CodeRabbit)
Codex-only findings (verified): —
Codex-only findings (discarded as over-flag): —
