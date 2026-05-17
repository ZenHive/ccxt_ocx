# ccxt_ocx Roadmap

**Vision:** A macro-first Elixir wrapper around CCXT that runs the JS bundle inside QuickBEAM, with per-exchange/per-method wrappers — REST and WS, data plane *and* trade plane — generated at compile time from CCXT's own type definitions. 100+ exchanges *available*; the user declares which ones they actually want compiled into their app.

**Scope:**

- **Full unified CCXT surface** — REST + WS, public + private, including `createOrder`, `cancelOrder`, `fetchBalance`, `setLeverage`, `watchMyTrades`, `watchBalance`. No carve-outs based on hypothetical risk.
- **User-scoped compile-time generation.** `use CcxtOcx, exchanges: [...]` (or `tier:` or `:all`) gates which per-exchange modules get emitted. Generating all 100+ by default would add 30–60s+ compile time, 5–10MB of beam, and pollute `mix docs` for the 95% of users who only touch 1–5 venues. Phoenix.Router precedent: routes only exist when declared.
- **Verification-first for the trade plane:** before signing against mainnet, run testnet harnesses (Binance, Deribit, OKX) and compare signed payloads byte-for-byte against known-good signers where one exists. Narrow scope *only* when concrete evidence of instability surfaces — not preemptively.
- **Recommended deployment shape:** the QuickBEAM pool runs in a dedicated OTP release / supervision tree so a NIF panic is isolated from anything else. This is a deployment recommendation, not a scope cut.
- **Long-term direction is native Elixir for the venues that matter.** CCXT-via-QuickBEAM is the bootstrap and the permanent fallback for the long tail (~95 exchanges). Phase 7 native ports are committed for 3–5 high-value venues, not hypothetical. The macro-generated public API in Phase 2 is the contract; the JS path stays alive forever as the conformance oracle that validates each native port.

**Completed work:** See [CHANGELOG.md](CHANGELOG.md).

**Task tracking:** This file is rendered by `rmap` from `roadmap/tasks.toml`. Don't hand-edit the task tables inside `<!-- TASKS:BEGIN -->` / `<!-- TASKS:END -->` marker pairs — they're regenerated on every `rmap render`. Edit `roadmap/tasks.toml` or use `rmap status` / `rmap mark` / `rmap new`. Prose outside the marker pairs is byte-preserved.

---

## 🎯 Current Focus

**Phase 1 complete.** The runtime lifecycle + supervision foundation is in place: `CcxtOcx.Runtime`, `RuntimePool`, `Error`, `Tiers`, `BundleSurface` (+ `mix ccxt.verify_bundle`), and `Telemetry` (Task 14, the first Phase 5 deliverable shipped in lockstep). Phase 2 (macro-driven method generation) is next; see the focus line below.

<!-- FOCUS:BEGIN -->
**Focus phase:** 1 — Foundation — Runtime Lifecycle (7 of 7 done · 0 in progress)

**Last shipped:** no recent shipments

**Up next:** Task N8 — CCXT-drift policy [D:3/B:7/U:6 → Eff:2.17] 🎯
<!-- FOCUS:END -->

---

## Phase 1: Foundation — Runtime Lifecycle ⬜

> Without this, every other phase is blocked. Goal: a supervised QuickBEAM runtime that loads ccxt once, exposes a stable handle, and survives transient JS errors.

<!-- TASKS:BEGIN phase=1 -->
> 7 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-1-foundation-runtime-lifecycle).
<!-- TASKS:END -->

---

## Phase 2: Macro-Driven Method Generation ⬜

> The leverage point. Don't hand-write `fetch_ticker/2`, `fetch_order_book/3`, `fetch_ohlcv/4`. Generate them from CCXT's own surface.
>
> **Parallel track with Phase 7's N0/N1.** Long-term direction is native, so Tasks 6 (parse `.d.ts`) and 8 (typed structs) feed both pipelines. `defunified` (JS-backed) and `defendpoint` (native, Task N0) sit on top of the same compile-time data structure — build them as one effort to avoid parsing the same TypeScript twice and to keep the unified-method surface and the native-adapter surface in lockstep.

<!-- TASKS:BEGIN phase=2 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 6 | ✅ | 🎁 **macros** · 🚀 **v0_1** · Discover and parse CCXT declaration sources with OXC [D:6/B:8/U:8 → Eff:1.33] 📋 |
| Task 6b | ⬜ | 🎁 **macros** · 🚀 **v0_1** · `use CcxtOcx` — exchange-scope entrypoint [D:5/B:9/U:9 → Eff:1.8] 🚀 |
| Task 7 | ⬜ | 🎁 **macros** · 🚀 **v0_1** · `defunified` macro [D:7/B:10/U:9 → Eff:1.36] 📋 |
| Task 8 | ⬜ | 🎁 **macros** · 🚀 **v0_1** · Typed structs for unified return shapes (with declarative field mapping) [D:5/B:8/U:8 → Eff:1.6] 🚀 |
| Task 9 | ⬜ | 🎁 **macros** · 🚀 **v0_1** · `defexchange` macro [D:6/B:7/U:6 → Eff:1.08] 📋 |
| Task 10 | ⬜ | 🎁 **macros** · Symbol normalization layer [D:6/B:6/U:5 → Eff:0.92] ⚠️ |
<!-- TASKS:END -->

---

## Phase 3: Streaming (CCXT Pro) ⬜

> WS verified working in this session. Surface it as something usable from a Phoenix app or a GenStage pipeline.

<!-- TASKS:BEGIN phase=3 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 11 | ⬜ | 🎁 **streaming** · 🚀 **v1_0** · `defstreaming` macro [D:7/B:9/U:8 → Eff:1.21] 📋 |
| Task 12 | ⬜ | 🎁 **streaming** · 🚀 **v1_0** · `CcxtOcx.Stream` GenStage producer [D:6/B:7/U:6 → Eff:1.08] 📋 |
| Task 13 | ⬜ | 🎁 **streaming** · 🚀 **v1_0** · Reconnect / heartbeat policy [D:6/B:8/U:7 → Eff:1.25] 📋 |
<!-- TASKS:END -->

---

## Phase 4: Trade-Plane Verification ⬜

> Trade-plane methods are macro-generated alongside data-plane methods in Phase 2. This phase **verifies** that signed/authenticated calls actually work end-to-end before anyone routes real money through them.

<!-- TASKS:BEGIN phase=4 -->
| Task | Status | Notes |
|------|--------|-------|
| Task T1 | ⬜ | 🎁 **trade-verify** · 🚀 **v1_0** · Testnet harness — Binance USDT-M futures [D:5/B:9/U:8 → Eff:1.7] 🚀 |
| Task T2 | ⬜ | 🎁 **trade-verify** · 🚀 **v1_0** · Testnet harness — Deribit options [D:5/B:8/U:7 → Eff:1.5] 🚀 |
| Task T3 | ⬜ | 🎁 **trade-verify** · Testnet harness — OKX [D:5/B:7/U:6 → Eff:1.3] 📋 |
| Task T4 | ⬜ | 🎁 **trade-verify** · 🚀 **v1_0** · Signed-payload byte-comparison harness [D:7/B:9/U:8 → Eff:1.21] 📋 |
| Task T5 | ⬜ | 🎁 **trade-verify** · 🚀 **v1_0** · WS authenticated streams (`watchBalance`, `watchMyTrades`, `watchOrders`) [D:6/B:8/U:7 → Eff:1.25] 📋 |
| Task T6 | ⬜ | 🎁 **trade-verify** · 🚀 **v1_0** · Document the actual stability surface [D:2/B:6/U:7 → Eff:3.25] 🎯 |
<!-- TASKS:END -->

---

## Phase 5: Production Hardening ⬜

<!-- TASKS:BEGIN phase=5 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 14 | ✅ | 🎁 **production** · Telemetry events [D:3/B:7/U:7 → Eff:2.33] 🎯 |
| Task 15 | ⬜ | 🎁 **production** · 🚀 **v1_0** · Memory monitoring + restart policy [D:5/B:8/U:7 → Eff:1.5] 🚀 |
| Task 16 | ⬜ | 🎁 **production** · ApiToolkit integration [D:4/B:6/U:6 → Eff:1.5] 🚀 |
| Task 16b | ⬜ | 🎁 **production** · 🚀 **v1_0** · Hoist rate-limit + nonce state into Elixir [D:7/B:9/U:8 → Eff:1.21] 📋 |
| Task 17 | ⬜ | 🎁 **production** · Sandboxed deployment shape [D:5/B:8/U:5 → Eff:1.3] 📋 |
| Task 21 | ✅ | 🎁 **production** · PromEx plugin (`CcxtOcx.PromEx.Plugin`) [D:3/B:7/U:7 → Eff:2.33] 🎯 |
<!-- TASKS:END -->

---

## Phase 6: DX and Docs ⬜

<!-- TASKS:BEGIN phase=6 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 18 | ⬜ | 🎁 **dx** · ex_doc + llms.txt [D:2/B:5/U:5 → Eff:2.5] 🎯 |
| Task 19 | ⬜ | 🎁 **dx** · Descripex annotations on the public API [D:3/B:5/U:4 → Eff:1.5] 🚀 |
| Task 20 | 🔄 | 🎁 **dx** · Tidewave examples [D:2/B:4/U:5 → Eff:2.25] 🎯 |
<!-- TASKS:END -->

---

## Phase 7: Native-Elixir Migration ⬜

> **Committed direction for the 3–5 venues that matter.** Long-term we move signed and hot-path methods to native Elixir for those venues. The JS bundle stays alive as the permanent fallback for the long tail (~95 exchanges) *and* as the permanent conformance oracle that validates the native port against CCXT's view of each venue's API. We never delete the JS path — it's how we catch venue API changes that CCXT's maintainers see before we do.
>
> Migration is exchange-by-exchange and method-family-by-method-family. The macro-generated public API (Phase 2) is the *contract* and never changes; only the adapter behind the dispatch swaps from `:js` to `:native`.
>
> **Build order:** N0 + N1 in parallel with Phase 2 (shared `.d.ts` parse, shared typed structs). N2 + N3 land before any native ship. Per-exchange ports (N4–N7) gated on N3 conformance + T4 byte-equality.

<!-- TASKS:BEGIN phase=7 -->
| Task | Status | Notes |
|------|--------|-------|
| Task N0 | ⬜ | 🎁 **native** · `defendpoint` macro + CCXT-JS source extractor [D:7/B:9/U:8 → Eff:1.21] 📋 |
| Task N1 | ⬜ | 🎁 **native** · `CcxtOcx.Adapter` behaviours [D:5/B:7/U:7 → Eff:1.4] 📋 |
| Task N2 | ⬜ | 🎁 **native** · Routing layer [D:3/B:6/U:7 → Eff:2.17] 🎯 |
| Task N3 | ⬜ | 🎁 **native** · Conformance harness [D:6/B:9/U:9 → Eff:1.5] 🚀 |
| Task N4 | ⬜ | 🎁 **native** · Native Binance — REST public [D:5/B:8/U:6 → Eff:1.4] 📋 |
| Task N5 | ⬜ | 🎁 **native** · Native Binance — WS public [D:7/B:8/U:6 → Eff:1.0] 📋 |
| Task N6 | ⬜ | 🎁 **native** · Native Binance — REST private (signed) [D:8/B:9/U:7 → Eff:1.0] 📋 |
| Task N7 | ⬜ | 🎁 **native** · Replicate to remaining Tier 1 venues [D:8/B:8/U:6 → Eff:0.88] ⚠️ |
| Task N8 | ⬜ | 🎁 **native** · CCXT-drift policy [D:3/B:7/U:6 → Eff:2.17] 🎯 |
<!-- TASKS:END -->

---

## Risk Register (track but don't act on yet)

- **Bundle vs ESM entry**: this session used `dist/ccxt.browser.min.js` (5.4MB webpack bundle). The package's `import` entry `js/ccxt.js` is unbundled ESM and may behave differently — possibly smaller per-runtime memory if QuickBEAM can resolve the imports. Worth a one-off comparison before Phase 2 lands.
- **`self.ccxt.exchanges` is an Object, not an Array** in this bundle, but `self.ccxt.default.exchanges` is the Array. Pick one, document in `CcxtOcx.Runtime`, and don't drift.
- **Per-exchange pro WS endpoint quirks**: not every exchange in CCXT pro has been verified to work under Mint-backed WebSocket. Phase 3 should test a representative spread (Binance ✅, Kraken, OKX, Bybit, Coinbase) before claiming broad support.
- **Compile-time bundle eval (Task 9)**: spinning a QuickBEAM runtime *during compilation* is unusual. CI environments without precompiled NIFs may struggle. Mitigation now baked into Task 9: cache introspection output to `priv/exchange_caps/<id>.exs`, regenerate on bundle bumps. Compile only re-boots runtimes when cache is missing.
- **`use CcxtOcx` default-policy decision (Task 6b)**: see the open question in Task 6b. Must be resolved before Task 7 lands so the macro contract is stable.
