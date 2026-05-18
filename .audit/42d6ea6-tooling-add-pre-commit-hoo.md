---
sha: 42d6ea6c8e82b120abca41f8d5d88a0abc603b13
short_sha: 42d6ea6
audited_at: 2026-05-18
auditor_model: claude-opus-4-7
verdict: clean — fast-path
codex_status: not-dispatched
audited_by: audit-review v1
---

# Audit: tooling: add pre-commit hook for fast harness checks

**Reason for fast-path:** 41 LOC, no production-code paths touched (introduces `.githooks/pre-commit` and docs).
**Files touched:** .githooks/pre-commit, CLAUDE.md (or similar tooling docs)
