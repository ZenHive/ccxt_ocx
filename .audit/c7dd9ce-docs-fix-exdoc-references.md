---
sha: c7dd9ce7a936da11caa07c321ae954b6a5937dd4
short_sha: c7dd9ce
audited_at: 2026-05-18
auditor_model: claude-opus-4-7
verdict: clean
codex_status: not-dispatched
audited_by: audit-review v1
---

# Audit: docs: fix ExDoc references to hidden __using__/1 and method_term type

**Original commit:** c7dd9ce — `docs: fix ExDoc references to hidden __using__/1 and method_term type`
**Author:** E.FU
**Files touched:** 2 (lib/ccxt_ocx/declarations.ex, lib/ccxt_ocx/macros/use.ex)
**LOC:** ±4

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| — | —  | (none)   | —         | Pure ExDoc cross-reference repair; uses correct `t:` type-ref syntax and removes pointer to undocumented `__using__/1`. | n/a |

## Auto-applied fixes

- (none)

## Discuss-tier resolutions

- (none)

## Codex second-opinion

Status: not-dispatched (small non-tiny commit, doc-only repair — single-reviewer pass)
Corroborated findings: —
Codex-only findings (verified): —
Codex-only findings (discarded as over-flag): —
