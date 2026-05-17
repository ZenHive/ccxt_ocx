defmodule CcxtOcx.RuntimePoolTest do
  # Native QuickBEAM runtimes — can't run async.
  use ExUnit.Case, async: false

  @bundle_path "node_modules/ccxt/dist/ccxt.browser.min.js"

  setup_all do
    if !File.exists?(@bundle_path) do
      flunk("""
      ccxt browser bundle not found at #{@bundle_path}.

      Install ccxt before running these tests:
        npm install
      """)
    end

    {:ok, shared} = CcxtOcx.RuntimePool.start_link(size: 2)
    on_exit(fn -> if Process.alive?(shared), do: CcxtOcx.RuntimePool.stop(shared) end)
    {:ok, shared: shared}
  end

  describe "lifecycle" do
    test "start_link/1 boots a pool with metadata cached at init", %{shared: pool} do
      info = CcxtOcx.RuntimePool.info(pool)
      assert info.size == 2
      assert info.strategy == :long_lived
      assert is_binary(info.ccxt_version)
      assert info.exchange_count > 100
    end

    test "info/1 ccxt fields match CcxtOcx.Runtime.info/1 for a fresh runtime", %{shared: pool} do
      {:ok, server} = CcxtOcx.Runtime.start_link([])
      on_exit(fn -> if Process.alive?(server), do: CcxtOcx.Runtime.stop(server) end)
      runtime_info = CcxtOcx.Runtime.info(server)
      pool_info = CcxtOcx.RuntimePool.info(pool)

      assert pool_info.ccxt_version == runtime_info.ccxt_version
      assert pool_info.exchange_count == runtime_info.exchange_count
    end

    test "stop/1 terminates the inner NimblePool" do
      {:ok, pool} = CcxtOcx.RuntimePool.start_link(size: 1)
      np = :sys.get_state(pool).np
      assert Process.alive?(np)
      :ok = CcxtOcx.RuntimePool.stop(pool)
      refute Process.alive?(np)
    end

    test "start_link/1 with bogus bundle path surfaces structured init error" do
      Process.flag(:trap_exit, true)
      bogus = Path.join(System.tmp_dir!(), "ccxt-#{System.unique_integer([:positive])}.js")

      assert {:error, {:worker_init_failed, {:bundle_missing, msg}}} =
               CcxtOcx.RuntimePool.start_link(size: 1, runtime_opts: [bundle_path: bogus])

      assert msg =~ bogus
    end

    test "start_link/1 rejects invalid :size at the API boundary" do
      Process.flag(:trap_exit, true)
      assert {:error, {:invalid_size, 0}} = CcxtOcx.RuntimePool.start_link(size: 0)
      assert {:error, {:invalid_size, -1}} = CcxtOcx.RuntimePool.start_link(size: -1)
      assert {:error, {:invalid_size, "4"}} = CcxtOcx.RuntimePool.start_link(size: "4")
      assert {:error, {:invalid_size, nil}} = CcxtOcx.RuntimePool.start_link(size: nil)
    end

    test "wrapper stops with :pool_died when NimblePool dies" do
      Process.flag(:trap_exit, true)
      {:ok, pool} = CcxtOcx.RuntimePool.start_link(size: 1)
      np = :sys.get_state(pool).np
      ref = Process.monitor(pool)

      Process.exit(np, :kill)

      assert_receive {:DOWN, ^ref, :process, ^pool, {:pool_died, :killed}}, 5_000
    end
  end

  describe "run/3" do
    test "happy path returns the function result", %{shared: pool} do
      result =
        CcxtOcx.RuntimePool.run(pool, fn rt ->
          QuickBEAM.eval(rt, "self.ccxt.version")
        end)

      assert {:ok, "4.5." <> _} = result
    end

    test "concurrent run/3 from N tasks each gets a working runtime" do
      {:ok, pool} = CcxtOcx.RuntimePool.start_link(size: 4)
      on_exit(fn -> if Process.alive?(pool), do: CcxtOcx.RuntimePool.stop(pool) end)

      results =
        1..4
        |> Task.async_stream(
          fn _ ->
            CcxtOcx.RuntimePool.run(pool, fn rt ->
              QuickBEAM.eval(rt, "self.ccxt.version")
            end)
          end,
          max_concurrency: 4,
          ordered: false,
          timeout: 60_000
        )
        |> Enum.map(fn {:ok, r} -> r end)

      assert length(results) == 4
      assert Enum.all?(results, fn {:ok, "4.5." <> _} -> true end)
    end

    test "raises from the function are propagated to the caller", %{shared: pool} do
      assert_raise RuntimeError, "boom", fn ->
        CcxtOcx.RuntimePool.run(pool, fn _rt -> raise "boom" end)
      end
    end

    test "non-NimblePool exit reasons from the callback propagate (not misclassified)", %{
      shared: pool
    } do
      # User callback exits with a `{:timeout, _}`-shaped reason that isn't
      # NimblePool's checkout timeout — the catch must NOT rewrite it to
      # `:checkout_timeout`. Same outer shape, different inner MFA.
      reason = {:timeout, {SomethingElse, :call, []}}

      assert catch_exit(CcxtOcx.RuntimePool.run(pool, fn _rt -> exit(reason) end)) == reason
    end

    test "returns :checkout_timeout when pool is exhausted" do
      {:ok, pool} = CcxtOcx.RuntimePool.start_link(size: 1)
      on_exit(fn -> if Process.alive?(pool), do: CcxtOcx.RuntimePool.stop(pool) end)

      parent = self()

      hog =
        Task.async(fn ->
          CcxtOcx.RuntimePool.run(
            pool,
            fn _rt ->
              send(parent, :hog_acquired)

              receive do
                :release -> :ok
              end
            end,
            10_000
          )
        end)

      assert_receive :hog_acquired, 5_000

      assert {:error, :checkout_timeout} =
               CcxtOcx.RuntimePool.run(pool, fn _ -> :ok end, 50)

      send(hog.pid, :release)
      Task.await(hog, 5_000)
    end

    test "long-lived: JS state set on one run is visible on a later run" do
      {:ok, pool} = CcxtOcx.RuntimePool.start_link(size: 1)
      on_exit(fn -> if Process.alive?(pool), do: CcxtOcx.RuntimePool.stop(pool) end)

      key = "ccxtOcxPoolTest_#{System.unique_integer([:positive])}"

      :ok =
        CcxtOcx.RuntimePool.run(pool, fn rt ->
          {:ok, _} = QuickBEAM.eval(rt, "globalThis.#{key} = 42;")
          :ok
        end)

      assert {:ok, 42} =
               CcxtOcx.RuntimePool.run(pool, fn rt ->
                 QuickBEAM.eval(rt, "globalThis.#{key}")
               end)
    end
  end

  describe "Worker callbacks (unit)" do
    alias CcxtOcx.RuntimePool.Worker

    test "handle_checkout/4 removes dead workers" do
      # Spawn a process and let it exit so its pid is dead but still has shape
      # of a worker pid. The dead-worker branch only fires if NimblePool hands
      # us a stale pid before its monitor has cleaned it up.
      dead = spawn(fn -> :ok end)
      ref = Process.monitor(dead)
      assert_receive {:DOWN, ^ref, :process, _, _}, 1_000
      refute Process.alive?(dead)

      assert {:remove, :dead_worker, %{runtime_opts: []}} =
               Worker.handle_checkout(:checkout, {self(), make_ref()}, dead, %{runtime_opts: []})
    end
  end

  describe "crash recovery" do
    test "worker crash → pool replaces it → subsequent run/3 succeeds" do
      {:ok, pool} = CcxtOcx.RuntimePool.start_link(size: 2)
      on_exit(fn -> if Process.alive?(pool), do: CcxtOcx.RuntimePool.stop(pool) end)

      version_before = CcxtOcx.RuntimePool.info(pool).ccxt_version
      np = :sys.get_state(pool).np

      # Direct NimblePool.checkout! lets us reach the Runtime server pid;
      # killing it triggers NimblePool's monitor → terminate_worker →
      # init_worker for a fresh replacement.
      killed_ref =
        NimblePool.checkout!(
          np,
          :checkout,
          fn _from, server ->
            ref = Process.monitor(server)
            Process.exit(server, :kill)
            {ref, :ok}
          end,
          10_000
        )

      assert_receive {:DOWN, ^killed_ref, :process, _pid, _}, 2_000

      # Replacement reloads the 5MB bundle — give it room.
      assert {:ok, ^version_before} =
               CcxtOcx.RuntimePool.run(
                 pool,
                 fn rt -> QuickBEAM.eval(rt, "self.ccxt.version") end,
                 30_000
               )
    end
  end
end
