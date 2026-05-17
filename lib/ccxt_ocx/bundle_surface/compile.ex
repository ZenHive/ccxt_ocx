defmodule CcxtOcx.BundleSurface.Compile do
  @moduledoc """
  Compile-time (and verification-time) helpers for the CCXT bundle surface.

  Used by:
  - The `mix ccxt.verify_bundle` task (Task 5b) to build the snapshot that
    gets diffed against `priv/ccxt_surface.exs`.
  - Future macro generators (Task 6/9) that need the static list of unified
    methods and per-exchange capability (`has`) tables.

  This module isolates the expensive work:
  - OXC parsing of `Exchange.d.ts` + selected per-exchange `.d.ts` files
  - Optional throwaway QuickBEAM runtimes to probe live `ex.has` tables

  The supervised `CcxtOcx.Runtime` is **not** used here — we spin fresh
  runtimes exactly like `CcxtOcx.Tiers.Compile` does during `mix compile`.

  ## Browser stub requirement

  The CCXT browser bundle expects `self` / `window` / `navigator` / `location`.
  We use `QuickBEAM.eval/3` (not `set_global/3` with atoms) for `self` and
  `window` because atoms become strings in the JS context.
  See the quickbeam skill for the canonical pattern.
  """

  @bundle_relative "node_modules/ccxt/dist/ccxt.browser.min.js"
  @exchange_dts "node_modules/ccxt/js/src/base/Exchange.d.ts"
  @load_timeout to_timeout(second: 30)
  @per_exchange_timeout to_timeout(minute: 1)

  # Small, high-value sample for has probing (Tier 1 + one options venue).
  # Keeps verification fast while still exercising the important signing/WS paths.
  @default_sample_exchanges ["binance", "bybit", "okx", "deribit", "coinbaseexchange"]

  # Verb prefixes that mark a method as part of the public unified surface.
  @verb_prefixes ~w(fetch create watch cancel edit loadMarkets set close describe)

  # Prefixes that mark a method as internal/base-class helper machinery and
  # MUST be filtered out even if they collide with a verb prefix (e.g. `parse`,
  # `handle`, `safeMarket`).
  @internal_prefixes ~w(parse handle sign request safe market nonce define extend)

  # Exact-name denylist for CCXT base-class helpers that *do* match a verb
  # prefix and *don't* match an internal prefix (so the prefix heuristic alone
  # captures them) but are not part of the unified public surface. Pollution
  # source: CCXT base Exchange ships these as plumbing — pagination, partial
  # balance access, HTTP retry, webpage fetch, safe-dict construction, and the
  # `loadMarkets` internal helper. Letting them stay in the manifest would mean
  # Phase 2's `defunified` macro generates wrappers for internal helpers with no
  # documented contract. Extend when future CCXT versions add new helpers that
  # slip past the prefix filter.
  @additional_denied ~w(
    fetch2
    fetchPaginatedCallCursor
    fetchPaginatedCallDeterministic
    fetchPaginatedCallDynamic
    fetchPaginatedCallIncremental
    fetchPartialBalance
    fetchWebEndpoint
    createSafeDictionary
    loadMarketsHelper
  )

  # Trade-plane methods that don't match the verb-prefix filter but are part of
  # the public unified surface (CCXT exposes them as bare-name methods on
  # exchanges that support them — withdrawals, transfers, isolated/cross
  # margin adjustments). Without this allowlist they'd be dropped from the
  # snapshot and never get a defunified wrapper.
  @additional_unified_methods ~w(
    withdraw
    transfer
    addMargin
    reduceMargin
    borrowCrossMargin
    borrowIsolatedMargin
    repayCrossMargin
    repayIsolatedMargin
  )

  @doc """
  Absolute path to the CCXT browser bundle (same logic as Tiers.Compile).
  """
  @spec bundle_path() :: String.t()
  def bundle_path do
    configured = Application.get_env(:ccxt_ocx, :bundle_path, @bundle_relative)

    if Path.type(configured) == :absolute,
      do: configured,
      else: Path.join(File.cwd!(), configured)
  end

  @doc """
  Absolute path to the main Exchange.d.ts that declares the unified surface.
  """
  @spec exchange_dts_path() :: String.t()
  def exchange_dts_path do
    Path.join(File.cwd!(), @exchange_dts)
  end

  @doc """
  Extract the list of public unified method names from the given .d.ts file
  using OXC.

  Filters out internal helpers (`parse*`, `handle*`, `sign`, `request`, etc.)
  and keeps the high-level `fetch*`, `create*`, `watch*`, `cancel*`, `edit*`,
  `loadMarkets`, `set*`, etc. plus the bare-name trade-plane methods listed in
  `@additional_unified_methods`.

  Returns a sorted list of strings.
  """
  @spec extract_unified_methods(String.t()) :: [String.t()]
  def extract_unified_methods(dts_path) do
    if !File.exists?(dts_path) do
      raise """
      CCXT declaration file not found at #{dts_path}.

      Run `mix npm.install` (or `mix npm.ci`) to populate node_modules/ccxt/.
      """
    end

    source = File.read!(dts_path)
    {:ok, ast} = OXC.parse(source, Path.basename(dts_path))

    names =
      OXC.collect(ast, fn
        %{type: :method_definition, key: %{name: name}} = _node ->
          if public_unified_method?(name), do: {:keep, name}, else: :skip

        _ ->
          :skip
      end)

    names
    |> MapSet.new()
    |> MapSet.to_list()
    |> Enum.sort()
  end

  @doc """
  Probe live `has` tables for the given list of exchange ids.

  Boots a fresh QuickBEAM runtime (browser APIs + CCXT bundle), then for each
  exchange id does:

      const ex = new self.ccxt.<id>({enableRateLimit: false});
      ex.has

  Returns `%{exchange_id => has_map}` where `has_map` is the raw CCXT
  `has` dictionary (values are `true`, `"emulated"`, or `undefined` / absent).

  The runtime is stopped in an `after` block even on error.
  """
  @spec probe_has_tables([String.t()]) :: %{String.t() => map()}
  def probe_has_tables(exchange_ids) when is_list(exchange_ids) do
    bundle_path = bundle_path()

    if !File.exists?(bundle_path) do
      raise """
      CCXT bundle not found at #{bundle_path}.

      Run `mix npm.install` to fetch the ccxt npm package.
      """
    end

    bundle = File.read!(bundle_path)
    {:ok, rt} = QuickBEAM.start(apis: :browser)

    try do
      apply_browser_stubs(rt)
      {:ok, _} = QuickBEAM.call(rt, "eval", [bundle], timeout: @load_timeout)

      {:ok, json} =
        QuickBEAM.eval(rt, has_probe_js(),
          vars: %{"__exchange_ids" => exchange_ids},
          timeout: @per_exchange_timeout
        )

      Jason.decode!(json)
    after
      QuickBEAM.stop(rt)
    end
  end

  @doc """
  Default list of exchanges we sample for `has` tables during verification.
  Uses Tier 1 roots when available, falling back to a safe hardcoded list.
  """
  @spec default_sample_exchanges() :: [String.t()]
  def default_sample_exchanges do
    # Prefer the already-compiled Tier data if it is safe to call here.
    # During early compile of the verifier task itself we may not have it yet,
    # so we keep a static fallback.
    CcxtOcx.Tiers.tier1_exchanges()
  rescue
    _ -> @default_sample_exchanges
  end

  # --- Private helpers ------------------------------------------------------

  @spec public_unified_method?(String.t()) :: boolean()
  defp public_unified_method?(name) do
    has_good_prefix = Enum.any?(@verb_prefixes, &String.starts_with?(name, &1))
    has_bad_prefix = Enum.any?(@internal_prefixes, &String.starts_with?(name, &1))
    in_allowlist = name in @additional_unified_methods
    in_denylist = name in @additional_denied

    (has_good_prefix or in_allowlist) and not has_bad_prefix and not in_denylist
  end

  @spec apply_browser_stubs(pid()) :: :ok
  defp apply_browser_stubs(rt) do
    {:ok, _} =
      QuickBEAM.eval(rt, "globalThis.self = globalThis; globalThis.window = globalThis;")

    :ok =
      QuickBEAM.set_global(rt, "navigator", %{"userAgent" => "QuickBEAM/CcxtOcx-BundleSurface"})

    :ok =
      QuickBEAM.set_global(rt, "location", %{"protocol" => "https:", "host" => "ccxt-ocx.local"})

    :ok
  end

  # JS source for the has-table probe. Reads exchange ids from the JS global
  # `__exchange_ids` injected by `QuickBEAM.eval/3`'s `:vars` option — this
  # keeps Elixir-side data out of the source string entirely, so an attacker
  # controlling the exchange-id list (improbable, but cheap to neutralize)
  # cannot inject JS.
  @spec has_probe_js() :: String.t()
  defp has_probe_js do
    """
    (async () => {
      const result = {};
      const ids = __exchange_ids;
      for (const id of ids) {
        try {
          const Ctor = self.ccxt.default[id] || self.ccxt[id];
          if (!Ctor) { result[id] = null; continue; }
          const ex = new Ctor({ enableRateLimit: false, timeout: 5000 });
          // We only need the has table; avoid network side-effects
          result[id] = ex.has || {};
        } catch (e) {
          result[id] = { __error: String(e) };
        }
      }
      return JSON.stringify(result);
    })()
    """
  end
end
