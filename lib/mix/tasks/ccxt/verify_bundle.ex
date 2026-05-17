defmodule Mix.Tasks.Ccxt.VerifyBundle do
  @shortdoc "Verify that the current CCXT bundle surface matches the committed manifest (Task 5b)"

  @moduledoc """
  `mix ccxt.verify_bundle`

  Runs the bundle-bump verification pipeline:

  1. Extracts the current unified method list from `Exchange.d.ts` via OXC.
  2. Probes sampled per-exchange `has` tables via a throwaway QuickBEAM runtime.
  3. Diffs the result against `priv/ccxt_surface.exs`.
  4. Fails (exit 1) on any drift unless `--accept` is passed.

  This task is intended to run in CI after `mix npm.ci` on any PR that
  touches `package.json`, the lockfile, or `node_modules/ccxt/`.

  ## Options

    * `--accept` / `--write` – Regenerate `priv/ccxt_surface.exs` from the
      current bundle after a human has reviewed the diff. Use only when you
      intentionally accept a surface change.
    * `--sample-exchanges a,b,c` – Override the default Tier-1 sample list.

  ## Examples

      # Normal verification (used in CI)
      mix ccxt.verify_bundle

      # After a deliberate CCXT upgrade that changes the surface
      mix ccxt.verify_bundle --accept
  """

  use Mix.Task

  alias CcxtOcx.BundleSurface
  alias CcxtOcx.BundleSurface.Manifest

  # we need the app env for bundle_path overrides
  @requirements ["app.config"]

  @impl true
  @spec run([String.t()]) :: :ok
  def run(args) do
    {opts, _rest, invalid} =
      OptionParser.parse(args,
        switches: [accept: :boolean, write: :boolean, sample_exchanges: :string],
        aliases: [a: :accept, w: :write]
      )

    if invalid != [] do
      Mix.raise(
        "Unknown or malformed option(s): " <>
          Enum.map_join(invalid, ", ", fn
            {k, nil} -> k
            {k, v} -> "#{k}=#{v}"
          end)
      )
    end

    accept? = Keyword.get(opts, :accept, false) or Keyword.get(opts, :write, false)

    sample =
      case Keyword.get(opts, :sample_exchanges) do
        nil -> nil
        csv -> String.split(csv, ",", trim: true)
      end

    Mix.shell().info("CCXT bundle surface verification (Task 5b)")

    snapshot = BundleSurface.build_snapshot(sample)

    committed = Manifest.read()

    diff = Manifest.diff(committed, snapshot)

    if diff.methods.added == [] and diff.methods.removed == [] and not diff.has_changed? do
      Mix.shell().info("✓ Surface matches committed manifest (#{length(committed.unified_methods)} methods)")
      :ok
    else
      print_diff(diff, snapshot)

      if accept? do
        Manifest.write(snapshot)
        Mix.shell().info("Manifest updated (accepted).")
        :ok
      else
        Mix.raise("""
        CCXT bundle surface drift detected.

        A `mix npm.update ccxt` (or manual change to node_modules/ccxt/) has
        altered the public unified method list or sampled `has` tables.

        This is a **human review gate**, not a silent auto-accept.

        Review the diff above. If the change is expected and safe:

            mix ccxt.verify_bundle --accept

        Then commit the updated `priv/ccxt_surface.exs`.

        If the change looks wrong, investigate the CCXT release notes or
        pin a known-good version in package.json.
        """)
      end
    end
  end

  @spec print_diff(map(), map()) :: :ok
  defp print_diff(diff, snapshot) do
    Mix.shell().info("")

    if diff.methods.added != [] do
      Mix.shell().info("Added methods (#{length(diff.methods.added)}):")
      Enum.each(diff.methods.added, &Mix.shell().info("  + #{&1}"))
    end

    if diff.methods.removed != [] do
      Mix.shell().info("Removed methods (#{length(diff.methods.removed)}):")
      Enum.each(diff.methods.removed, &Mix.shell().info("  - #{&1}"))
    end

    if diff.has_changed? do
      Mix.shell().info("Sampled `has` tables differ for one or more exchanges.")
    end

    Mix.shell().info("")
    Mix.shell().info("Current snapshot has #{length(snapshot.unified_methods)} unified methods.")
    Mix.shell().info("Run with --accept to write a new baseline after review.")
  end
end
