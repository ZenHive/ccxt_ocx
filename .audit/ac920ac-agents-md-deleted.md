---
sha: ac920ac61da883472350dc81f1480bfebdc730b6
short_sha: ac920ac
audited_at: 2026-05-17
auditor_model: claude-opus-4-7
verdict: clean — fast-path
codex_status: not-dispatched
audited_by: audit-review v1
---

# Audit: agents md deleted

**Reason for fast-path:** no production-code paths touched (single-file deletion of auto-generated `AGENTS.md`; immediately re-synced in the next commit `54ac2e8` from `CLAUDE.md` via `scripts/sync-agents-md.sh`). Net effect across the audit range is the regenerated file present at HEAD.
**Files touched:** AGENTS.md
