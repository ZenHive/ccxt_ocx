defmodule CcxtOcx.RuntimePool do
  @moduledoc """
  Supervised pool of long-lived `CcxtOcx.Runtime` workers.

  Each worker keeps its QuickBEAM runtime alive across calls, so the ~2s
  CCXT bundle eval is paid once per worker boot rather than once per
  `run/3` call. (Phase 1 benchmark — see the Task 3 plan — measured
  `QuickBEAM.Pool.run/3` at ~2s/call because reset re-evals the 5.3 MB
  bundle; long-lived workers serve at 0ms.)

  Built on top of `NimblePool` (same primitive Finch and Plug use) so the
  checkout queue, worker monitoring, and async worker init are battle-tested.
  This module wraps a NimblePool with a small GenServer that holds the
  cached diagnostic metadata (`ccxt_version`, `exchange_count`) probed at
  start-up.

  ## Public API

      {:ok, _pid} = CcxtOcx.RuntimePool.start_link(name: MyPool, size: 4)

      {:ok, "4.5." <> _} =
        CcxtOcx.RuntimePool.run(MyPool, fn rt ->
          QuickBEAM.eval(rt, "self.ccxt.version")
        end)

  `run/3` is the primary call path. Direct `checkout`/`checkin` is not
  exposed yet — Task 11 (streaming) and Task 16b (nonce hoisting) will add
  it on the `NimblePool.checkout!/4` foundation when they need it.

  ## Crash semantics

  NimblePool monitors each worker. A worker death is caught, the dead
  worker is replaced by `init_worker/1` (which spawns a new
  `CcxtOcx.Runtime` and re-loads the bundle), and the pool keeps serving.
  Bundle-reload cost is paid on crash, not per call. The wrapper GenServer
  is supervised by the top-level OTP supervision tree.
  """

  use GenServer

  alias CcxtOcx.RuntimePool.Worker

  @default_checkout_timeout to_timeout(minute: 1)
  @default_init_timeout to_timeout(minute: 2)
  @default_stop_timeout to_timeout(second: 30)

  @typedoc "Pool reference (registered name, via-tuple, or pid)."
  @type pool :: atom() | {:via, module(), term()} | pid()

  @typedoc "Function passed to `run/3` — receives the raw QuickBEAM pid."
  @type run_fun(result) :: (pid() -> result)

  @typedoc "Diagnostic snapshot of pool state."
  @type info :: %{
          size: pos_integer(),
          strategy: :long_lived,
          ccxt_version: String.t(),
          exchange_count: non_neg_integer()
        }

  # TODO(Task 9): promote the state + info maps into a `defstruct` once
  # per-exchange pools land and the shape stops moving — same reasoning
  # as the matching TODO in `CcxtOcx.Runtime`.

  ## Public API

  @doc """
  Start a pool.

  ## Options

    * `:name` — register the GenServer under a name (atom or `{:via, ...}`).
    * `:size` — number of workers. Defaults to `System.schedulers_online()`.
    * `:runtime_opts` — keyword list forwarded to each `CcxtOcx.Runtime.start_link/1`
      call (e.g. `[bundle_path: "..."]`).

  Bumps the GenServer init timeout to 2 minutes to allow parallel worker
  boot to complete.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = [timeout: @default_init_timeout]
    gen_opts = if name, do: Keyword.put(gen_opts, :name, name), else: gen_opts
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc "Stop the pool. Cascades worker termination via NimblePool."
  @spec stop(pool()) :: :ok
  def stop(pool), do: GenServer.stop(pool, :normal, @default_stop_timeout)

  @doc """
  Check out a worker, run `fun.(rt)` against its raw QuickBEAM handle,
  then check the worker back in.

  Returns the function's result, or `{:error, :checkout_timeout}` if no
  worker became available within `timeout` ms.
  """
  @spec run(pool(), run_fun(result), timeout()) :: result | {:error, :checkout_timeout}
        when result: term()
  def run(pool, fun, timeout \\ @default_checkout_timeout) when is_function(fun, 1) do
    np = GenServer.call(pool, :np)

    NimblePool.checkout!(
      np,
      :checkout,
      fn _from, server ->
        {fun.(CcxtOcx.Runtime.rt(server)), :ok}
      end,
      timeout
    )
  catch
    :exit, {:timeout, _} -> {:error, :checkout_timeout}
  end

  @doc "Return diagnostics about the pool."
  @spec info(pool()) :: info()
  def info(pool), do: GenServer.call(pool, :info)

  ## GenServer callbacks

  @impl GenServer
  @spec init(keyword()) :: {:ok, map()} | {:stop, term()}
  def init(opts) do
    size = Keyword.get(opts, :size) || System.schedulers_online()
    runtime_opts = Keyword.get(opts, :runtime_opts, [])

    # Trap exits during probe so a failing CcxtOcx.Runtime.start_link surfaces
    # as a structured init error instead of cascading through the link and
    # killing this process before the `with` else-clause can wrap the reason.
    Process.flag(:trap_exit, true)
    probe_result = probe_runtime(runtime_opts)
    Process.flag(:trap_exit, false)
    flush_exits()

    with {:ok, %{ccxt_version: version, exchange_count: count}} <- probe_result,
         {:ok, np} <-
           NimblePool.start_link(
             worker: {Worker, %{runtime_opts: runtime_opts}},
             pool_size: size,
             lazy: false
           ) do
      state = %{
        np: np,
        size: size,
        ccxt_version: version,
        exchange_count: count,
        runtime_opts: runtime_opts
      }

      {:ok, state}
    else
      {:error, {:probe_failed, reason}} -> {:stop, {:worker_init_failed, reason}}
      {:error, reason} -> {:stop, {:pool_init_failed, reason}}
    end
  end

  @spec flush_exits() :: :ok
  defp flush_exits do
    receive do
      {:EXIT, _pid, _reason} -> flush_exits()
    after
      0 -> :ok
    end
  end

  @impl GenServer
  @spec handle_call(:np | :info, GenServer.from(), map()) ::
          {:reply, pid() | info(), map()}
  def handle_call(:np, _from, state), do: {:reply, state.np, state}

  def handle_call(:info, _from, state) do
    info = %{
      size: state.size,
      strategy: :long_lived,
      ccxt_version: state.ccxt_version,
      exchange_count: state.exchange_count
    }

    {:reply, info, state}
  end

  @impl GenServer
  @spec handle_info(term(), map()) :: {:noreply, map()}
  def handle_info(_msg, state), do: {:noreply, state}

  @impl GenServer
  @spec terminate(term(), map()) :: :ok
  def terminate(_reason, %{np: np}) do
    if Process.alive?(np) do
      Process.unlink(np)

      try do
        NimblePool.stop(np, :shutdown, @default_stop_timeout)
      catch
        :exit, _ -> :ok
      end
    end

    :ok
  end

  def terminate(_reason, _state), do: :ok

  ## Helpers

  # Boots one runtime synchronously to surface structured init errors
  # (e.g. `{:bundle_missing, _}`) before NimblePool spawns its workers.
  # Also captures the diagnostic metadata so `info/1` doesn't need to
  # check out a worker.
  @spec probe_runtime(keyword()) :: {:ok, CcxtOcx.Runtime.info()} | {:error, {:probe_failed, term()}}
  defp probe_runtime(runtime_opts) do
    case CcxtOcx.Runtime.start_link(runtime_opts) do
      {:ok, probe} ->
        info = CcxtOcx.Runtime.info(probe)
        CcxtOcx.Runtime.stop(probe)
        {:ok, info}

      {:error, reason} ->
        {:error, {:probe_failed, reason}}
    end
  end
end
