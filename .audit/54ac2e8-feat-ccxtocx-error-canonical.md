---
sha: 54ac2e8daab9296179e1461fce5845fac455fd1c
short_sha: 54ac2e8
audited_at: 2026-05-17
auditor_model: claude-opus-4-7
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: feat: CcxtOcx.Error — canonical 9-tag taxonomy + JS normalization (Task 4) (#4)

**Original commit:** `54ac2e8` — merge of PR #4
**Author:** E.FU
**Files touched:** 8
**LOC:** +4880 / −12 (AGENTS.md regen accounts for ~4020; production-code delta is +447 lib + +380 test + +6 runtime.ex comment tweak)

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 4   | bug      | lib/ccxt_ocx/error.ex:312 | `from_js_error/2` JSError clause doesn't defensively coerce non-binary `:name` (asymmetric with map clause) | Applied: guard + `safe_name` coercion |
| 2 | 5   | doc-gap  | lib/ccxt_ocx/error.ex:71-77  | Moduledoc cites old `@external_resource` path (`ccxt/...` vs actual `node_modules/ccxt/...`) and old `export class XxxError` syntax (actual: `declare class Foo extends Bar`) | Applied: moduledoc rewritten to match the live gate |

## Auto-applied fixes

- **`lib/ccxt_ocx/error.ex:312`** — Wrapped `tag_for_ccxt_class/1` call in `safe_name = if is_binary(name), do: name, else: "Error"`. The `QuickBEAM.JSError` struct pins `name: String.t()` and its only constructor (`from_js_value/1`) force-coerces via `to_string/1`, so this is unreachable through QuickBEAM's own API surface. The fix preserves the commit-body-stated defensive symmetry ("Coerce any non-binary value to the 'Error' sentinel") that the map clause already implements — a hand-built `%QuickBEAM.JSError{name: :foo}` bypassing the constructor previously raised `FunctionClauseError` on `tag_for_ccxt_class/1`'s `is_binary` guard; now lands on `:unknown` like the map path. 2-line change, no public surface, contract-preserving.

- **`lib/ccxt_ocx/error.ex:71-77`** — Rewrote the "Compile-time drift gate" section of the moduledoc to cite (a) the actual `@external_resource "node_modules/ccxt/js/src/base/errors.d.ts"` path (was `ccxt/js/src/base/errors.d.ts`, missed the npm-install prefix), (b) the actual regex shape `declare class Foo extends Bar` (was `export class XxxError`, predated the B1/B2 fix). The drift gate behavior itself is unchanged; the moduledoc was lying about it.

## Discuss-tier resolutions

- (none)

## Codex second-opinion

Status: **dual-reviewer**
Corroborated findings: —
Codex-only findings (verified): 1, 2 — both real (verified against `node_modules/ccxt/js/src/base/errors.d.ts` and `deps/quickbeam/lib/quickbeam/js_error.ex`)
Codex-only findings (discarded as over-flag): —

Codex pre-flight verification: parsed `errors.d.ts` (41 classes), confirmed `@ccxt_to_tag` has no missing upstream classes, confirmed the 7 B1/B2-fix classes (AccountNotEnabled, ManualInteractionNeeded, RestrictedLocation, ContractUnavailable, ExchangeClosedByUser, ChecksumError, UnsubscribeError) are present and mapped, confirmed map values stay within the closed 9-tag set. Could not run `mix test` / `mix format` in its sandbox (Mix `:eperm` on PubSub socket).

## Acceptance criteria cross-reference

PR #4 / Task 4 acceptance criteria (from `roadmap/tasks.toml`):
- ✅ Closed 9-tag taxonomy implemented (`tags/0` returns exactly 9 atoms; verified `length(tags) == 9` test passes)
- ✅ `%CcxtOcx.Error{}` struct with enforced `:tag`, `:source`, `:source_name` + optional `:exchange`, `:method`, `:original`, `:meta`
- ✅ Three-function API (`tag_for_ccxt_class/1`, `from_js_error/2`, `normalize/2`)
- ✅ Compile-time drift gate via `@external_resource` (verified gate would fail on unmapped class; B1/B2 fix proved the gate fires)
- ✅ Full `Exception` behaviour (`raise`, `Exception.message/1`, `rescue`)
- ✅ Real CCXT error tests via QuickBEAM runtime
- ✅ ROADMAP marks Task 4 ✅; CHANGELOG entry present
- ✅ Source discriminator (`:source` / `:source_name`) future-proofs Phase 7

## Notes for future drift audits

- The reverse-direction drift check is NOT implemented — entries in `@ccxt_to_tag` that don't correspond to any class in `errors.d.ts` (currently: `ExchangeClosed`, `FailedRequest`, `OperationNotAllowed`) would not fail the gate. These three are harmless forward-compat placeholders today; if a future audit picks "tighten the gate to bi-directional" as a design call, file under `defunified` work in Phase 2.
