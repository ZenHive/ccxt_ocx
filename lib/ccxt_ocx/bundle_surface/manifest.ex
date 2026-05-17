defmodule CcxtOcx.BundleSurface.Manifest do
  @moduledoc """
  Read/write/diff helpers for `priv/ccxt_surface.exs`.

  The file contains a single top-level map that is the "known good"
  surface for the current committed CCXT version.
  """

  @path "priv/ccxt_surface.exs"

  @doc "Absolute path to the manifest (resolved against the current working directory)."
  def path, do: Path.join(File.cwd!(), @path)

  @doc "Read and evaluate the committed manifest. Raises on missing file."
  def read do
    p = path()

    unless File.exists?(p) do
      raise """
      CCXT surface manifest not found at #{p}.

      This file is created by Task 5b's verification pipeline.
      Run `mix ccxt.verify_bundle --accept` (after the first successful
      extraction) to generate the initial baseline.
      """
    end

    {term, _binding} = Code.eval_file(p)
    term
  end

  @doc """
  Write a new snapshot to the manifest path (pretty-printed for human review).
  Used by the `--accept` / `--write` flow of the Mix task.
  """
  def write(snapshot) when is_map(snapshot) do
    p = path()
    File.mkdir_p!(Path.dirname(p))

    content = """
    # CCXT surface snapshot for bundle-bump verification (Task 5b)
    #
    # This file is the source of truth for the public unified method surface
    # that `use CcxtOcx` + defunified will generate wrappers for.
    #
    # Generated from the current CCXT bundle + .d.ts files.
    # Run `mix ccxt.verify_bundle --accept` after human review of any drift.

    #{inspect(snapshot, pretty: true, limit: :infinity, charlists: false)}
    """

    File.write!(p, content)
    :ok
  end

  @doc "Return a human-readable diff between two snapshots (method list + sampled has)."
  def diff(old, new) do
    old_methods = Map.get(old, :unified_methods, []) |> MapSet.new()
    new_methods = Map.get(new, :unified_methods, []) |> MapSet.new()

    added = MapSet.difference(new_methods, old_methods) |> MapSet.to_list() |> Enum.sort()
    removed = MapSet.difference(old_methods, new_methods) |> MapSet.to_list() |> Enum.sort()

    %{
      methods: %{added: added, removed: removed},
      has_changed?: Map.get(old, :sampled_has) != Map.get(new, :sampled_has)
    }
  end
end
