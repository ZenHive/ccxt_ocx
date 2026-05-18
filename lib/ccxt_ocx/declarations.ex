defmodule CcxtOcx.Declarations do
  @moduledoc """
  Public compile-time surface for CCXT declaration parsing (Task 6).

  This module (and its `Compile` submodule) are the single source of truth for
  the unified method surface extracted from CCXT's own TypeScript declarations.

  Consumers in Phase 2 (Task 6b `use CcxtOcx`, Task 7 `defunified`, Task 9
  `defexchange`) call `parse_unified_surface/0` at compile time to obtain the
  rich per-method terms that drive macro expansion.

  The underlying parser uses OXC (`OXC.parse/2 + OXC.collect/2`) against the
  real declaration files inside `node_modules/ccxt/js/src/...` (not the barrel
  `ccxt.d.ts`). It distinguishes `:base`, `:exchange`, and `:pro` surfaces and
  captures overrides.

  ## Layout stability

  The parser contains loud guards that raise with actionable messages if the
  expected CCXT file layout changes or the smoke-test methods disappear. This
  turns "CCXT bumped and broke our codegen" into a fast, obvious failure instead
  of a mysterious macro bug.
  """

  alias CcxtOcx.Declarations.Compile

  # Recompile the facade when ANY discovered declaration source changes — base,
  # per-exchange, or pro. Limiting this to the base file would let
  # `parse_unified_surface/0` return stale terms after `mix npm.update ccxt`
  # touches only an exchange-specific or pro .d.ts.
  for path <- [Compile.base_dts_path()] ++ Compile.exchange_dts_paths() ++ Compile.pro_dts_paths() do
    @external_resource path
  end

  @doc """
  Parse the discovered CCXT declaration surface and return one rich term per
  public unified method.

  See `t:CcxtOcx.Declarations.Compile.method_term/0` for the exact shape.
  """
  @spec parse_unified_surface() :: [Compile.method_term()]
  def parse_unified_surface, do: Compile.parse_unified_surface()

  @doc "Delegates to `Compile.public_unified_method?/1` (the single source of truth)."
  @spec public_unified_method?(String.t()) :: boolean()
  def public_unified_method?(name), do: Compile.public_unified_method?(name)

  @doc "Absolute path to the core Exchange.d.ts (convenience for docs / tests)."
  @spec base_dts_path() :: String.t()
  def base_dts_path, do: Compile.base_dts_path()

  @doc """
  Pure list of all known CCXT exchange ids (atoms) derived from the .d.ts files.

  Zero-cost at compile time (no QuickBEAM). Consumed by `use CcxtOcx` (Task 6b)
  for unknown-exchange validation + did-you-mean suggestions, and by Task 9
  `defexchange` for capability gating.
  """
  @spec known_exchange_ids() :: [atom()]
  def known_exchange_ids, do: Compile.known_exchange_ids()
end
