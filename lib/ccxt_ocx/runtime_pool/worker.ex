defmodule CcxtOcx.RuntimePool.Worker do
  @moduledoc false

  @behaviour NimblePool

  @impl NimblePool
  @spec init_worker(map()) :: {:async, (-> pid()), map()}
  def init_worker(%{runtime_opts: runtime_opts} = pool_state) do
    fun = fn ->
      case CcxtOcx.Runtime.start_link(runtime_opts) do
        {:ok, server} ->
          server

        {:error, reason} ->
          raise "CcxtOcx.Runtime init failed: #{inspect(reason)}"
      end
    end

    {:async, fun, pool_state}
  end

  @impl NimblePool
  @spec handle_checkout(:checkout, GenServer.from(), pid(), map()) ::
          {:ok, pid(), pid(), map()} | {:remove, atom(), map()}
  def handle_checkout(:checkout, _from, server, pool_state) do
    if Process.alive?(server) do
      {:ok, server, server, pool_state}
    else
      {:remove, :dead_worker, pool_state}
    end
  end

  @impl NimblePool
  @spec terminate_worker(term(), pid(), map()) :: {:ok, map()}
  def terminate_worker(_reason, server, pool_state) do
    if Process.alive?(server) do
      try do
        CcxtOcx.Runtime.stop(server)
      catch
        :exit, _ -> :ok
      end
    end

    {:ok, pool_state}
  end
end
