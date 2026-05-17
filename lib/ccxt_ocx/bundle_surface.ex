defmodule CcxtOcx.BundleSurface do
  @moduledoc """
  Public surface description for the loaded CCXT bundle.

  This module (and its `Compile` / `Manifest` submodules) power the
  bundle-bump verification pipeline (Task 5b) and will be consumed by the
  macro generators in Phase 2.

  The key artifacts are:
  - The static list of unified public methods (from `Exchange.d.ts`)
  - Sampled per-exchange `has` capability tables (probed via QuickBEAM)

  The checked-in snapshot lives at `priv/ccxt_surface.exs` and is resolved
  through `Manifest.path/0` (which uses `:code.priv_dir/1`).
  """

  alias CcxtOcx.BundleSurface.Compile
  alias CcxtOcx.BundleSurface.Manifest

  # Recompile when the snapshot changes. Path computed at compile time against
  # the source tree (priv hasn't been packaged into the dep yet at this point);
  # runtime callers should use `manifest_path/0` which delegates to `Manifest.path/0`.
  @external_resource Path.join(__DIR__, "../../priv/ccxt_surface.exs")

  @doc "Path to the committed surface manifest (delegates to `Manifest.path/0`)."
  @spec manifest_path() :: String.t()
  def manifest_path, do: Manifest.path()

  @doc "Current unified method list (from the committed manifest)."
  @spec unified_methods() :: [String.t()]
  def unified_methods do
    Manifest.read().unified_methods
  end

  @doc "Sampled has tables from the committed manifest."
  @spec sampled_has() :: %{String.t() => map()}
  def sampled_has do
    Manifest.read().sampled_has
  end

  @doc """
  Build a fresh snapshot from the on-disk CCXT bundle and declarations.
  Used by `mix ccxt.verify_bundle`.
  """
  @spec build_snapshot([String.t()] | nil) :: map()
  def build_snapshot(sample_exchanges \\ nil) do
    methods = Compile.extract_unified_methods(Compile.exchange_dts_path())

    samples = sample_exchanges || Compile.default_sample_exchanges()
    has_tables = Compile.probe_has_tables(samples)

    %{
      ccxt_version: "from-bundle",
      generated_at: DateTime.to_iso8601(DateTime.utc_now()),
      unified_methods: methods,
      sampled_has: has_tables
    }
  end
end
