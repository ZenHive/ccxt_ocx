defmodule CcxtOcx.Runtime do
  @moduledoc """
  GenServer that owns one QuickBEAM runtime with the ccxt browser bundle pre-loaded.

  This is the foundation handle every macro-generated wrapper sits on top of.
  The GenServer's job is lifecycle (start, stub, load, terminate); it does NOT
  proxy every JS call — `eval/3`, `call/4`, and `with_runtime/2` fetch the raw
  QuickBEAM handle once and dispatch directly, so call-path latency is the
  same as calling QuickBEAM yourself.

  ## What init does

  1. Starts a QuickBEAM runtime with `:browser` APIs.
  2. Applies the browser stubs ccxt's webpack bundle expects:
     - `globalThis.self = globalThis; globalThis.window = globalThis;` (must be
       set via `eval/3` — `set_global/3` with an atom would coerce to a string).
     - `navigator` with a `userAgent` field.
     - `location` with `protocol` and `host`.
  3. Reads `node_modules/ccxt/dist/ccxt.browser.min.js` (5.2 MB webpack UMD)
     and evaluates it.
  4. Captures `self.ccxt.version` and `self.ccxt.default.exchanges.length` for
     diagnostics.

  ## ccxt object shape gotcha

  The browser bundle exposes ccxt at two paths with different types:

      self.ccxt.exchanges          # Object  — keys are exchange ids
      self.ccxt.default.exchanges  # Array   — list of exchange ids

  This module assumes `default.exchanges` is the Array and pins that
  invariant in the test suite. If a future ccxt release reshuffles, the test
  fails loudly rather than corrupting downstream consumers.

  ## Caller-crash isolation

  The runtime is owned by this GenServer, not linked to ad-hoc callers. A
  caller crashing mid-`with_runtime/2` does not affect the runtime — standard
  GenServer.call semantics. JS-side timeouts (`QuickBEAM.eval(rt, src, timeout: ...)`)
  also leave the runtime usable.

  ## Configuration

  Bundle path resolution:

      :bundle_path opt → Application.get_env(:ccxt_ocx, :bundle_path) →
      "node_modules/ccxt/dist/ccxt.browser.min.js"

  Relative paths resolve against `File.cwd!/0`.
  """

  use GenServer

  @default_bundle_path "node_modules/ccxt/dist/ccxt.browser.min.js"
  @default_load_timeout to_timeout(second: 30)

  @typedoc "Diagnostic snapshot of the loaded runtime."
  @type info :: %{
          ccxt_version: String.t(),
          exchange_count: non_neg_integer(),
          bundle_path: String.t()
        }

  # TODO(Task 3): promote the state map + info return into a `defstruct` once
  # RuntimePool adds more fields — sobelow's struct hint is right but it's not
  # worth the churn while the shape is still settling.

  ## Public API

  @doc """
  Start a runtime, apply browser stubs, and load the ccxt bundle.

  ## Options

    * `:name` — register the GenServer under a name (atom or `{:via, ...}`).
    * `:bundle_path` — override the ccxt bundle path. Defaults to
      `Application.get_env(:ccxt_ocx, :bundle_path)` then
      `"node_modules/ccxt/dist/ccxt.browser.min.js"`.
    * `:apis` — passed through to `QuickBEAM.start/1`. Defaults to `:browser`.
    * `:memory_limit` — passed through.
    * `:max_stack_size` — passed through (QuickBEAM 0.10 default is 8 MB).
    * `:load_timeout` — bundle eval timeout in milliseconds. Defaults to 30_000.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc "Stop the runtime and free the underlying QuickBEAM resources."
  @spec stop(GenServer.server()) :: :ok
  def stop(server), do: GenServer.stop(server)

  @doc """
  Return the raw QuickBEAM runtime handle.

  Useful when you need a QuickBEAM API not exposed here (e.g. `set_global/3`,
  `info/1`, `memory_usage/1`).
  """
  @spec rt(GenServer.server()) :: pid()
  def rt(server), do: GenServer.call(server, :rt)

  @doc """
  Evaluate JavaScript source in the runtime.

  Thin wrapper around `QuickBEAM.eval/3` — accepts the same options
  (`:vars`, `:timeout`).
  """
  @spec eval(GenServer.server(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def eval(server, source, opts \\ []) when is_binary(source) do
    QuickBEAM.eval(rt(server), source, opts)
  end

  @doc """
  Call a JavaScript global function by name.

  Thin wrapper around `QuickBEAM.call/4`.
  """
  @spec call(GenServer.server(), String.t(), [term()], keyword()) ::
          {:ok, term()} | {:error, term()}
  def call(server, fn_name, args \\ [], opts \\ []) when is_binary(fn_name) and is_list(args) do
    QuickBEAM.call(rt(server), fn_name, args, opts)
  end

  @doc """
  Hand the raw QuickBEAM runtime handle to `fun` and return its result.

  Lets callers compose multi-step QuickBEAM operations without paying the
  GenServer hop on every call.
  """
  @spec with_runtime(GenServer.server(), (pid() -> result)) :: result when result: var
  def with_runtime(server, fun) when is_function(fun, 1) do
    fun.(rt(server))
  end

  @doc "Return diagnostics about the loaded runtime."
  @spec info(GenServer.server()) :: info()
  def info(server), do: GenServer.call(server, :info)

  ## Callbacks

  @impl true
  @spec init(keyword()) :: {:ok, map()} | {:stop, term()}
  def init(opts) do
    bundle_path = resolve_bundle_path(Keyword.get(opts, :bundle_path))
    load_timeout = Keyword.get(opts, :load_timeout, @default_load_timeout)

    qb_opts =
      opts
      |> Keyword.take([:apis, :memory_limit, :max_stack_size, :max_convert_depth, :max_convert_nodes])
      |> Keyword.put_new(:apis, :browser)

    with {:ok, rt} <- QuickBEAM.start(qb_opts),
         :ok <- apply_browser_stubs(rt),
         {:ok, bundle} <- read_bundle(bundle_path),
         :ok <- load_bundle(rt, bundle, load_timeout),
         {:ok, version} <- QuickBEAM.eval(rt, "self.ccxt.version"),
         {:ok, count} <- QuickBEAM.eval(rt, "self.ccxt.default.exchanges.length") do
      state = %{
        rt: rt,
        bundle_path: bundle_path,
        ccxt_version: version,
        exchange_count: count
      }

      {:ok, state}
    else
      {:error, reason} ->
        {:stop, reason}

      # TODO(Task 4): the remaining defensive catch-all is now only for shape
      # changes in helper return values. Real JS errors from QuickBEAM are
      # normalized via CcxtOcx.Error at the adapter/wrapper layer.
      other ->
        {:stop, {:unexpected_init_result, other}}
    end
  end

  @impl true
  def handle_call(:rt, _from, %{rt: rt} = state), do: {:reply, rt, state}

  def handle_call(:info, _from, state) do
    info = %{
      ccxt_version: state.ccxt_version,
      exchange_count: state.exchange_count,
      bundle_path: state.bundle_path
    }

    {:reply, info, state}
  end

  @impl true
  @spec terminate(term(), map()) :: :ok
  def terminate(_reason, %{rt: rt}) when is_pid(rt) do
    if Process.alive?(rt), do: QuickBEAM.stop(rt)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  ## Helpers

  @spec resolve_bundle_path(String.t() | nil) :: String.t()
  defp resolve_bundle_path(nil) do
    configured = Application.get_env(:ccxt_ocx, :bundle_path, @default_bundle_path)
    expand_relative(configured)
  end

  defp resolve_bundle_path(path) when is_binary(path), do: expand_relative(path)

  @spec expand_relative(String.t()) :: String.t()
  defp expand_relative(path) do
    if Path.type(path) == :absolute, do: path, else: Path.join(File.cwd!(), path)
  end

  @spec apply_browser_stubs(pid()) :: :ok | {:error, term()}
  defp apply_browser_stubs(rt) do
    with {:ok, _} <-
           QuickBEAM.eval(rt, "globalThis.self = globalThis; globalThis.window = globalThis;"),
         :ok <- QuickBEAM.set_global(rt, "navigator", %{"userAgent" => "QuickBEAM/CcxtOcx"}) do
      QuickBEAM.set_global(rt, "location", %{
        "protocol" => "https:",
        "host" => "ccxt-ocx.local"
      })
    end
  end

  @spec read_bundle(String.t()) :: {:ok, binary()} | {:error, {:bundle_missing, String.t()}}
  # sobelow_skip ["Traversal.FileModule"]
  # Path comes from operator config (:bundle_path opt / app env / hardcoded default),
  # not from external input.
  defp read_bundle(path) do
    case File.read(path) do
      {:ok, contents} -> {:ok, contents}
      {:error, reason} -> {:error, {:bundle_missing, "#{path}: #{:file.format_error(reason)}"}}
    end
  end

  @spec load_bundle(pid(), binary(), pos_integer()) :: :ok | {:error, term()}
  defp load_bundle(rt, bundle, timeout) do
    case QuickBEAM.call(rt, "eval", [bundle], timeout: timeout) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:bundle_load_failed, reason}}
    end
  end
end
