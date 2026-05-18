if Code.ensure_loaded?(PromEx.Plugin) do
  defmodule CcxtOcx.PromEx.Plugin do
    @moduledoc """
    Ship-with-the-library [PromEx](https://hex.pm/packages/prom_ex) plugin for
    the `[:ccxt_ocx, ...]` telemetry event family.

    Consumers add `{:prom_ex, "~> 1.11"}` to their app's deps, then reference
    this module in their PromEx config:

        defmodule MyApp.PromEx do
          use PromEx, otp_app: :my_app

          @impl true
          def plugins do
            [
              PromEx.Plugins.Application,
              PromEx.Plugins.Beam,
              # Optional :pool / :poll_rate opts enable periodic pool memory snapshots.
              {CcxtOcx.PromEx.Plugin, pool: MyApp.CcxtPool, poll_rate: 10_000}
            ]
          end
        end

    PromEx is declared as an **optional** dependency of `:ccxt_ocx`. This
    module is wrapped in `Code.ensure_loaded?(PromEx.Plugin)` so that
    consumer projects without `:prom_ex` in their own deps can still
    compile `:ccxt_ocx` — the module simply isn't defined when PromEx is
    absent.

    ## Provided metrics

    ### Event-based (always on)

    Backed by `[:ccxt_ocx, :runtime, :memory]` — emitted from
    `CcxtOcx.Runtime.memory/1`, runtime init/terminate, and
    `CcxtOcx.RuntimePool.memory/1`:

      * `ccxt_ocx_runtime_memory_malloc_size_bytes` (last_value)
      * `ccxt_ocx_runtime_memory_used_size_bytes`   (last_value)
      * `ccxt_ocx_runtime_memory_obj_count`         (last_value)

    Backed by `[:ccxt_ocx, :rest, :stop | :exception]` — reserved for
    Phase 2 `defunified` (Task 7); the metric definitions exist now so
    dashboards stay stable when emission lights up:

      * `ccxt_ocx_rest_duration_milliseconds` (distribution)
      * `ccxt_ocx_rest_total`                 (counter)
      * `ccxt_ocx_rest_exceptions_total`      (counter)

    Backed by `[:ccxt_ocx, :ws, :tick]` — reserved for Phase 3
    `defstreaming` (Task 11):

      * `ccxt_ocx_ws_ticks_total` (counter)

    ### Polling (opt-in)

    When the plugin is configured with `pool: <pool_name>`, a periodic
    timer calls `CcxtOcx.RuntimePool.memory/1` every `:poll_rate`
    milliseconds (default 5_000). Each call emits a fresh
    `[:ccxt_ocx, :runtime, :memory]` event captured by the event metrics
    above. No additional metric definitions — polling here is purely a
    driver, not a separate metric stream.

    ## Tag stability

    All tag values are normalized through `tag_values/1` callbacks so that
    Prometheus labels stay consistent across emission sites. Missing
    metadata keys become `"none"`, runtime PIDs are inspected (`#PID<…>`),
    and exceptions are normalized to `:kind` (`:error | :exit | :throw`).
    """

    use PromEx.Plugin

    alias CcxtOcx.Telemetry, as: T

    @impl true
    def event_metrics(_opts) do
      [
        runtime_event_metrics(),
        rest_event_metrics(),
        ws_event_metrics()
      ]
    end

    @impl true
    def polling_metrics(opts) do
      case Keyword.fetch(opts, :pool) do
        {:ok, pool} ->
          poll_rate = Keyword.get(opts, :poll_rate, 5_000)

          [
            Polling.build(
              :ccxt_ocx_runtime_pool_memory_polling_metrics,
              poll_rate,
              {CcxtOcx.RuntimePool, :memory, [pool]},
              []
            )
          ]

        :error ->
          []
      end
    end

    ## ------------------------------------------------------------------
    ## Event-group builders
    ## ------------------------------------------------------------------

    @spec runtime_event_metrics() :: Event.t()
    defp runtime_event_metrics do
      memory_event = T._runtime_memory()
      memory_tags = [:server, :pool, :phase]
      memory_tag_values = &normalize_memory_metadata/1

      Event.build(:ccxt_ocx_runtime_event_metrics, [
        last_value(
          [:ccxt_ocx, :runtime, :memory, :malloc_size, :bytes],
          event_name: memory_event,
          measurement: :malloc_size,
          description: "QuickJS malloc size for a ccxt_ocx runtime.",
          tags: memory_tags,
          tag_values: memory_tag_values,
          unit: :byte
        ),
        last_value(
          [:ccxt_ocx, :runtime, :memory, :used_size, :bytes],
          event_name: memory_event,
          measurement: :memory_used_size,
          description: "QuickJS used memory for a ccxt_ocx runtime.",
          tags: memory_tags,
          tag_values: memory_tag_values,
          unit: :byte
        ),
        last_value(
          [:ccxt_ocx, :runtime, :memory, :obj_count],
          event_name: memory_event,
          measurement: :obj_count,
          description: "QuickJS live object count for a ccxt_ocx runtime.",
          tags: memory_tags,
          tag_values: memory_tag_values
        )
      ])
    end

    @spec rest_event_metrics() :: Event.t()
    defp rest_event_metrics do
      stop_event = T._rest_stop()
      exception_event = T._rest_exception()
      rest_tags = [:exchange, :method]
      rest_tag_values = &normalize_rest_metadata/1
      exception_tags = [:exchange, :method, :kind]
      exception_tag_values = &normalize_rest_exception_metadata/1

      Event.build(:ccxt_ocx_rest_event_metrics, [
        distribution(
          [:ccxt_ocx, :rest, :duration, :milliseconds],
          event_name: stop_event,
          measurement: :duration,
          description: "CCXT REST call duration.",
          tags: rest_tags,
          tag_values: rest_tag_values,
          unit: {:native, :millisecond},
          reporter_options: [buckets: [10, 50, 100, 250, 500, 1000, 5000]]
        ),
        counter(
          [:ccxt_ocx, :rest, :total],
          event_name: stop_event,
          description: "CCXT REST call count.",
          tags: rest_tags,
          tag_values: rest_tag_values
        ),
        counter(
          [:ccxt_ocx, :rest, :exceptions, :total],
          event_name: exception_event,
          description: "CCXT REST call exception count.",
          tags: exception_tags,
          tag_values: exception_tag_values
        )
      ])
    end

    @spec ws_event_metrics() :: Event.t()
    defp ws_event_metrics do
      tick_event = T._ws_tick()

      Event.build(:ccxt_ocx_ws_event_metrics, [
        counter(
          [:ccxt_ocx, :ws, :ticks, :total],
          event_name: tick_event,
          description: "CCXT WebSocket inbound message count.",
          tags: [:exchange, :stream, :type],
          tag_values: &normalize_ws_tick_metadata/1
        )
      ])
    end

    ## ------------------------------------------------------------------
    ## Tag-value normalizers
    ## ------------------------------------------------------------------

    @spec normalize_memory_metadata(:telemetry.event_metadata()) :: %{
            server: String.t(),
            pool: String.t(),
            phase: String.t()
          }
    defp normalize_memory_metadata(metadata) do
      %{
        server: stringify(Map.get(metadata, :server)),
        pool: stringify(Map.get(metadata, :pool)),
        phase: stringify(Map.get(metadata, :phase))
      }
    end

    @spec normalize_rest_metadata(:telemetry.event_metadata()) :: %{
            exchange: String.t(),
            method: String.t()
          }
    defp normalize_rest_metadata(metadata) do
      %{
        exchange: stringify(Map.get(metadata, :exchange)),
        method: stringify(Map.get(metadata, :method))
      }
    end

    @spec normalize_rest_exception_metadata(:telemetry.event_metadata()) :: %{
            exchange: String.t(),
            method: String.t(),
            kind: String.t()
          }
    defp normalize_rest_exception_metadata(metadata) do
      %{
        exchange: stringify(Map.get(metadata, :exchange)),
        method: stringify(Map.get(metadata, :method)),
        kind: stringify(Map.get(metadata, :kind))
      }
    end

    @spec normalize_ws_tick_metadata(:telemetry.event_metadata()) :: %{
            exchange: String.t(),
            stream: String.t(),
            type: String.t()
          }
    defp normalize_ws_tick_metadata(metadata) do
      %{
        exchange: stringify(Map.get(metadata, :exchange)),
        stream: stringify(Map.get(metadata, :stream)),
        type: stringify(Map.get(metadata, :type))
      }
    end

    @spec stringify(term()) :: String.t()
    defp stringify(nil), do: "none"
    defp stringify(value) when is_binary(value), do: value
    defp stringify(value) when is_atom(value), do: Atom.to_string(value)
    defp stringify(value), do: inspect(value)
  end
end
