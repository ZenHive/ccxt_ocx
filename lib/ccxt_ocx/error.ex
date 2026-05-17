defmodule CcxtOcx.Error do
  @moduledoc """
  Canonical error taxonomy for CcxtOcx.

  Provides a single, stable `%CcxtOcx.Error{}` struct and a small set of
  functions for turning raw JS (QuickBEAM) errors from CCXT into a consistent
  Elixir shape that carries both a canonical semantic tag and rich context
  (`:exchange`, `:method`) for logging and higher-level handling.

  ## The closed 9-tag taxonomy

  All errors are reduced to one of these nine atoms:

      :bad_symbol | :network | :rate_limit | :auth | :not_found |
      :permission | :exchange | :timeout | :unknown

  The set is intentionally closed. New CCXT error subclasses are mapped into
  one of the existing tags (usually `:exchange` or `:network`). If a future
  semantic distinction is required at the public API level, it must be added
  via a spec change + new task, not by expanding the set during implementation.

  ## Source discriminator for Phase 7

  The struct carries two fields that future-proof the shape for native adapters:

      source: :js | :native | atom()
      source_name: String.t()

  Today (JS adapter via QuickBEAM):

      %CcxtOcx.Error{source: :js, source_name: "BadSymbol", ...}

  In Phase 7 (native Elixir REST/WS adapters for the venues that matter):

      %CcxtOcx.Error{source: :binance, source_name: "BNC-1100", ...}
      %CcxtOcx.Error{source: :okx, source_name: "51000", ...}

  Wrappers and callers pattern-match on `:tag` for control flow and only look
  at `:source`/`:source_name` when they need the original provenance (logs,
  metrics, retry heuristics, etc.).

  ## Primary API for wrapper authors

      # In a macro-generated or hand-written wrapper
      case CcxtOcx.Error.normalize(raw_js_error,
             exchange: :binance,
             method: "createOrder",
             meta: %{retries: 0}
           ) do
        %CcxtOcx.Error{tag: :rate_limit} -> ...
        %CcxtOcx.Error{tag: :auth}       -> ...
        err -> raise err
      end

  The three public functions have distinct roles:

    * `tag_for_ccxt_class/1` — pure mapper, used by the compile-time drift gate
      and by tests. Never injects context.

    * `from_js_error/2` — turns a raw JS error (map or `%QuickBEAM.JSError{}`)
      into a `%CcxtOcx.Error{}`. Accepts the same opts as `normalize/2`.

    * `normalize/2` — the main entry point called from wrappers. Accepts a
      tag atom (for manual construction), a raw JS error, or an already-built
      `%CcxtOcx.Error{}` and decorates it with `[:exchange, :method, :original, :meta]`.

  ## Compile-time drift gate

  The module declares:

      @external_resource "node_modules/ccxt/js/src/base/errors.d.ts"

  When that file is present at compile time (the npm-installed CCXT package
  used by OXC and future macro generators), a check runs that enumerates every
  concrete `declare class Foo extends Bar` entry and asserts that
  `@ccxt_to_tag` contains a mapping for it. Missing mappings cause compilation
  to fail with a clear message.

  This gate is active from day one so that adding support for a new CCXT error
  subclass is a deliberate, visible change rather than a silent fallback to
  `:unknown`.

  ## Exception behaviour

  `CcxtOcx.Error` implements the `Exception` behaviour, so you can do:

      raise CcxtOcx.Error.normalize(raw, exchange: :foo, method: "bar")

  and get a useful `message/1`.
  """

  @enforce_keys [:tag, :source, :source_name]
  defexception [
    :tag,
    :source,
    :source_name,
    :exchange,
    :method,
    original: nil,
    meta: %{}
  ]

  @type source :: :js | :native | atom()
  @type tag ::
          :bad_symbol
          | :network
          | :rate_limit
          | :auth
          | :not_found
          | :permission
          | :exchange
          | :timeout
          | :unknown

  @type t :: %__MODULE__{
          tag: tag(),
          source: source(),
          source_name: String.t(),
          exchange: atom() | nil,
          method: String.t() | nil,
          original: term() | nil,
          meta: map()
        }

  @tags [
    :bad_symbol,
    :network,
    :rate_limit,
    :auth,
    :not_found,
    :permission,
    :exchange,
    :timeout,
    :unknown
  ]

  @doc "The closed set of canonical error tags."
  @spec tags() :: [tag()]
  def tags, do: @tags

  # ------------------------------------------------------------------
  # CCXT class → canonical tag mapping
  #
  # This is the single source of truth for the JS adapter path.
  # When the full CCXT source tree is present, the compile-time gate below
  # verifies that every exported concrete error class has an entry here.
  # ------------------------------------------------------------------

  @ccxt_to_tag %{
    # Base classes — keep them so the gate is happy and fallbacks work
    "BaseError" => :unknown,
    "ExchangeError" => :exchange,
    "NetworkError" => :network,

    # Authentication / permission family
    "AuthenticationError" => :auth,
    "PermissionDenied" => :permission,
    "AccountSuspended" => :permission,
    "OperationNotAllowed" => :permission,

    # Symbol / request shaping
    "BadSymbol" => :bad_symbol,
    "BadRequest" => :exchange,
    "ArgumentsRequired" => :exchange,
    "InvalidAddress" => :exchange,
    "AddressPending" => :exchange,

    # Order lifecycle
    "InvalidOrder" => :exchange,
    "OrderNotFound" => :not_found,
    "OrderNotCached" => :not_found,
    "CancelPending" => :exchange,
    "OrderImmediatelyFillable" => :exchange,
    "OrderNotFillable" => :exchange,
    "DuplicateOrderId" => :exchange,

    # Funds / trading
    "InsufficientFunds" => :exchange,

    # Rate limiting
    "RateLimitExceeded" => :rate_limit,
    "DDoSProtection" => :rate_limit,

    # Operational / exchange-level
    "NotSupported" => :exchange,
    "ExchangeClosed" => :exchange,
    "ExchangeClosedByUser" => :exchange,
    "OnMaintenance" => :exchange,
    "FailedRequest" => :exchange,
    "OperationRejected" => :exchange,
    "OperationFailed" => :exchange,
    "InvalidProxySettings" => :exchange,
    "InvalidNonce" => :exchange,
    "MarginModeAlreadySet" => :exchange,
    "MarketClosed" => :exchange,
    "ManualInteractionNeeded" => :exchange,
    "NoChange" => :exchange,
    "ContractUnavailable" => :exchange,
    "ChecksumError" => :exchange,
    "UnsubscribeError" => :exchange,

    # Geo / account restriction (permission family per the moduledoc)
    "AccountNotEnabled" => :permission,
    "RestrictedLocation" => :permission,

    # Network / transport
    "RequestTimeout" => :timeout,
    "BadResponse" => :network,
    "NullResponse" => :network,
    "ExchangeNotAvailable" => :network
  }

  @doc """
  Returns the canonical tag for a CCXT error class name.

  Pure function. Used by the compile gate, tests, and `from_js_error/2`.

      iex> CcxtOcx.Error.tag_for_ccxt_class("BadSymbol")
      :bad_symbol

      iex> CcxtOcx.Error.tag_for_ccxt_class("RateLimitExceeded")
      :rate_limit

      iex> CcxtOcx.Error.tag_for_ccxt_class("SomeFutureError")
      :unknown
  """
  @spec tag_for_ccxt_class(String.t()) :: tag()
  def tag_for_ccxt_class(class_name) when is_binary(class_name) do
    Map.get(@ccxt_to_tag, class_name, :unknown)
  end

  # ------------------------------------------------------------------
  # Compile-time drift gate
  # ------------------------------------------------------------------

  @errors_dts_path "node_modules/ccxt/js/src/base/errors.d.ts"
  @external_resource @errors_dts_path

  # CCXT's .d.ts uses `declare class Foo extends Bar`; the public export list at
  # the bottom of the file is a single `export { ... }` block, so matching
  # `declare class` + `extends` captures every concrete subclass (and excludes
  # generated artifacts like `_default`). Single-sourced here so the
  # compile-time gate below and the test-callable `parse_ccxt_classes/1` use
  # the exact same pattern.
  @class_regex ~r/declare\s+class\s+(\w+)\s+extends\b/

  if File.exists?(@errors_dts_path) do
    content = File.read!(@errors_dts_path)

    classes =
      @class_regex
      |> Regex.scan(content)
      |> Enum.map(fn [_, name] -> name end)
      |> Enum.uniq()

    missing = classes -- Map.keys(@ccxt_to_tag)

    if missing != [] do
      raise CompileError,
        description: """
        CcxtOcx.Error is missing mappings for new CCXT error classes:

            #{inspect(missing)}

        Update @ccxt_to_tag in lib/ccxt_ocx/error.ex and add the appropriate
        canonical tag (or route the new class to :exchange / :network / :unknown).

        The gate exists so drift is caught at compile time rather than
        producing :unknown at runtime.
        """
    end
  end

  @doc false
  # Test-callable shim over the same regex the compile-time gate uses.
  # Lets tests assert the parser detects unmapped classes against synthetic
  # fixtures without having to corrupt the real errors.d.ts on disk.
  @spec parse_ccxt_classes(String.t()) :: [String.t()]
  def parse_ccxt_classes(content) when is_binary(content) do
    @class_regex
    |> Regex.scan(content)
    |> Enum.map(fn [_, name] -> name end)
    |> Enum.uniq()
  end

  @doc false
  # Test-callable accessor for @ccxt_to_tag. The gate's drift check compares
  # parser output against this map's keys; tests need the same view.
  @spec ccxt_to_tag_for_test() :: %{String.t() => tag()}
  def ccxt_to_tag_for_test, do: @ccxt_to_tag

  # ------------------------------------------------------------------
  # Construction helpers
  # ------------------------------------------------------------------

  @doc """
  Turns a raw JS error (from QuickBEAM) into a `%CcxtOcx.Error{}`.

  Accepts either a `%QuickBEAM.JSError{}` struct or a plain map with
  `"name"` / `:name` and `"message"` keys (the shape QuickBEAM returns for
  thrown objects).

  The second argument is the same keyword opts accepted by `normalize/2`:

      [:exchange, :method, :original, :meta]

  Use this when you already know you have a JS error and just want the
  struct. Most wrapper code should call `normalize/2` instead.
  """
  @spec from_js_error(QuickBEAM.JSError.t() | map() | term(), keyword()) :: t()
  def from_js_error(raw, opts \\ [])

  def from_js_error(%QuickBEAM.JSError{name: name} = js_err, opts) do
    # QuickBEAM.JSError's @type pins `name: String.t()` and its from_js_value/1
    # constructor force-coerces via to_string/1, so name should always be a
    # binary in practice. Coerce defensively anyway so a misuse-built struct
    # (e.g. `%QuickBEAM.JSError{name: :foo}` bypassing the constructor) lands
    # on :unknown instead of raising FunctionClauseError — same defensive shape
    # as the map clause below.
    safe_name = if is_binary(name), do: name, else: "Error"
    tag = tag_for_ccxt_class(safe_name)

    build_struct(tag, :js, safe_name, raw: js_err, opts: opts)
  end

  def from_js_error(%{} = raw, opts) when is_map(raw) do
    name =
      case Map.get(raw, "name") || Map.get(raw, :name) do
        n when is_binary(n) -> n
        # Non-binary (atom, number, list, …) or nil — fall back to the
        # synthetic "Error" sentinel so tag_for_ccxt_class/1 returns :unknown
        # instead of raising FunctionClauseError on its is_binary guard.
        _ -> "Error"
      end

    tag = tag_for_ccxt_class(name)

    build_struct(tag, :js, name, raw: raw, opts: opts)
  end

  def from_js_error(other, opts) do
    # Last-resort fallback — treat the whole thing as the original
    build_struct(:unknown, :js, "Error", raw: other, opts: opts)
  end

  @doc """
  Primary entry point for turning anything error-like into a `%CcxtOcx.Error{}`.

  `raw_or_tag` may be:

    * a CCXT class name string (e.g. `"BadSymbol"`)
    * a raw JS error map or `%QuickBEAM.JSError{}`
    * an already-constructed `%CcxtOcx.Error{}` (for re-decoration)
    * a canonical tag atom (for manual construction in tests or special paths)

  `opts` (all optional):

    * `:exchange` — atom exchange id (e.g. `:binance`)
    * `:method`   — string method name as seen by the caller (e.g. `"createOrder"`)
    * `:original` — the raw payload to keep for debugging
    * `:meta`     — arbitrary map for extra context (retry count, etc.)

  Examples:

      normalize("OrderNotFound", exchange: :okx, method: "cancelOrder")
      normalize(%{"name" => "RateLimitExceeded", ...}, exchange: :binance)
      normalize(%CcxtOcx.Error{...}, method: "fetchBalance")  # adds context
  """
  @spec normalize(atom() | String.t() | map() | t() | term(), keyword()) :: t()
  def normalize(raw_or_tag, opts \\ [])

  # Already an Error struct — just merge context
  def normalize(%__MODULE__{} = err, opts) do
    merge_context(err, opts)
  end

  # Direct tag atom (manual construction, mostly tests)
  def normalize(tag, opts) when is_atom(tag) and tag in @tags do
    build_struct(tag, :js, "tag:#{tag}", raw: nil, opts: opts)
  end

  # String that looks like a CCXT class name
  def normalize(class_name, opts) when is_binary(class_name) do
    if Map.has_key?(@ccxt_to_tag, class_name) or String.ends_with?(class_name, "Error") do
      tag = tag_for_ccxt_class(class_name)
      build_struct(tag, :js, class_name, raw: nil, opts: opts)
    else
      # Treat arbitrary strings as the original payload
      build_struct(:unknown, :js, "Error", raw: class_name, opts: opts)
    end
  end

  # Raw map or JSError — delegate to from_js_error
  def normalize(%{} = raw, opts) do
    from_js_error(raw, opts)
  end

  def normalize(other, opts) do
    build_struct(:unknown, :js, "Error", raw: other, opts: opts)
  end

  # ------------------------------------------------------------------
  # Exception behaviour
  # ------------------------------------------------------------------

  @impl true
  @spec exception(term()) :: t()
  def exception(term) do
    normalize(term)
  end

  @impl true
  @spec message(t()) :: String.t()
  def message(%__MODULE__{tag: tag, source: source, source_name: name, exchange: ex, method: m}) do
    base = "[#{tag}] #{source}:#{name}"

    ctx =
      case {ex, m} do
        {nil, nil} -> ""
        {ex, nil} -> " (#{ex})"
        {nil, m} -> " (#{m})"
        {ex, m} -> " (#{ex}.#{m})"
      end

    base <> ctx
  end

  # ------------------------------------------------------------------
  # Internal helpers
  # ------------------------------------------------------------------

  @spec build_struct(tag(), source(), String.t(), keyword()) :: t()
  defp build_struct(tag, source, source_name, raw: raw, opts: opts) do
    %__MODULE__{
      tag: tag,
      source: source,
      source_name: source_name,
      exchange: Keyword.get(opts, :exchange),
      method: Keyword.get(opts, :method),
      original: Keyword.get(opts, :original, raw),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  @spec merge_context(t(), keyword()) :: t()
  defp merge_context(%__MODULE__{} = err, opts) do
    %{
      err
      | exchange: Keyword.get(opts, :exchange, err.exchange),
        method: Keyword.get(opts, :method, err.method),
        original: Keyword.get(opts, :original, err.original),
        meta: Map.merge(err.meta, Keyword.get(opts, :meta, %{}))
    }
  end
end
