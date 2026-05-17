defmodule CcxtOcx.Telemetry do
  @moduledoc """
  Canonical telemetry event definitions and thin wrappers for CcxtOcx.

  All events are emitted under the stable `[:ccxt_ocx]` prefix. This module is the
  single source of truth for event names, measurement shapes, and metadata
  conventions so that:

  - downstream consumers (PromEx, TelemetryMetrics, Datadog, custom handlers)
    can attach with zero glue,
  - future macro-generated wrappers (`defunified`, `defstreaming`) have a
    pre-agreed contract, and
  - Task 15 (memory monitoring) and Phase 3/4 work can emit without renaming risk.

  ## Event families

  ### REST (documented now, emitted by Phase 2 `defunified`)

      [:ccxt_ocx, :rest, :start]
      [:ccxt_ocx, :rest, :stop]
      [:ccxt_ocx, :rest, :exception]

  Emitted via `:telemetry.span/3`. Measurements include `duration` (stop/exception)
  and `system_time` (start). Metadata carries `exchange`, `method`, `signed`,
  `runtime`, `pool`, etc.

  ### WebSocket (documented now, emitted by Phase 3 `defstreaming`)

      [:ccxt_ocx, :ws, :tick]

  High-cardinality per-message event. `measurements` typically contain `count: 1`
  and optionally `size_bytes`. Metadata: `exchange`, `stream`, `type`.

  ### Runtime (implemented in Task 14)

      [:ccxt_ocx, :runtime, :memory]
      [:ccxt_ocx, :runtime, :start]   # reserved for runtime lifecycle (Task 15)
      [:ccxt_ocx, :runtime, :stop]    # reserved for runtime lifecycle (Task 15)

  `:memory` is emitted on-demand by `CcxtOcx.Runtime.memory/1` and
  `CcxtOcx.RuntimePool.memory/1`, plus once at the end of `Runtime.init/1`
  (baseline) and once in `Runtime.terminate/2` (final, best-effort).

  Metadata shape for `:memory`:

  - `%{server: pid()}` — explicit `Runtime.memory/1` call
  - `%{server: pid(), phase: :init | :terminate}` — lifecycle emit
  - `%{pool: pool_ref}` — `RuntimePool.memory/1` (pool_ref per `t:CcxtOcx.RuntimePool.pool/0`)

  Raw numbers are also available from `CcxtOcx.Runtime.memory_usage/1` (no event).

  ## Usage

      handler_id = {:ccxt_ocx, :my_handler}
      :telemetry.attach(handler_id, [:ccxt_ocx, :runtime, :memory], &MyHandler.handle/4, %{})
      ...
      :telemetry.detach(handler_id)

  Or use the higher-level wrappers from this module when emitting from inside CcxtOcx.
  """

  @prefix [:ccxt_ocx]

  # ------------------------------------------------------------------
  # Event name constants (prevents typos, enables @compile-time checks)
  # ------------------------------------------------------------------

  @rest_start @prefix ++ [:rest, :start]
  @rest_stop @prefix ++ [:rest, :stop]
  @rest_exception @prefix ++ [:rest, :exception]

  @ws_tick @prefix ++ [:ws, :tick]

  @runtime_memory @prefix ++ [:runtime, :memory]
  @runtime_start @prefix ++ [:runtime, :start]
  @runtime_stop @prefix ++ [:runtime, :stop]

  @doc "Returns the top-level event prefix used by all CcxtOcx telemetry."
  @spec prefix() :: [:ccxt_ocx]
  def prefix, do: @prefix

  # ------------------------------------------------------------------
  # Public emission helpers (used by Runtime, future macros, etc.)
  # ------------------------------------------------------------------

  @doc """
  Wraps `:telemetry.span/3` under the CcxtOcx prefix.

  Supports the convenient "return bare result" style (most common in our
  future macro call sites). When callers need custom stop metadata or
  measurements, return an explicitly tagged tuple:

      {:telemetry_span, result, stop_meta}
      {:telemetry_span, result, extra_meas, stop_meta}

  Callers pass only the suffix:

      CcxtOcx.Telemetry.span([:rest], meta, fn -> do_work() end)
  """
  @spec span(
          [atom()],
          :telemetry.event_metadata(),
          (-> result | {:telemetry_span, result, map()} | {:telemetry_span, result, map(), map()})
        ) :: result
        when result: var
  def span(suffix, meta, fun) when is_list(suffix) and is_function(fun, 0) do
    wrapped = fn ->
      case fun.() do
        {:telemetry_span, result, stop_meta} when is_map(stop_meta) ->
          {result, stop_meta}

        {:telemetry_span, result, extra, stop_meta} when is_map(extra) and is_map(stop_meta) ->
          {result, extra, stop_meta}

        result ->
          {result, %{}}
      end
    end

    :telemetry.span(@prefix ++ suffix, meta, wrapped)
  end

  @doc """
  Wraps `:telemetry.execute/3` under the CcxtOcx prefix.

  Callers pass only the suffix:

      CcxtOcx.Telemetry.execute([:runtime, :memory], measurements, meta)
  """
  @spec execute([atom()], :telemetry.event_measurements(), :telemetry.event_metadata()) :: :ok
  def execute(suffix, measurements, meta) when is_list(suffix) do
    :telemetry.execute(@prefix ++ suffix, measurements, meta)
  end

  # ------------------------------------------------------------------
  # Internal accessors for Runtime / Pool (kept small)
  # ------------------------------------------------------------------

  @doc false
  @spec __rest_start__() :: [:ccxt_ocx | :rest | :start, ...]
  def __rest_start__, do: @rest_start
  @doc false
  @spec __rest_stop__() :: [:ccxt_ocx | :rest | :stop, ...]
  def __rest_stop__, do: @rest_stop
  @doc false
  @spec __rest_exception__() :: [:ccxt_ocx | :rest | :exception, ...]
  def __rest_exception__, do: @rest_exception
  @doc false
  @spec __ws_tick__() :: [:ccxt_ocx | :ws | :tick, ...]
  def __ws_tick__, do: @ws_tick
  @doc false
  @spec __runtime_memory__() :: [:ccxt_ocx | :runtime | :memory, ...]
  def __runtime_memory__, do: @runtime_memory
  @doc false
  @spec __runtime_start__() :: [:ccxt_ocx | :runtime | :start, ...]
  def __runtime_start__, do: @runtime_start
  @doc false
  @spec __runtime_stop__() :: [:ccxt_ocx | :runtime | :stop, ...]
  def __runtime_stop__, do: @runtime_stop
end
