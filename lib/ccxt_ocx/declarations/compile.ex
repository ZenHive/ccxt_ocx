defmodule CcxtOcx.Declarations.Compile do
  @moduledoc """
  Compile-time parser for CCXT TypeScript declaration sources via OXC.

  Discovers `js/src/base/Exchange.d.ts`, per-exchange `*.d.ts`, and `pro/*.d.ts`,
  extracts unified method signatures (name + params + return type), classifies
  by owning surface (`:base`, `:exchange`, `:pro`), and captures exchange-specific
  overrides.

  This is the foundation for the Phase 2 macro layer (`defunified`, `defexchange`,
  `use CcxtOcx`). Output is a list of stable Elixir terms consumed at compile time
  by the macro generators.

  ## Layout guard

  The parser hard-fails (with actionable instructions) if the expected CCXT
  declaration layout disappears or the three smoke-test methods are absent from
  the base surface. This makes "CCXT changed their .d.ts" a loud, fast failure
  instead of a silent macro-generation bug later.
  """

  # --- Filter lists (source of truth for "public unified surface") ------------

  # Verb prefixes that mark a method as part of the public unified surface.
  @verb_prefixes ~w(fetch create watch cancel edit loadMarkets set close describe)

  # Prefixes that mark a method as internal/base-class helper machinery and
  # MUST be filtered out even if they collide with a verb prefix.
  @internal_prefixes ~w(parse handle sign request safe market nonce define extend)

  # Exact-name denylist for CCXT base-class helpers that slip past the prefix
  # heuristic but are not part of the unified public surface.
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

  # Trade-plane methods that don't match the verb-prefix filter but belong in
  # the public unified surface.
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

  # --- Path configuration (mirrors BundleSurface.Compile / Tiers.Compile) -----

  @base_dts "node_modules/ccxt/js/src/base/Exchange.d.ts"
  @exchange_glob "node_modules/ccxt/js/src/*.d.ts"
  @pro_glob "node_modules/ccxt/js/src/pro/*.d.ts"

  @doc """
  Absolute path to the core Exchange.d.ts (the :base unified contract).
  """
  @spec base_dts_path() :: String.t()
  def base_dts_path do
    Path.join(File.cwd!(), @base_dts)
  end

  @doc """
  Absolute paths to all top-level per-exchange .d.ts files (surface :exchange).
  Excludes subdirectories (base/, pro/, abstract/, etc.).
  """
  @spec exchange_dts_paths() :: [String.t()]
  def exchange_dts_paths do
    Path.wildcard(Path.join(File.cwd!(), @exchange_glob))
  end

  @doc """
  Absolute paths to all CCXT Pro declaration files (surface :pro).
  """
  @spec pro_dts_paths() :: [String.t()]
  def pro_dts_paths do
    Path.wildcard(Path.join(File.cwd!(), @pro_glob))
  end

  # --- Public entry point -----------------------------------------------------

  @type param :: %{name: String.t(), type: String.t(), optional: boolean()}
  @type surface :: :base | :exchange | :pro
  @type declaration_ref :: %{surface: surface, source: String.t()}
  @type override_ref :: %{surface: surface, source: String.t(), params: [param()], return_type: String.t()}
  @type method_term :: %{
          name: String.t(),
          params: [param()],
          return_type: String.t(),
          primary: declaration_ref(),
          overrides: %{optional(String.t()) => override_ref()}
        }

  @doc """
  Parse the entire discovered CCXT declaration surface and return one rich term
  per public unified method.

  The term contains the canonical (primary) signature from the base surface,
  plus any per-exchange or pro overrides that re-declare the same method with
  different types or JSDoc.

  Raises with a loud, actionable message if the CCXT .d.ts layout has changed
  (missing key files or disappearance of the three smoke-test methods).
  """
  @spec parse_unified_surface() :: [method_term()]
  def parse_unified_surface do
    base_path = base_dts_path()

    if !File.exists?(base_path) do
      raise """
      CCXT declaration layout changed.

      Expected core file not found:
        #{base_path}

      Run `mix npm.install` (or `mix npm.ci`) to restore node_modules/ccxt/,
      then recompile.
      """
    end

    base_methods = parse_dts(base_path, {:base, nil})

    exchange_methods =
      Enum.flat_map(exchange_dts_paths(), fn p -> parse_dts(p, {:exchange, exchange_id_from_path(p)}) end)

    pro_methods =
      Enum.flat_map(pro_dts_paths(), fn p -> parse_dts(p, {:pro, exchange_id_from_path(p)}) end)

    all = base_methods ++ exchange_methods ++ pro_methods

    grouped = Enum.group_by(all, & &1.name)

    terms =
      for {name, decls} <- grouped, into: [] do
        primary = Enum.find(decls, &(&1.surface == :base)) || hd(decls)

        overrides =
          decls
          |> Enum.reject(&(&1.surface == primary.surface and &1.source == primary.source))
          |> Map.new(fn d ->
            # Key by "surface:exchange_id" so an :exchange and a :pro override
            # for the same exchange (e.g. kucoinfutures.fetchBidsAsks lives in
            # both src/kucoinfutures.d.ts and src/pro/kucoinfutures.d.ts) both
            # survive rather than silently overwriting one another.
            eid = d.exchange_id || "unknown"
            key = "#{d.surface}:#{eid}"
            {key, Map.take(d, [:surface, :source, :params, :return_type])}
          end)

        %{
          name: name,
          params: primary.params,
          return_type: primary.return_type,
          primary: %{surface: primary.surface, source: primary.source},
          overrides: overrides
        }
      end

    terms = Enum.sort_by(terms, & &1.name)

    assert_required_methods!(terms)

    terms
  end

  # --- Core parser ------------------------------------------------------------

  @spec parse_dts(String.t(), {surface(), String.t() | nil}) :: [map()]
  defp parse_dts(path, {surface, exchange_id}) do
    if File.exists?(path) do
      source = File.read!(path)

      ast =
        case OXC.parse(source, Path.basename(path)) do
          {:ok, ast} ->
            ast

          {:error, errors} ->
            messages = Enum.map_join(errors, "\n  - ", & &1.message)

            raise """
            Failed to parse CCXT declaration file with OXC:

              #{path}

            OXC errors:
              - #{messages}

            This usually means CCXT shipped invalid TypeScript or OXC's parser
            doesn't yet understand a syntax form in this file. Pin CCXT to a
            known-good version in package.json, then bump OXC.
            """
        end

      OXC.collect(ast, &collect_method(&1, surface, exchange_id, path))
    else
      # Non-fatal for secondary surfaces during discovery; just skip.
      []
    end
  end

  @spec collect_method(map(), surface(), atom() | nil, String.t()) ::
          {:keep, map()} | :skip
  defp collect_method(node, surface, exchange_id, path) do
    case node do
      %{type: :method_definition, key: %{name: name}, value: value} ->
        if public_unified_method?(name) do
          {:keep, build_method_term(name, value, surface, exchange_id, path)}
        else
          :skip
        end

      _ ->
        :skip
    end
  end

  @spec build_method_term(String.t(), map(), surface(), String.t() | nil, String.t()) :: map()
  defp build_method_term(name, value, surface, exchange_id, path) do
    %{
      name: name,
      params: extract_params(value.params || []),
      return_type: extract_return_type(value.returnType),
      surface: surface,
      source: path,
      exchange_id: exchange_id
    }
  end

  # --- Signature extraction helpers (follow oxc.md shapes) --------------------

  @spec extract_params([map()]) :: [param()]
  defp extract_params(params) when is_list(params) do
    Enum.map(params, fn p ->
      name = Map.get(p, :name, "unknown")
      optional = Map.get(p, :optional, false)
      type_node = get_in(p, [:typeAnnotation, :typeAnnotation])

      %{
        name: name,
        type: render_type(type_node),
        optional: optional
      }
    end)
  end

  @spec extract_return_type(map() | nil) :: String.t()
  defp extract_return_type(nil), do: "void"

  defp extract_return_type(%{type: :ts_type_annotation, typeAnnotation: node}) do
    render_type(node)
  end

  defp extract_return_type(_), do: "any"

  @doc """
  Recursively renders a TypeScript type AST node (from OXC) back to a source-like
  string — e.g. `Promise<Ticker>`, `OHLCV[]`, `string | number`, `"limit"`.

  Used by the declaration parser to capture method param and return types in a
  form the macro layer (`defunified`) can pattern-match on. Unknown node kinds
  yield `"UNKNOWN(<kind>)"` so tests fail loudly rather than silently emitting
  the wrong type.
  """
  @spec render_type(map() | nil) :: String.t()
  def render_type(nil), do: "any"

  def render_type(%{type: :ts_string_keyword}), do: "string"
  def render_type(%{type: :ts_number_keyword}), do: "number"
  def render_type(%{type: :ts_boolean_keyword}), do: "boolean"
  def render_type(%{type: :ts_any_keyword}), do: "any"
  def render_type(%{type: :ts_unknown_keyword}), do: "unknown"
  def render_type(%{type: :ts_void_keyword}), do: "void"
  def render_type(%{type: :ts_null_keyword}), do: "null"
  def render_type(%{type: :ts_undefined_keyword}), do: "undefined"

  def render_type(%{type: :ts_type_reference} = node) do
    name = get_in(node, [:typeName, :name]) || "UnknownRef"
    args = get_in(node, [:typeArguments, :params]) || []

    if args == [] do
      name
    else
      rendered = Enum.map_join(args, ", ", &render_type/1)
      "#{name}<#{rendered}>"
    end
  end

  def render_type(%{type: :ts_type_literal}), do: "{}"

  def render_type(%{type: :ts_array_type, elementType: elem}) do
    "#{render_type(elem)}[]"
  end

  def render_type(%{type: :ts_union_type, types: types}) when is_list(types) do
    Enum.map_join(types, " | ", &render_type/1)
  end

  def render_type(%{type: :ts_literal_type, literal: lit}) do
    case lit do
      %{value: v} when is_binary(v) -> "\"#{v}\""
      %{value: v} -> inspect(v)
      _ -> "literal"
    end
  end

  def render_type(%{type: :ts_type_annotation, typeAnnotation: inner}) do
    render_type(inner)
  end

  def render_type(%{type: t}), do: "UNKNOWN(#{t})"
  def render_type(_), do: "any"

  # --- Filter (will be the single source of truth; BundleSurface delegates) ---

  @doc """
  Returns true for method names that belong to the public unified surface.

  Central predicate used by both the declaration parser and the legacy
  BundleSurface name extractor. Moving the lists here makes the "what gets a
  defunified wrapper" decision live in one place.
  """
  @spec public_unified_method?(String.t()) :: boolean()
  def public_unified_method?(name) do
    has_good_prefix = Enum.any?(@verb_prefixes, &String.starts_with?(name, &1))
    has_bad_prefix = Enum.any?(@internal_prefixes, &String.starts_with?(name, &1))
    in_allowlist = name in @additional_unified_methods
    in_denylist = name in @additional_denied

    (has_good_prefix or in_allowlist) and not has_bad_prefix and not in_denylist
  end

  # --- Helpers ----------------------------------------------------------------

  # Compile-time helper that maps a per-exchange .d.ts path (discovered by
  # `exchange_dts_paths/0`, never user input) to its exchange id atom.
  # Private so `String.to_atom/1` is not reachable from runtime code paths —
  # all current call sites are in this module and feed it the discovered .d.ts
  # paths directly. Use `known_exchange_ids/0` for the bounded id set if
  # something external needs the list.
  @spec exchange_id_from_path(String.t()) :: atom()
  defp exchange_id_from_path(path) do
    # Path.rootname("foo.d.ts") == "foo.d" — we must strip the .d.ts suffix explicitly.
    path
    |> Path.basename()
    |> Path.basename(".d.ts")
    |> String.to_atom()
  end

  @doc """
  Returns the sorted list of all known exchange ids (as atoms) derived purely
  from the on-disk per-exchange .d.ts files.

  Zero JS / zero bundle load. Used by the `use CcxtOcx` macro (Task 6b) for
  validation + suggestions. Also useful for docs and test fixtures.
  """
  @spec known_exchange_ids() :: [atom()]
  def known_exchange_ids do
    exchange_dts_paths()
    |> Enum.map(&exchange_id_from_path/1)
    |> Enum.sort()
  end

  # --- Layout guard ------------------------------------------------------------

  @required_smoke_methods ~w(fetchTicker createOrder watchTicker)

  @spec assert_required_methods!([method_term()]) :: :ok
  defp assert_required_methods!(terms) do
    present = MapSet.new(Enum.map(terms, & &1.name))

    missing = Enum.reject(@required_smoke_methods, &MapSet.member?(present, &1))

    if missing != [] do
      raise """
      CCXT declaration layout changed — required unified methods disappeared.

      Missing from :base surface (or filtered out):
        #{inspect(missing)}

      Expected them in:
        #{base_dts_path()}

      This is a deliberate loud failure (Task 6 acceptance).
      After a `mix npm.update ccxt`, review the diff and either:
        - pin a known-good version in package.json, or
        - run `mix ccxt.verify_bundle --accept` (after human review).

      If the methods genuinely moved to a different .d.ts, update the discovery
      globs in Declarations.Compile.
      """
    end

    # Each required smoke method MUST be primary :base from Exchange.d.ts.
    # `Enum.any?` would pass silently if e.g. createOrder moved to pro while
    # fetchTicker stayed on base — exactly the layout drift this guard exists
    # to catch.
    by_name = Map.new(terms, &{&1.name, &1})

    non_base =
      Enum.reject(@required_smoke_methods, fn name ->
        case Map.get(by_name, name) do
          %{primary: %{surface: :base, source: src}} -> String.ends_with?(src, "Exchange.d.ts")
          _ -> false
        end
      end)

    if non_base != [] do
      raise """
      CCXT declaration layout changed — required smoke methods are not primary :base
      from Exchange.d.ts.

      Not primary :base:
        #{inspect(non_base)}

      Expected each of #{inspect(@required_smoke_methods)} to be declared in:
        #{base_dts_path()}

      If CCXT genuinely reorganized these methods onto another surface, update the
      discovery globs in Declarations.Compile and the @required_smoke_methods list.
      """
    end

    :ok
  end

  # --- Task 8: interface introspection for typed struct drift guard ------------

  @types_dts "node_modules/ccxt/js/src/base/types.d.ts"

  @doc """
  Absolute path to the CCXT core types declaration (contains Ticker, OrderBook, Trade, etc.).
  """
  @spec types_dts_path() :: String.t()
  def types_dts_path do
    Path.join(File.cwd!(), @types_dts)
  end

  @doc """
  Parse the types.d.ts and return the field list for a named interface
  (e.g. "Ticker", "OrderBook", "Trade", "MarketInterface", "CurrencyInterface").

  Each field is `%{name: String.t(), type: String.t(), optional: boolean()}` using
  the same `render_type/1` as the method parser.
  """
  # sobelow_skip ["Traversal.FileModule"]
  @spec interface_fields(String.t()) :: [map()]
  def interface_fields(interface_name) when is_binary(interface_name) do
    path = types_dts_path()

    if !File.exists?(path) do
      raise "CCXT types.d.ts not found at #{path}. Run `mix npm.install`."
    end

    source = File.read!(path)

    ast =
      case OXC.parse(source, Path.basename(path)) do
        {:ok, a} -> a
        {:error, e} -> raise "OXC parse failed on types.d.ts: #{inspect(e)}"
      end

    collected =
      OXC.collect(ast, &collect_interface_fields(&1, interface_name))

    # collect_interface_fields returns {:keep, [field, ...]} for the matching interface
    fields = List.flatten(collected)
    Enum.sort_by(fields, & &1.name)
  end

  defp collect_interface_fields(node, wanted_name) do
    case node do
      %{type: :ts_interface_declaration, id: %{name: ^wanted_name}, body: %{body: members}} ->
        fields =
          for m <- members,
              key = get_in(m, [:key, :name]) || get_in(m, [:name]),
              not is_nil(key) do
            opt = Map.get(m, :optional, false) || (get_in(m, [:key, :optional]) || false)
            type_node = get_in(m, [:typeAnnotation, :typeAnnotation]) || get_in(m, [:typeAnnotation])

            %{
              name: key,
              type: render_type(type_node),
              optional: !!opt
            }
          end

        {:keep, fields}

      _ ->
        :skip
    end
  end

  # Public helper used by Task 8 tests to list the 6 core interfaces we care about.
  @core_struct_interfaces ~w(Ticker OrderBook Trade MarketInterface CurrencyInterface)

  @doc "The interface names in types.d.ts that back the v0.1 typed structs."
  @spec core_struct_interfaces() :: [String.t()]
  def core_struct_interfaces, do: @core_struct_interfaces
end
