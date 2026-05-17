defmodule CcxtOcx.Macros.Use do
  @moduledoc """
  Core logic for the `use CcxtOcx` exchange-scoping entrypoint (Task 6b on v0.1).

  This module owns:
  - The NimbleOptions schema for the public macro surface.
  - Normalization and validation of the three supported input modes.
  - The "bare use" policy decision (Option A — hard compile error).
  - Exchange id resolution (explicit list, tier expansion via `CcxtOcx.Tiers`, `:all`).
  - High-quality `CompileError` messages.

  It is called exclusively from `CcxtOcx.__using__/1`. Do not call directly.
  """

  @type resolved_scope :: %{
          exchanges: [atom()],
          mode: :explicit | :tier | :all,
          source: keyword()
        }

  @schema NimbleOptions.new!(
            exchanges: [
              type: {:or, [{:list, :atom}, {:in, [:all]}]},
              doc: """
              Explicit list of exchange ids (as atoms, e.g. [:binance, :deribit])
              or the atom `:all` to generate wrappers for every exchange in the CCXT bundle.
              Mutually exclusive with `:tier`.
              """
            ],
            tier: [
              type: {:in, [:tier1, :tier2, :tier3, :dex]},
              doc: """
              Shortcut that expands to the corresponding priority tier member set
              via `CcxtOcx.Tiers.members_for_tier/1` (includes variants and aliases).
              Mutually exclusive with `:exchanges`.
              """
            ]
          )

  @doc """
  Validates the options given to `use CcxtOcx` and returns a normalized scope.

  `caller` is a plain map captured from `__CALLER__` inside the actual macro
  (`%{file:, line:}`) so this function remains a normal function.
  """
  @spec validate_and_normalize(keyword(), map()) :: resolved_scope()
  def validate_and_normalize(opts, caller) when is_list(opts) and is_map(caller) do
    # Bare `use CcxtOcx` (no options at all) is rejected early with the
    # educational Option A message (see plan). Any non-empty opts go through
    # Nimble first so that unknown keys produce a precise "unknown options"
    # error instead of the generic policy message.
    if opts == [] do
      raise CompileError,
        description: """
        `use CcxtOcx` requires explicit scope.

        You must declare which exchanges you actually need:

            use CcxtOcx, exchanges: [:binance, :okx, :deribit]
            use CcxtOcx, tier: :tier1
            use CcxtOcx, exchanges: :all     # heavy — almost never what you want

        The library is macro-generated. Loading the full surface (~150 unified
        methods × 100+ exchanges) has a significant compile-time and memory cost.
        Requiring an explicit declaration makes that cost visible on day one.

        See the `CcxtOcx` moduledoc for guidance on choosing between an
        explicit list and a priority tier.
        """,
        file: caller.file,
        line: caller.line
    end

    # Nimble catches type errors, unknown keys, etc. Only after it succeeds
    # do we know a recognized scope key was actually supplied.
    case NimbleOptions.validate(opts, @schema) do
      {:ok, validated} ->
        if Keyword.has_key?(validated, :exchanges) and Keyword.has_key?(validated, :tier) do
          raise CompileError,
            description: """
            `:exchanges` and `:tier` are mutually exclusive.

            Choose one:

                use CcxtOcx, exchanges: [:binance, :deribit]
                use CcxtOcx, tier: :tier1
            """,
            file: caller.file,
            line: caller.line
        end

        if Keyword.has_key?(validated, :exchanges) or Keyword.has_key?(validated, :tier) do
          resolve_scope(validated, caller)
        else
          # Should be unreachable (Nimble would have errored on unknown keys),
          # but give a clear message if the schema ever changes.
          raise CompileError,
            description: """
            `use CcxtOcx` requires one of `:exchanges` or `:tier`.

            Supported forms:

                use CcxtOcx, exchanges: [:binance, :deribit]
                use CcxtOcx, tier: :tier1
                use CcxtOcx, exchanges: :all
            """,
            file: caller.file,
            line: caller.line
        end

      {:error, %NimbleOptions.ValidationError{} = err} ->
        raise CompileError,
          description: """
          Invalid options passed to `use CcxtOcx`.

          #{Exception.message(err)}

          Supported forms:

              use CcxtOcx, exchanges: [:binance, :deribit]
              use CcxtOcx, tier: :tier1
              use CcxtOcx, exchanges: :all
          """,
          file: caller.file,
          line: caller.line
    end
  end

  # --- Internal resolution ----------------------------------------------------

  defp resolve_scope(validated, caller) do
    if Keyword.has_key?(validated, :exchanges) do
      resolve_exchanges_mode(validated[:exchanges], caller)
    else
      resolve_tier_mode(validated[:tier], caller)
    end
  end

  defp resolve_exchanges_mode(:all, _caller) do
    # Eagerly expand `:all` to the concrete list so downstream callers (the
    # `__using__` expansion) work with a single shape — `[atom()]`. The list is
    # cheap (no JS, pure read of the .d.ts directory).
    %{
      exchanges: CcxtOcx.Declarations.known_exchange_ids(),
      mode: :all,
      source: [exchanges: :all]
    }
  end

  defp resolve_exchanges_mode(list, caller) when is_list(list) do
    exchanges =
      list
      |> Enum.map(&normalize_exchange_id/1)
      |> Enum.uniq()
      |> Enum.sort()

    # Basic sanity: at least one exchange requested in explicit mode
    if exchanges == [] do
      raise CompileError,
        description: "`use CcxtOcx, exchanges: []` is not allowed. Provide at least one exchange or use a tier.",
        file: caller.file,
        line: caller.line
    end

    validate_known_exchange_ids!(exchanges, caller)

    %{exchanges: exchanges, mode: :explicit, source: [exchanges: list]}
  end

  defp resolve_tier_mode(tier, caller) do
    members =
      tier
      |> CcxtOcx.Tiers.members_for_tier()
      |> Enum.map(&normalize_exchange_id/1)
      |> Enum.sort()

    # The four shipped tiers are guaranteed non-empty by construction in
    # priv/priority_tiers.json + Tiers.Compile. A hand-edited empty tier would
    # simply emit zero exchange modules (harmless).
    validate_known_exchange_ids!(members, caller)

    %{exchanges: members, mode: :tier, source: [tier: tier]}
  end

  defp normalize_exchange_id(id) when is_atom(id), do: id

  # sobelow_skip ["DOS.StringToAtom"]
  # Input is restricted to atoms/strings from `priv/priority_tiers.json` (committed,
  # human-curated, ~30 entries) and the NimbleOptions schema (which already constrains
  # the explicit-list path to `{:list, :atom}`). No user-controlled atom-creation surface.
  defp normalize_exchange_id(id) when is_binary(id), do: String.to_atom(id)

  # --- Unknown id validation + did-you-mean (Task 6b) -------------------------

  defp validate_known_exchange_ids!(ids, caller) do
    known = MapSet.new(CcxtOcx.Declarations.known_exchange_ids())

    unknowns =
      ids
      |> Enum.reject(&MapSet.member?(known, &1))
      |> Enum.sort()

    if unknowns != [] do
      suggestions =
        for u <- unknowns, into: %{} do
          {u, top_suggestions(u, known, 3)}
        end

      msg = build_unknown_exchange_error(unknowns, suggestions)
      raise CompileError, description: msg, file: caller.file, line: caller.line
    end
  end

  defp top_suggestions(unknown, known_set, n) do
    known_set
    |> MapSet.to_list()
    |> Enum.map(fn k -> {k, String.jaro_distance(to_string(unknown), to_string(k))} end)
    |> Enum.sort_by(fn {_, d} -> d end, :desc)
    |> Enum.take(n)
    |> Enum.map(fn {k, _} -> k end)
  end

  defp build_unknown_exchange_error(unknowns, suggestions) do
    lines =
      for u <- unknowns do
        sugg = Map.get(suggestions, u, [])
        sugg_str = if sugg == [], do: "", else: " (did you mean #{inspect(sugg)}?)"
        "  - #{inspect(u)}#{sugg_str}"
      end

    """
    Unknown exchange id(s) passed to `use CcxtOcx`.

    #{Enum.join(lines, "\n")}

    `use CcxtOcx` only accepts ids that exist in the loaded CCXT bundle
    (derived from node_modules/ccxt/js/src/*.d.ts at compile time).

    Run `CcxtOcx.Declarations.known_exchange_ids/0` in IEx (or Tidewave) to
    see the full current list, or pick a priority tier:

        use CcxtOcx, tier: :tier1
    """
  end

  @doc """
  Returns the NimbleOptions schema (useful for docs and tests).
  """
  def schema, do: @schema
end
