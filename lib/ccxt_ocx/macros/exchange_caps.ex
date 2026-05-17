defmodule CcxtOcx.Macros.ExchangeCaps do
  @moduledoc """
  Compile-time per-exchange capability & metadata cache (introduced in Task 6b,
  exercised by Task 9 `defexchange`).

  **Current status (v0.1 / after Task 6b)**: The module is fully implemented and
  the cache format is stable, but **it is not invoked by the `use CcxtOcx` stub
  emission**. The only live public surface today is the zero-JS delegation
  `known_exchange_ids/0 → Declarations.known_exchange_ids/0`.

  When Task 9 lands, `defexchange` (and any manual call) will do:

      caps = CcxtOcx.Macros.ExchangeCaps.fetch_or_build(:deribit)
      # => %{id: :deribit, has: %{}, urls: %{}, timeframes: %{}, ...}

  For every exchange declared via `use CcxtOcx`, this module can produce a
  stable map containing:

    * `:has` — the CCXT capability table (`fetchTicker: true`, `createOrder: "emulated"`, ...)
    * `:urls`, `:timeframes`, `:rateLimit`, `:defaultType` (from options)

  The first call for an id boots a short-lived QuickBEAM runtime (same browser-stub
  + bundle pattern as `Tiers.Compile` and `BundleSurface.Compile`), extracts the data,
  writes a reproducible Elixir term to `priv/exchange_caps/<id>.exs`, and returns it.

  Subsequent compiles hit the file (cheap `Code.eval_file`). A bundle bump
  invalidates via the Task 5b verify pipeline (which will be taught to refresh caps).

  The pure `known_exchange_ids/0` (zero JS) is delegated to `CcxtOcx.Declarations`
  so the `use` macro validator stays fast and has no NIF side-effects.

  ## Extension point for Task 9

  `defexchange` will call `fetch_or_build/1` (or the lower-level probe) to emit
  the per-exchange struct + `has?/1`, `urls/0`, `timeframes/0` etc. without
  re-implementing the QuickBEAM dance.

  When wiring the reader side in Task 9, add `@external_resource` on the
  consuming modules so that a regenerated caps file forces recompilation.
  """


  alias CcxtOcx.Declarations

  @cache_dir "priv/exchange_caps"
  @load_timeout 30_000

  @doc "Delegates to the pure (no-JS) list in Declarations — the single source of truth."
  @spec known_exchange_ids() :: [atom()]
  def known_exchange_ids, do: Declarations.known_exchange_ids()

  @doc """
  Returns the cached (or freshly probed) capability map for one exchange id.

  The map is written as a pretty-printed .exs file so it is human-readable and
  `Code.eval_file/1` friendly. The file is the artifact that Task 9 will consume.
  """
  @spec fetch_or_build(atom()) :: map()
  def fetch_or_build(id) when is_atom(id) do
    path = caps_path(id)

    if File.exists?(path) do
      {term, _binding} = Code.eval_file(path)
      term
    else
      build_and_cache!(id, path)
    end
  end

  @doc """
  Absolute path to the (possibly not-yet-created) caps cache file for a given
  exchange id. Pure function — does not create directories or files.
  """
  @spec caps_path(atom()) :: String.t()
  def caps_path(id) do
    dir = Path.join(File.cwd!(), @cache_dir)
    Path.join(dir, "#{id}.exs")
  end

  # --- Probing implementation (adapted from BundleSurface.Compile) ------------
  # TODO(Task 9): extract the shared "boot QuickBEAM :browser + apply stubs +
  # load bundle + stop in `after`" pattern (also in `Tiers.Compile` and
  # `BundleSurface.Compile`) into a single `CcxtOcx.CompileProbe` helper once
  # `defexchange` lands and we know the final stub surface.

  @spec build_and_cache!(atom(), String.t()) :: map()
  defp build_and_cache!(id, path) do
    bundle_path = bundle_path()

    if !File.exists?(bundle_path) do
      raise CompileError,
        description: """
        CCXT bundle not found at #{bundle_path}.

        Run `mix npm.install` before compiling any `use CcxtOcx`.
        """
    end

    # Ensure cache dir only on the write path (caps_path is intentionally pure).
    File.mkdir_p!(Path.dirname(path))

    bundle = File.read!(bundle_path)
    {:ok, rt} = QuickBEAM.start(apis: :browser)

    try do
      apply_browser_stubs(rt)
      {:ok, _} = QuickBEAM.call(rt, "eval", [bundle], timeout: @load_timeout)

      {:ok, json} =
        QuickBEAM.eval(rt, probe_js(),
          vars: %{"__exchange_id" => to_string(id)},
          timeout: @load_timeout
        )

      data = Jason.decode!(json)

      if Map.has_key?(data, "__error") do
        raise CompileError,
          description: "ExchangeCaps probe failed for #{id}: #{data["__error"]}"
      end

      # Normalize keys to atoms for nicer Elixir consumption in Task 9
      term = %{
        id: id,
        has: data["has"] || %{},
        urls: data["urls"] || %{},
        timeframes: data["timeframes"] || %{},
        rate_limit: data["rateLimit"],
        default_type: data["defaultType"],
        version: data["version"]
      }

      File.write!(path, inspect(term, pretty: true, limit: :infinity) <> "\n")
      term
    after
      QuickBEAM.stop(rt)
    end
  end

  @spec bundle_path() :: String.t()
  defp bundle_path do
    :ccxt_ocx
    |> Application.get_env(:bundle_path, "node_modules/ccxt/dist/ccxt.browser.min.js")
    |> then(fn p ->
      if Path.type(p) == :absolute, do: p, else: Path.join(File.cwd!(), p)
    end)
  end

  @spec apply_browser_stubs(pid()) :: :ok
  defp apply_browser_stubs(rt) do
    {:ok, _} = QuickBEAM.eval(rt, "globalThis.self = globalThis; globalThis.window = globalThis;")

    :ok = QuickBEAM.set_global(rt, "navigator", %{"userAgent" => "QuickBEAM/CcxtOcx-ExchangeCaps"})

    :ok =
      QuickBEAM.set_global(rt, "location", %{"protocol" => "https:", "host" => "ccxt-ocx.local"})

    :ok
  end

  # Rich probe: has + the metadata Task 9's defexchange will need.
  # Data is injected via :vars so the JS source stays static (no string interpolation).
  @spec probe_js() :: String.t()
  defp probe_js do
    """
    (async () => {
      const id = __exchange_id;
      const Ctor = self.ccxt.default[id] || self.ccxt[id];
      if (!Ctor) return JSON.stringify({__error: "exchange constructor not found: " + id});
      try {
        const ex = new Ctor({ enableRateLimit: false, timeout: 5000 });
        return JSON.stringify({
          has: ex.has || {},
          urls: ex.urls || {},
          timeframes: ex.timeframes || {},
          rateLimit: ex.rateLimit || null,
          defaultType: (ex.options || {}).defaultType || null,
          version: ex.version || null
        });
      } catch (e) {
        return JSON.stringify({__error: String(e)});
      }
    })()
    """
  end
end
