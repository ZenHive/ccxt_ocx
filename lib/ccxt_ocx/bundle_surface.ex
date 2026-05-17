defmodule CcxtOcx.BundleSurface do
  @moduledoc """
  Public surface description for the loaded CCXT bundle.

  This module (and its `Compile` / `Manifest` submodules) power the
  bundle-bump verification pipeline (Task 5b) and will be consumed by the
  macro generators in Phase 2.

  The key artifacts are:
  - The static list of unified public methods (from `Exchange.d.ts`)
  - Sampled per-exchange `has` capability tables (probed via QuickBEAM)

  The checked-in snapshot lives at `priv/ccxt_surface.exs`.
  """

  alias CcxtOcx.BundleSurface.Compile
  alias CcxtOcx.BundleSurface.Manifest

  @manifest_path Path.join(__DIR__, "../../priv/ccxt_surface.exs")
  @external_resource @manifest_path

  @doc "Path to the committed surface manifest."
  def manifest_path, do: @manifest_path

  @doc "Current unified method list (from the committed manifest)."
  def unified_methods do
    Manifest.read().unified_methods
  end

  @doc "Sampled has tables from the committed manifest."
  def sampled_has do
    Manifest.read().sampled_has
  end

  @doc """
  Build a fresh snapshot from the on-disk CCXT bundle and declarations.
  Used by `mix ccxt.verify_bundle`.
  """
  def build_snapshot(sample_exchanges \\ nil) do
    methods = Compile.extract_unified_methods(Compile.exchange_dts_path())

    samples = sample_exchanges || Compile.default_sample_exchanges()
    has_tables = Compile.probe_has_tables(samples)

    %{
      # filled by verifier with real runtime info
      ccxt_version: "from-bundle",
      generated_at: DateTime.to_iso8601(DateTime.utc_now()),
      unified_methods: methods,
      sampled_has: has_tables
    }
  end
end
