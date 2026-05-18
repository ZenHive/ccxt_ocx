defmodule CcxtOcx.Macros.Exchange do
  @moduledoc """
  Implementation of the `defexchange` macro (Task 9, v0.1).

  This macro is invoked from inside the per-exchange modules emitted by
  `use CcxtOcx` (see `CcxtOcx.__using__/1`). It is the single place that
  materializes the compile-time capability snapshot for one venue.

  It consumes `CcxtOcx.Macros.ExchangeCaps.fetch_or_build/1` (which either
  hits the `priv/exchange_caps/<id>.exs` cache or runs a throwaway QuickBEAM
  probe) and emits:

    * `@has_table` + `has?/1` (and `has_table/0`) — the raw CCXT `has` map
      for capability-gated emission in Task 7 (`defunified`)
    * `urls/0`, `timeframes/0`, `rate_limit/0`, `default_type/0`, `version/0`
    * `caps/0` (raw map) and `exchange/0` (populated struct)
    * A nested `Exchange` struct type for first-class descriptor values
    * `@external_resource` so cache refreshes via the verify pipeline force
      recompilation of every consumer

  The macro runs at the compile time of any module that does `use CcxtOcx`.
  Only exchanges that were explicitly declared pay the (cached) cost.

  ## Dogfooding evidence (2026-05-21, Tidewave)
  Verified on :binance, :deribit, :okx that the caps contain both method flags
  (`fetchOptionChain`, `createOrder`) and market-type flags (`option`, `swap`,
  `spot`, `future`) and that the Deribit options surface is fully captured.
  See session transcript for the exact `project_eval` calls.
  """

  alias CcxtOcx.Macros.ExchangeCaps

  @doc """
  Emits the full per-exchange capability surface for the given CCXT exchange id.

  Must be called inside a `defmodule CcxtOcx.<Camel>` that was created by the
  `use CcxtOcx` expansion. The call performs the (cached) probe if the caps
  file for `id` does not yet exist.

  ## Example (generated code, not written by hand)

      defmodule CcxtOcx.Binance do
        def __exchange_id__, do: :binance
        require CcxtOcx.Macros.Exchange
        CcxtOcx.Macros.Exchange.defexchange(:binance)
      end
  """
  @spec defexchange(atom()) :: Macro.t()
  defmacro defexchange(id) when is_atom(id) do
    caps = ExchangeCaps.fetch_or_build(id)

    data = %{
      has: caps.has || %{},
      urls: caps.urls || %{},
      timeframes: caps.timeframes || %{},
      rate_limit: caps.rate_limit,
      default_type: caps.default_type,
      version: caps.version,
      caps_path: ExchangeCaps.caps_path(id)
    }

    emit_surface(data)
  end

  # --- Emission helpers (extracted to keep defexchange cyclomatic complexity low) ---

  defp emit_surface(data) do
    quote do
      # Recompile this generated module when the caps cache for this exchange changes
      # (e.g. after `mix ccxt.verify_bundle --accept` that refreshes the file).
      @external_resource unquote(data.caps_path)

      # Materialized for O(1) lookup and for Task 7's compile-time gating.
      # Using Macro.escape so large maps (100+ entries) stay as literals in the AST.
      @has_table unquote(Macro.escape(data.has))

      unquote(emit_has_functions(data.has))
      unquote(emit_accessor(:urls, data.urls))
      unquote(emit_accessor(:timeframes, data.timeframes))
      unquote(emit_simple_accessor(:rate_limit, data.rate_limit))
      unquote(emit_simple_accessor(:default_type, data.default_type))
      unquote(emit_simple_accessor(:version, data.version))

      unquote(emit_caps_function())
      unquote(emit_struct_module())
      unquote(emit_exchange_function())
    end
  end

  defp emit_has_functions(_has_map) do
    quote do
      @doc """
      Returns true when this exchange reports support for the given CCXT method
      or market type.

      The lookup is **exact** against CCXT's raw camelCase keys (`"fetchTicker"`,
      `"createOrder"`, `"option"`). Pass the CCXT key as a binary — atoms are
      rejected at the type level to avoid the snake_case-vs-camelCase trap (the
      generated wrapper functions, e.g. `Binance.fetch_ticker/N`, handle the
      camelCase→snake_case mapping at their layer).

      `"emulated"` entries are treated as supported (truthy). Unknown keys return false.
      """
      @spec has?(binary()) :: boolean()
      def has?(key) when is_binary(key) do
        case Map.get(@has_table, key) do
          nil -> false
          false -> false
          _ -> true
        end
      end

      @doc "Returns the raw `has` table (map of CCXT camelCase key → true | \"emulated\" | false)."
      @spec has_table() :: %{optional(binary()) => true | binary() | false}
      def has_table, do: @has_table
    end
  end

  defp emit_accessor(name, value) when is_atom(name) do
    doc =
      case name do
        :urls -> "CCXT `urls` metadata (api, doc, fees, test, www, …)."
        :timeframes -> "Supported timeframes (map of human label → CCXT value)."
      end

    escaped = Macro.escape(value)

    quote do
      @doc unquote(doc)
      @spec unquote(name)() :: map()
      def unquote(name)(), do: unquote(escaped)
    end
  end

  defp emit_simple_accessor(name, value) when is_atom(name) do
    {doc, spec} =
      case name do
        :rate_limit ->
          {"Rate limit in ms (or nil if not advertised).", quote(do: pos_integer() | nil)}

        :default_type ->
          {"`options.defaultType` at the time the snapshot was captured (or nil).", quote(do: binary() | nil)}

        :version ->
          {"Exchange version string reported by the CCXT class (or nil).", quote(do: binary() | nil)}
      end

    quote do
      @doc unquote(doc)
      @spec unquote(name)() :: unquote(spec)
      def unquote(name)(), do: unquote(value)
    end
  end

  defp emit_caps_function do
    quote do
      @doc "The full capability snapshot as a plain map (identical to the cached .exs term)."
      @spec caps() :: map()
      def caps do
        %{
          id: __exchange_id__(),
          has: has_table(),
          urls: urls(),
          timeframes: timeframes(),
          rate_limit: rate_limit(),
          default_type: default_type(),
          version: version()
        }
      end
    end
  end

  defp emit_struct_module do
    quote do
      # --- Struct descriptor ---------------------------------------------------

      defmodule Exchange do
        @moduledoc """
        First-class struct descriptor for a single exchange's compile-time
        capability snapshot.

        Produced by `CcxtOcx.<Camel>.exchange/0`. Useful when you need a value
        (pattern matching, passing to helpers, future descriptor pipelines)
        rather than calling the module functions directly.
        """

        @enforce_keys [:id]
        defstruct [:id, :has, :urls, :timeframes, :rate_limit, :default_type, :version]

        @type t :: %__MODULE__{
                id: atom(),
                has: %{optional(binary()) => true | binary() | false},
                urls: map(),
                timeframes: map(),
                rate_limit: pos_integer() | nil,
                default_type: binary() | nil,
                version: binary() | nil
              }
      end
    end
  end

  defp emit_exchange_function do
    quote do
      @doc "Returns a populated `%#{inspect(__MODULE__)}.Exchange{}` struct for this exchange."
      @spec exchange() :: Exchange.t()
      def exchange do
        %Exchange{
          id: __exchange_id__(),
          has: has_table(),
          urls: urls(),
          timeframes: timeframes(),
          rate_limit: rate_limit(),
          default_type: default_type(),
          version: version()
        }
      end
    end
  end
end
