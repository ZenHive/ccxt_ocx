---
sha: 2d54289
short_sha: 2d54289
audited_at: 2026-05-17
auditor_model: claude-opus-4-7
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: feat: Bundle-bump verification pipeline (Task 5b) (#5)

**Original commit:** `2d54289` — merge of PR #5
**Author:** E.FU
**Files touched:** ~15
**LOC:** +1486 (production + test + manifest + harness)

## Findings

| #  | Pri | Category          | File:Line                                         | Description                                                                                                                                                                                          | Resolution |
|----|-----|-------------------|---------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------|
| A1 | 6   | abstraction       | `lib/ccxt_ocx/bundle_surface/compile.ex:170-181`  | `public_unified_method?/1` prefix heuristic admits 8 internal CCXT helpers (`fetch2`, `fetchPaginatedCall{Cursor,Deterministic,Dynamic,Incremental}`, `fetchPartialBalance`, `fetchWebEndpoint`, `createSafeDictionary`) into the manifest; Codex's dialogue identified a 9th (`loadMarketsHelper`) | Applied: `@additional_denied` exact-name denylist (9 entries) + manifest regen (261→252) + negative-assertion test in `bundle_surface_test.exs` |
| A3 | 4   | extraction        | `lib/ccxt_ocx/bundle_surface/compile.ex` (timeouts) | `60_000` hardcoded in `probe_has_tables/1`; inconsistent with `@load_timeout` style elsewhere                                                                                                       | Applied: extracted `@per_exchange_timeout to_timeout(minute: 1)` module attribute |
| A4 | 4   | extraction        | `lib/ccxt_ocx/bundle_surface/compile.ex` (filter lists) | `verb_prefixes` and `internal_prefixes` defined as inline literals inside `public_unified_method?/1`; harder to extend                                                                              | Applied: extracted `@verb_prefixes` and `@internal_prefixes` module attributes; predicate now references them |
| A5 | 4   | doc-gap           | `ROADMAP.md` Current Focus                        | Stale prose: "Phase 1: Foundation… Next: pool it (Task 3), normalize JS errors (Task 4), and smoke-test (Task 5)" — all three done by 2d54289                                                       | Applied: replaced with "Phase 1 complete" prose + Phase 2 pointer; rendered from `tasks.toml` after flipping `[phases.1].status = "done"` |
| A6 | 3   | doc-gap           | `CLAUDE.md` macro surface section                 | Said "Task 1 `CcxtOcx.Runtime` is the only landed Phase 2 piece" — Runtime is Phase 1, not Phase 2                                                                                                  | Applied: rewrote to list Phase 1 foundation modules accurately |
| A7 | 3   | doc-gap           | `.github/workflows/harness.yml:18-24`              | Comment said "no tagged tests yet; exclude is a no-op" but lines 109-119 now `--include integration` (CI runs them)                                                                                  | Applied: comment now describes the actual include/exclude behavior |

## Auto-applied fixes

- **`lib/ccxt_ocx/bundle_surface/compile.ex` extractions** — Three new module attributes (`@per_exchange_timeout`, `@verb_prefixes`, `@internal_prefixes`) plus the new `@additional_denied` denylist. `public_unified_method?/1` now references all four. `probe_has_tables/1` uses `@per_exchange_timeout` instead of `60_000`. Net LOC ~+25 (mostly the denylist's documenting comment).
- **`priv/ccxt_surface.exs` regenerated** via `mix ccxt.verify_bundle --accept`. 9 internal helpers removed; manifest count 261 → 252.
- **`test/ccxt_ocx/bundle_surface_test.exs`** — Added "unified_methods/0 excludes CCXT base-class internal helpers" test that `refute name in methods` for each of the 9 denied names. Closes the regression-guard gap Codex called out (existing tests only used `> 50` lower-bound checks).
- **`.sobelow-skips`** rebuilt from a clean baseline to match the new line numbers (`compile.ex:121` and `:165`, was `:91` and `:135`); also picked up `runtime.ex:288` drift from `:234`. 7 fingerprints total, no stale entries.

## Discuss-tier resolutions

**A1 (manifest pollution) — discuss-design, resolved via Claude+Codex dialogue:**

- **Claude position:** add `@additional_denied` denylist (8 names) + regen + update count assertion.
- **Codex independent resolution:** ⚠️ AGREE-WITH-AMENDMENT — same mechanism, but also deny `loadMarketsHelper` (cited line 80 of pre-regen manifest, line 337 of `Exchange.d.ts`); count goes 261 → 252 (not 253); no exact count assertion exists in the test file (it uses `> 50`), so add explicit negative-assertion test rather than chasing a nonexistent count.
- **Convergence:** both agree on the denylist mechanism over regex / structural / deferred alternatives. Codex's amendments accepted in full. Applied via auto-fix path.

## Codex second-opinion

Status: **dual-reviewer** (full audit dispatched in parallel + dedicated dialogue for A1).

Corroborated findings: A1 (with amendment).
Codex-only findings (verified): `loadMarketsHelper` should be denied alongside the 8 Claude named.
Codex-only findings (discarded as over-flag): One Codex flag claimed `:telemetry.span/3` "drops start metadata" — verified against `telemetry` docs (start metadata is merged into stop_metadata), discarded.

Claude-only findings (discarded as over-flag): A finding on `exchange_dts_path/0` using `File.cwd!()` flagged by Explore — false positive; this is a verifier-only code path (`mix ccxt.verify_bundle`), not a runtime path, and the verifier is meant to run from project root.

## Acceptance criteria cross-reference

Task 5b acceptance criteria (from `roadmap/tasks.toml`):

- ✅ `priv/ccxt_surface.exs` committed manifest (snapshot of unified methods + sampled `has`)
- ✅ `mix ccxt.verify_bundle` mix task; `--accept` writes a new baseline
- ✅ CI harness gate runs `mix ccxt.verify_bundle` (`harness.yml:85-86`)
- ✅ Diff output shows added / removed methods on drift
- ✅ Tests cover the diff engine (`bundle_surface_test.exs`, ≥12 passing)
- ✅ Bundle path resolution honors `Application.get_env(:ccxt_ocx, :bundle_path, ...)`

## Notes for future drift audits

- The denylist is a working short-term mechanism. When Phase 2's `defunified` macro lands (Task 7), the canonical filter should move to `.d.ts` `@param` analysis or per-method `@doc`/`@spec` source-of-truth derivation — at which point `@additional_denied` should be revisited and likely retired. File under Phase 2 work, not a separate task.
- CCXT version bumps may introduce new base-class helpers that match `@verb_prefixes` and don't match `@internal_prefixes`. The harness gate will fail-loud with an "Added methods" diff; reviewer adds names to `@additional_denied` and regens. The negative-assertion test will then need extending in lockstep.
