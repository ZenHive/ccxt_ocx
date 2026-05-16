---
sha: 39ed93f32cd435bc224a07f9bb25ae48e6612472
short_sha: 39ed93f
audited_at: 2026-05-16
auditor_model: claude-opus-4-7
verdict: findings-applied
codex_status: cancelled-stalled
audited_by: audit-review v1
---

# Audit: feat: CcxtOcx.Tiers — priority-tier classification + CI harness (#1)

**Original commit:** `39ed93f` — merge of PR #1 (squash; head commits `b8d2674…067aa84`)
**Author:** E.FU
**Files touched:** 12
**LOC:** +1027 / −12

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 4   | doc-gap  | .github/workflows/harness.yml:52-60 | Cache step misses `priv/plts`; dialyzer rebuilds PLT every run | Applied: added `priv/plts` to cache paths |

## Auto-applied fixes

- `.github/workflows/harness.yml:52-60` — Added `priv/plts` to the cache `path` list and renamed the step ("Cache deps, _build, and dialyxir PLTs"). `mix.exs` pins `plt_local_path: "priv/plts"` and `plt_core_path: "priv/plts"` (per `elixir-setup.md` § "PLT location: `priv/plts/` not `_build/dialyzer/`"), but the original cache step covered only `deps` and `_build`. Net effect: dialyzer PLT now survives across CI runs instead of rebuilding cold (5–10 min saved per workflow).

## Codex second-opinion

Status: **cancelled-stalled** — single-reviewer pass
Codex investigation hit ~22 min of reasoning-step hang (matches the documented stall pattern in the skill's "Codex review hang" reference). Log showed Codex completed file inspection and emitted two assistant-message previews:

1. "One concrete mismatch is already visible: the workflow runs `mix npm.ci`, and the repo declares the `:npm` dependency but no local alias for that task." — **invalid finding.** `npm_ex` ships `mix npm.ci` as a regular mix task (verified via `mix help | grep npm.` in this session — "Install from lockfile (CI mode)"). No alias needed.
2. "A couple of candidates are doc drift rather than runtime bugs" — Codex never emitted the actual table; reasoning step never returned findings.

User redirect: dual-reviewer ceremony over-applied to a data-classification module (no signing / crypto / wire format). Cancelled and proceeded single-reviewer with the one substantive finding from the CodeRabbit + Claude pass.

Corroborated findings: —
Codex-only findings (verified): —
Codex-only findings (discarded as over-flag): 1 (`mix npm.ci` alias claim)

## Acceptance criteria cross-reference

PR #1 acceptance criteria (from `roadmap/tasks.toml` Task 5c body):
- ✅ Tier roots committed to `priv/priority_tiers.json` — 5/6/13/4 buckets present
- ✅ Variant inheritance derived at compile time via `Object.getPrototypeOf` walk — reference-identity `Map` keying (bot finding #2 fixed pre-merge)
- ✅ Public API mirrors `ccxt_extract`: `tier1_members/0`, `members_for_tier/1`, `get_priority_tier/1`, `tier1?/1`, `collect_tier_exchanges/1` — all present with `@doc` + `@spec`
- ✅ Drift policy documented in moduledoc
- ✅ ROADMAP marks 5c ✅; CHANGELOG entry present with matching score `D:4/B:7/U:8`

## Pre-merge bot findings (all fixed before merge)

For audit completeness — the 5 substantive bot findings were addressed in commit `067aa84` before merge:

1. `tiers.ex` `has_tier_flags?/1` — now returns boolean per `@spec` via `Enum.any?/2`
2. `tiers/compile.ex` JS walk — `new Map()` with `.set/.get` (reference-identity)
3. `tiers.ex` `@tier_member_map` build — raises `CompileError` on cross-tier collision
4. `CHANGELOG.md` — score corrected to `D:4/B:7/U:8`
5. `harness.yml` — uses `mix npm.ci` (lockfile-frozen)
