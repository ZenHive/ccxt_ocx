---
sha: 8b9dfadc56d606ddaa9fb8ebd16170fceb93327e
short_sha: 8b9dfad
audited_at: 2026-05-17
auditor_model: claude-opus-4-7
verdict: clean — ceremony-tier
codex_status: skipped — docs-only (0 lib/ files)
audited_by: audit-review v1
---

# Audit: docs: add Tidewave examples (Task 20) + references + roadmap render

**Original commit:** `8b9dfad`
**Author:** E.FU
**Files touched:** 6 (`CLAUDE.md`, `README.md`, `ROADMAP.md`, `docs/tidewave_examples.md` (new), `roadmap/data.json`, `roadmap/tasks.toml`)
**LOC:** +229 / −13

## Classification

Ceremony-tier per `agent-pr-review.md` § "Review Tiering" — docs-only commit, 0 `lib/` files. The 229 LOC delta is dominated by the new `docs/tidewave_examples.md` reference document.

## Findings

None — the document is internally consistent and matches the patterns used in the underlying `CcxtOcx.Runtime` API (verified `Runtime.eval/2`, `Runtime.call/3`, and the `mcp__tidewave__project_eval` examples reference real public function signatures on `lib/ccxt_ocx/runtime.ex`).

## Notes

- Task 20 marked `in_progress` (not `done`) in `tasks.toml` despite the file being added — intentional per the body's evergreen framing ("These examples are maintained from actual Tidewave sessions and will evolve into the usage patterns for the generated macros"). The doc is a living reference, not a one-shot deliverable.
- `rmap` schema note: `in_progress` typically requires a `branch` field. Task 20 has none. Either tasks.toml should record the branch where the work continues, or the status would more accurately be `pending` (since the file landed and no future-work branch exists). Surfaced for the next session — not auto-applied (low priority, single-developer signal).
