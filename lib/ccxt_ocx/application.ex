defmodule CcxtOcx.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  @spec start(Application.start_type(), term()) :: {:ok, pid()} | {:error, term()}
  def start(_type, _args) do
    opts = [strategy: :one_for_one, name: CcxtOcx.Supervisor]
    Supervisor.start_link(children(), opts)
  end

  @spec children() :: [Supervisor.child_spec() | {module(), term()}]
  defp children do
    if Application.get_env(:ccxt_ocx, :start_default_pool, true) do
      [{CcxtOcx.RuntimePool, name: CcxtOcx.RuntimePool.Default, size: pool_size()}]
    else
      []
    end
  end

  @spec pool_size() :: pos_integer()
  defp pool_size do
    Application.get_env(:ccxt_ocx, :pool_size, System.schedulers_online())
  end
end
