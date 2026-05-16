defmodule CcxtOcx.Tiers.Compile do
  @moduledoc """
  Compile-time helpers for `CcxtOcx.Tiers`.

  Spins up a throwaway QuickBEAM runtime to derive variant inheritance
  from the loaded CCXT bundle's prototype chains. The
  application-supervised `CcxtOcx.Runtime` is not started during
  `mix compile`, so this module runs its own raw `QuickBEAM.start/1`,
  applies the same browser stubs the runtime uses, loads the bundle,
  walks `Object.getPrototypeOf` for every exchange, and stops the
  runtime.

  The output (a `%{variant_id => parent_id}` map) is consumed inside
  `CcxtOcx.Tiers` module attributes — runtime cost is zero JS.

  ## Why reference comparison

  The CCXT bundle is webpack-minified; `constructor.name` returns mangled
  single-letter names. The walk builds a `ctor -> name` map keyed on the
  preserved string IDs in `self.ccxt.default.exchanges`, then compares
  each prototype's constructor by reference identity.
  """

  @bundle_relative "node_modules/ccxt/dist/ccxt.browser.min.js"
  @load_timeout to_timeout(second: 30)
  @walk_depth_cap 8

  @doc """
  Absolute path to the CCXT browser bundle, resolved at compile time.

  Honors `Application.get_env(:ccxt_ocx, :bundle_path)` for overrides;
  defaults to the in-tree `node_modules/ccxt/dist/ccxt.browser.min.js`
  relative to `File.cwd!/0`.
  """
  @spec bundle_path() :: String.t()
  def bundle_path do
    configured = Application.get_env(:ccxt_ocx, :bundle_path, @bundle_relative)

    if Path.type(configured) == :absolute,
      do: configured,
      else: Path.join(File.cwd!(), configured)
  end

  @doc """
  Derive the exchange inheritance map from the loaded CCXT bundle.

  Returns `%{variant_id => parent_id}` for every exchange whose
  prototype-chain parent is itself an exchange class in the bundle
  (e.g. `binanceus → binance`, `huobi → htx`). Pure exchanges that
  extend the base `Exchange` class are absent from the map — their
  tier is determined by direct root membership, not inheritance.

  Boots a fresh `QuickBEAM` runtime, applies browser stubs, evals the
  bundle, runs the inheritance walk, and stops the runtime.
  Raises with actionable instructions when the bundle file is missing.
  """
  @spec derive_inheritance!(String.t()) :: %{String.t() => String.t()}
  def derive_inheritance!(bundle_path) do
    if not File.exists?(bundle_path) do
      raise """
      CCXT bundle not found at #{bundle_path}.

      Run `mix npm.install` to fetch the ccxt npm package (the bundle
      lives at node_modules/ccxt/dist/ccxt.browser.min.js once installed).
      """
    end

    bundle = File.read!(bundle_path)
    {:ok, rt} = QuickBEAM.start(apis: :browser)

    try do
      :ok = apply_browser_stubs(rt)
      {:ok, _} = QuickBEAM.call(rt, "eval", [bundle], timeout: @load_timeout)
      {:ok, map} = QuickBEAM.eval(rt, inheritance_js())
      map
    after
      QuickBEAM.stop(rt)
    end
  end

  @doc """
  Expand a list of root exchange IDs into the full member set.

  A variant is included when its transitive parent (walked through
  `inheritance_map`, capped at #{@walk_depth_cap} hops) is one of the
  roots. Output is sorted and deduplicated.
  """
  @spec expand([String.t()], %{String.t() => String.t()}) :: [String.t()]
  def expand(roots, inheritance_map) do
    roots_set = MapSet.new(roots)

    variants =
      for {id, _parent} <- inheritance_map,
          not MapSet.member?(roots_set, id),
          MapSet.member?(roots_set, resolve_root(id, inheritance_map, @walk_depth_cap)),
          do: id

    (roots ++ variants) |> Enum.uniq() |> Enum.sort()
  end

  @spec resolve_root(String.t(), %{String.t() => String.t()}, non_neg_integer()) :: String.t()
  defp resolve_root(id, _map, 0), do: id

  defp resolve_root(id, map, depth) do
    case Map.get(map, id) do
      nil -> id
      ^id -> id
      parent -> resolve_root(parent, map, depth - 1)
    end
  end

  @spec apply_browser_stubs(pid()) :: :ok
  defp apply_browser_stubs(rt) do
    {:ok, _} =
      QuickBEAM.eval(rt, "globalThis.self = globalThis; globalThis.window = globalThis;")

    :ok =
      QuickBEAM.set_global(rt, "navigator", %{"userAgent" => "QuickBEAM/CcxtOcx-Tiers-Compile"})

    :ok =
      QuickBEAM.set_global(rt, "location", %{"protocol" => "https:", "host" => "ccxt-ocx.local"})

    :ok
  end

  @spec inheritance_js() :: String.t()
  defp inheritance_js do
    """
    (function() {
      const c = self.ccxt.default;
      const names = c.exchanges;
      const ctorToName = new Map();
      for (const name of names) { ctorToName.set(c[name], name); }
      const result = {};
      for (const name of names) {
        const parent = Object.getPrototypeOf(c[name].prototype).constructor;
        const parentName = ctorToName.get(parent);
        if (parentName) { result[name] = parentName; }
      }
      return result;
    })()
    """
  end
end
