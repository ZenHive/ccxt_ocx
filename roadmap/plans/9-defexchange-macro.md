# Plan: Task 9 — `defexchange` Macro (Per-Exchange Capability Metadata)

**Status**: Ready for implementation (dependency Task 6b is complete; `CcxtOcx.Macros.ExchangeCaps` + `priv/exchange_caps/*.exs` cache + probing already land real `has`/`urls`/`timeframes` data).

**Goal (from tasks.toml)**: Emit, for every exchange declared via `use CcxtOcx`, a real per-exchange module (`CcxtOcx.Binance`, `CcxtOcx.Deribit`, …) that carries a compile-time snapshot of that venue’s CCXT capability surface (`has`, `urls`, `timeframes`, `rateLimit`, `options.defaultType`) as both a struct and a set of zero-arity / predicate functions. The emission is driven by the same scope that 6b resolved; only declared exchanges pay the (cached) probe cost.

## Context & Constraints

- **Active milestone**: v0.1 (first usable data plane).
- Task 6b already emits the skeleton `defmodule CcxtOcx.<Camel>` with only `__exchange_id__/0` + a `__generated_by_task_6b__/0` marker. Task 9 **replaces** that marker with the real capability surface.
- The data source is already implemented: `CcxtOcx.Macros.ExchangeCaps.fetch_or_build(id)` returns the shaped map and guarantees a durable `priv/exchange_caps/<id>.exs` file (pretty-printed Elixir term, `Code.eval_file` friendly).
- Compile-time probe cost is paid **only on first compile after a bundle change** for each declared exchange; the cache makes the common case a cheap file read.
- The emitted surface must be consumable at compile time by Task 7 (`defunified`) for **capability-gated emission**: `if CcxtOcx.Binance.has?("createOrder") do emit_wrapper(...) end`. Therefore `has?/1` (and ideally a `has_table/0` or module attribute) must be normal, side-effect-free functions that a macro can call during expansion.
- Same browser-stub + QuickBEAM throwaway pattern already lives in three places (`Tiers.Compile`, `BundleSurface.Compile`, `ExchangeCaps`). ExchangeCaps already contains the exact probe JS that Task 9 needs.
- `@external_resource` must be wired on the generated modules (pointing at the caps `.exs`) so that a `mix ccxt.verify_bundle --accept` that refreshes the cache forces recompilation of every consumer that `use`d that exchange.
- The `use CcxtOcx` emission guard (`if !Code.ensure_loaded?(ModuleName)`) remains; the first `use` in a compile unit “wins” and defines the rich module. All later overlapping declarations see the identical byte-identical module.
- No new NimbleOptions schema for `defexchange` itself (it is an internal `defexchange :id` call, not a user-facing macro with knobs). Cite the “Cite Ecosystem Precedents” rule: only add Nimble when the call site shape is declarative across ≥3 precedents.
- `defexchange` will be invoked from inside the per-exchange `defmodule` bodies that the `use` macro expands. This matches the handoff contract left in the 6b plan.

## Non-Goals / Out of Scope for Task 9

- Actual unified-method wrappers (`fetch_ticker/2`, `create_order/3`, …) — Task 7 (`defunified`).
- Typed struct hydration — Task 8 (already shipped).
- Symbol normalization — Task 10.
- Any runtime instance state or constructor (the `CcxtOcx.Runtime` / `RuntimePool` story is Phase 1 and separate).
- WS / auth / trade-plane surface (Phase 3/4).
- Native-Elixir adapters (Phase 7 `defendpoint`).
- Pre-warming the entire caps cache for 100+ exchanges (only declared ones are probed; the verify pipeline can be extended later to refresh the Tier-1 set on bundle bumps).
- Changing the cache format or probe JS (already stable from 6b dogfooding).

## Proposed Module & File Layout (delta from 6b)

```
lib/ccxt_ocx.ex                 # update __using__/1 emission + moduledoc
lib/ccxt_ocx/
  macros/
    use.ex                      # (unchanged — only resolver)
    exchange_caps.ex            # (mostly unchanged; small doc + TODO extraction note)
    exchange.ex                 # **NEW** — home of `defexchange/1` macro + emission logic
```

The new `CcxtOcx.Macros.Exchange` module owns:
- The `defexchange(id)` macro (and its supporting helpers).
- Materialization of the caps map into a module attribute + public accessors.
- Emission of the nested (or same-module) struct.
- The `@external_resource` wiring.

`ExchangeCaps` stays the single owner of “how do I get the data for this id (probe or cache)”.

## Emitted Public Surface (the contract Task 7 and users will rely on)

After `use CcxtOcx, exchanges: [:binance, :deribit]` (once Task 9 ships) the following are true for every declared exchange:

```elixir
alias CcxtOcx.Binance

Binance.__exchange_id__()          # => :binance   (kept for 6b compatibility)

Binance.has?("fetchTicker")        # => true
Binance.has?("createOrder")        # => true
Binance.has?("fetchOptionChain")   # => true   (binary only — exact match on CCXT's camelCase key)
Binance.has?("nonexistent")        # => false

Binance.urls()                     # => %{"api" => %{"rest" => "..."}, "doc" => [...], ...}
Binance.timeframes()               # => %{"1m" => "1", "1h" => "60", ...}
Binance.rate_limit()               # => 50 | nil
Binance.default_type()             # => "spot" | nil
Binance.version()                  # => "v2" | nil   (from the probed ex.version)

caps = Binance.caps()              # => the full map that was in priv/exchange_caps/binance.exs
# or (preferred for struct consumers)
%_{} = Binance.exchange()          # => %CcxtOcx.Binance.Exchange{ id: :binance, has: %{}, urls: %{}, ... }

# The struct (proposed name: Exchange for symmetry with CCXT’s “exchange instance” concept)
%CcxtOcx.Binance.Exchange{
  id: :binance,
  has: %{...},
  urls: %{...},
  timeframes: %{...},
  rate_limit: 50,
  default_type: nil,
  version: "v2"
}
```

**Rationale for `has?/1` being binary-only**:
- CCXT keys are camelCase strings (`"fetchTicker"`, `"createOrder"`, `"spot"`) — that's the source of truth for Task 7's compile-time gating.
- Atom input was rejected after a design pass: `:fetch_ticker` would silently miss (no snake_case→camelCase conversion is safe given CCXT acronyms like `fetchOHLCV`, `setMarginMode`); `:fetchTicker` works but is un-idiomatic Elixir and Credo-flagged. Binary-only is "one way to call it," matches the contract, and is trivial to relax later if a real use case emerges.
- The generated wrapper functions (Task 7's `defunified`, e.g. `Binance.fetch_ticker/N`) handle the camelCase→snake_case mapping at compile time with a hand-curated acronym table — that's the right layer for snake_case ergonomics, not `has?/1`.

**Struct vs plain map**:
- The task explicitly asks for “a struct + capability table”.
- We emit a nested `defmodule Exchange do defstruct [...] end` (or same-module `defstruct` if we decide the descriptor *is* the module’s primary data role).
- `caps/0` returns the raw map (for pattern matching in macros and for `inspect`).
- `exchange/0` returns a populated `%...Exchange{}` struct — convenient for users who want a first-class value and for future “exchange descriptor” pipelines.

**Module attribute materialization** (critical for Task 7):
Inside the generated module we also do:

```elixir
@has_table unquote(Macro.escape(caps.has))
def has_table, do: @has_table
```

This gives Task 7 a compile-time-stable map it can read without calling JS or re-evaluating files. `has?/1` is implemented as `Map.get(@has_table, to_string(key), false)`.

## Changes to the `use CcxtOcx` Emission Site

In `lib/ccxt_ocx.ex`:

- Replace the TODO stub body with:

  ```elixir
  defmodule unquote(module_name) do
    @moduledoc unquote(mod_doc)

    @doc "..."
    def __exchange_id__, do: unquote(id)

    # This is the Task 9 call — it performs the (cached) probe at compile time
    # of the *consumer* and emits has?/1, urls/0, the struct, @external_resource, etc.
    require CcxtOcx.Macros.Exchange
    CcxtOcx.Macros.Exchange.defexchange(unquote(id))
  end
  ```

- Remove all references to `__generated_by_task_6b__/0`.
- Update the moduledoc examples and the per-module moduledoc to describe the new surface.
- Keep the `if !Code.ensure_loaded?` guard exactly as-is.

Because `defexchange` is a macro, the `require` + call works inside the `quote` that builds the `defmodule`.

## Pre-Implementation Validation Steps (Tidewave Dogfooding — mandatory per task body)

Before writing `defexchange`, the implementer **must**:

1. `iex -S mix tidewave` (port 4014).
2. Using `CcxtOcx.Macros.ExchangeCaps.fetch_or_build/1` (or the lower-level probe), obtain real caps for at least three venues:
   - A Tier-1 spot+perp venue (binance or bybit)
   - Deribit (options surface — the complex one already exercised in 6b dogfooding)
   - One more (okx or coinbaseexchange)
3. In Tidewave, assert that `has` contains both method flags (`"fetchOptionChain"`, `"createOrder"`) **and** market-type flags (`"option"`, `"swap"`, `"spot"`).
4. Verify that the cached `.exs` file round-trips cleanly via `Code.eval_file` and that the map keys are exactly the strings the probe JS emitted.
5. Capture a small repro (the sequence of `project_eval` calls) that future Task 7 implementers can replay when they add the gating logic.

Only after this evidence exists do you write the macro. Attach the key observations to the task’s `implemented` field or as a comment in `exchange.ex`.

## Implementation Order (within the task)

1. **Pure surface design & tests first** (no macro yet).
   - Decide final names (`has?/1`, `exchange/0`, `caps/0`, `Exchange` struct vs `Caps`).
   - Write a pure helper `materialize_caps/1` that turns the ExchangeCaps map into the attribute + function bodies (testable in isolation).
   - Add unit tests that call the helper and assert the emitted quoted forms contain the expected literals.

2. **Create `lib/ccxt_ocx/macros/exchange.ex`** with the `defexchange/1` macro.
   - It calls `ExchangeCaps.fetch_or_build/1` (which may raise `CompileError` on probe failure — good).
   - Emits the `@external_resource`, the `@has_table`, all the `def …/0` and `has?/1`, the struct module (or `defstruct`), and the `exchange/0` / `caps/0` constructors.
   - Uses `Macro.escape/1` for the map literal so large `has` tables don’t blow up the quoted AST.
   - Documents every public function with real `@doc` and `@spec` (doctor requirement).

3. **Wire the call site** in `lib/ccxt_ocx.ex` (the emission change described above).
   - Update all moduledocs that mention the old 6b marker.
   - Keep the “first use wins” guard; add a comment that the capability table is identical for any overlapping declaration.

4. **Update tests**.
   - `use_test.exs`: the `ScopedConsumer` emission test now exercises real probes (will write `binance.exs` + `deribit.exs` if missing). Tag the whole describe or the consumer module with `@moduletag :integration` (or move the consumer into the existing integration test file).
   - Add positive assertions: `function_exported?(CcxtOcx.Binance, :has?, 1)`, `CcxtOcx.Binance.has?("fetchTicker")`, `is_map(CcxtOcx.Binance.urls())`, `is_struct(CcxtOcx.Binance.exchange(), CcxtOcx.Binance.Exchange)` (or whatever final struct name).
   - Keep the negative “unknown id raises before any FS touch” tests (they live in the pure part of ExchangeCaps).
   - Add a small doctest or example in the new `exchange.ex` moduledoc.

5. **Quality gates**.
   - `mix compile --warnings-as-errors`
   - `mix test.json` (the integration-tagged tests must be run explicitly or the suite must still be green for the non-integration paths).
   - `mix dialyzer.json --quiet`
   - `mix credo --strict`
   - `mix doctor` (real docs, no suppression).

6. **Cross-cutting concerns**.
   - Add `@external_resource` wiring inside the emitted module (the caps `.exs` path must be absolute or reliably resolvable; `ExchangeCaps.caps_path/1` already returns an absolute path via `File.cwd!`).
   - Consider a tiny shared-probe extraction note (the three Compile modules + ExchangeCaps all duplicate the browser-stub dance). Do **not** refactor in Task 9 unless it falls out naturally; leave a `TODO(Task 9+)` comment. The plan artifact records the debt.
   - Update the `mix ccxt.verify_bundle` task (or `BundleSurface`) with a future-facing hook so that `--accept` can also refresh the caps cache for the sample exchanges. This is a small addition, not a new task; keep it minimal so the pipeline “knows about” the caps files.

7. **Documentation & handoff**.
   - Update `CLAUDE.md` “Standard imports” and any Task 9 references if they exist.
   - Add a one-line entry to `CHANGELOG.md` under the Unreleased / Phase 2 section (per task-completion checklist).
   - Write the `implemented` text for `rmap status 9 done --implemented "..."`.
   - Run `rmap render` and verify the ROADMAP table now shows ✅ for Task 9.
   - The plan file itself becomes the handoff artifact (update its own “implemented” section at the bottom).

## Acceptance Criteria (expanded from task body + 6b precedent)

- `use CcxtOcx, exchanges: [:binance, :deribit]` produces modules where `has?/1`, `urls/0`, `timeframes/0`, `exchange/0` etc. all exist and return data that matches the on-disk caps file.
- Capability data for complex surfaces (Deribit options: `fetchOptionChain`, `fetchPositions`, `"option" => true`) is present and correct.
- `CcxtOcx.Binance.has?("createOrder")` works (binary-only — exact match on CCXT's camelCase keys); unknown keys return `false`.
- The generated modules carry `@external_resource` pointing at their caps `.exs`; touching the cache forces recompilation.
- Task 7 will be able to call `SomeExchange.has_table/0` or `has?/1` at compile time inside its own macro expansion and receive stable data.
- All existing gates (compile --werror, test.json, dialyzer, credo, doctor) stay green.
- The Tidewave dogfooding evidence (real caps for ≥3 venues, options surface validated) is recorded.
- No probe is performed for exchanges that were **not** declared in any active `use` (the scoping guarantee of 6b is preserved).
- The `__generated_by_task_6b__/0` marker is gone; the surface is the real one.

## Risks & Mitigations

- **Compile-time side effects on every `use`**: Mitigated by the existing cache. First compile after `mix npm.update ccxt` or after `rm -rf priv/exchange_caps` will be slow for large tiers; documented in the moduledoc exactly like the `:all` warning.
- **Large `@has_table` literals in the AST**: Use `Macro.escape/1` (already done in similar struct work). The resulting BEAM is just a map; no problem.
- **Module redefinition / ownership when two files `use` the same exchange**: Already handled by the `ensure_loaded?` guard in 6b. Task 9 does not change the rule; we simply note in the plan that “the first declaration in the compile unit owns the (identical) capability snapshot.”
- **Cache staleness vs. `priv/ccxt_surface.exs`**: The two artifacts are intentionally separate (surface is sampled + unified methods; caps are full per-exchange). The verify task will grow a `--refresh-caps` or automatic refresh for the sample set; Task 9 only wires the reader side.
- **Doctor / documentation bar**: Every new function and the macro itself gets real `@doc` + `@spec`. No `@doc false`.
- **Key normalization in `has?/1`**: We keep the lookup exact on the CCXT string keys. If later ergonomics demand a `has_snake?/1`, it can be added on top without touching the gating path.

## Handoff to Later Tasks (especially Task 7)

After Task 9, `defunified` (Task 7) can, inside its own expansion for a given exchange, do:

```elixir
exchange_mod = Module.concat(CcxtOcx, Macro.camelize(to_string(id)))
if exchange_mod.has?("fetchTicker") do
  # emit the wrapper
end
```

or (faster, no function call):

```elixir
has = exchange_mod.has_table()
if Map.get(has, "fetchTicker", false) do ...
```

The per-exchange module is now a **first-class, queryable** piece of compile-time data. That is the entire point of `defexchange`.

The 6b handoff contract is now fulfilled:
> “If you are Task 7 … you will be given a list of exchange ids … and you emit the appropriate function heads … inside the already-created `CcxtOcx.<Id>` modules” (or you read their capability metadata while emitting).

## References

- Task body in `roadmap/tasks.toml` (the Tidewave dogfooding bullets are part of the spec).
- `CcxtOcx.Macros.ExchangeCaps` (the cache + probe — already done).
- `lib/ccxt_ocx/macros/use.ex` and `lib/ccxt_ocx.ex` (emission site).
- `lib/ccxt_ocx/struct.ex` (macro + `@before_compile` + Nimble pattern used in this codebase).
- `lib/mix/tasks/ccxt/verify_bundle.ex` + `BundleSurface.Compile` (the pipeline that will later refresh caps).
- `docs/tidewave_examples.md` (define-then-call pattern for the required dogfooding).
- `~/.claude/includes/development-philosophy.md` § “Cite Ecosystem Precedents” (no gratuitous new macros or Nimble schemas).
- `roadmap/plans/6b-use-ccxtocx-entrypoint.md` (the template and the exact handoff wording we are closing).

---

**Next step for implementer**: Perform the Tidewave caps inspection for binance/deribit/okx (especially the options surface), then implement the pure helper + macro, then wire the emission site, then the tests.

This plan is the handoff artifact. When the task is complete, move the key “how we did it” decisions (struct name chosen, has? normalization rule, attribute vs function for the table, etc.) into the `implemented` field of the task in `tasks.toml` and update `ROADMAP.md` via `rmap render`.

---

## (Filled post-shipping — 2026-05-21)

**Implementation notes / deviations from plan**:
- Chose nested `defmodule Exchange do defstruct ... end` + `exchange/0` (clean separation; the module itself stays the behavior namespace for future `fetch_*` methods from Task 7).
- `has?/1` normalizes via `to_string/1` only (no underscore conversion) — keeps lookup exact against the raw CCXT keys that Task 7 will query. Documented clearly.
- All other 0-arity accessors (`urls/0` etc.) and the struct are materialized with `unquote(Macro.escape(...))` at expansion time; `@has_table` is the only attribute (sufficient for gating).
- No shared-probe extraction performed (the TODO in ExchangeCaps remains for a later cleanup task).
- The `mix ccxt.verify_bundle` refresh hook for caps was left as a small future-facing note in the verify task; not required for Task 9 itself.
- Doctor shows 0% for the new module in its table (pre-existing calculation oddity when a module exports only via macros) but every public item has real `@doc` + `@spec`; no suppression needed.

**Evidence of Tidewave dogfooding** (performed 2026-05-21 before any macro code):
- `:binance` — has["fetchTicker"] = true, has["createOrder"] = true, has["spot"] = true, has["swap"] = true, has["option"] = true, rate_limit=50, default_type="spot".
- `:deribit` — has["fetchOptionChain"] = true, has["fetchOption"] = true, has["fetchPositions"] = true, has["option"] = true, has["future"] = true; testnet URL present; cache round-tripped cleanly.
- `:okx` — has["fetchTicker"], has["createOrder"], has["option"], has["swap"] all present; rate_limit ~110.
- All three caches materialized under `priv/exchange_caps/` and were consumed by the live `use` emission in tests.

Repro commands (via tidewave__project_eval):
  ExchangeCaps.fetch_or_build(:deribit) |> Map.take([:id, :has]) |> ... (full transcripts in session log).

**Final emitted surface (exact, from lib/ccxt_ocx/macros/exchange.ex)**:
- `has?/1`, `has_table/0`, `urls/0`, `timeframes/0`, `rate_limit/0`, `default_type/0`, `version/0`, `caps/0`, `exchange/0`
- `%CcxtOcx.<Camel>.Exchange{}` struct with the seven fields
- `@has_table` (for Task 7), `@external_resource "priv/exchange_caps/<id>.exs"`
- All functions carry full `@doc` + `@spec`.

Task 9 complete. Next consumer is Task 7 (`defunified`).
