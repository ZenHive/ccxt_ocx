defmodule CcxtOcx.RuntimeTest do
  # GenServer + native QuickBEAM runtime — can't run async.
  use ExUnit.Case, async: false

  @bundle_path "node_modules/ccxt/dist/ccxt.browser.min.js"

  setup_all do
    if File.exists?(@bundle_path) do
      :ok
    else
      flunk("""
      ccxt browser bundle not found at #{@bundle_path}.

      Install ccxt before running these tests:
        npm install
      or, equivalently:
        mix npm.install ccxt
      """)
    end
  end

  setup do
    {:ok, server} = CcxtOcx.Runtime.start_link([])
    on_exit(fn -> if Process.alive?(server), do: CcxtOcx.Runtime.stop(server) end)
    {:ok, server: server}
  end

  describe "lifecycle" do
    test "start_link/1 boots a runtime, applies stubs, and loads the bundle", %{server: server} do
      assert is_pid(server)
      assert Process.alive?(server)
    end

    test "rt/1 returns a live QuickBEAM handle", %{server: server} do
      rt = CcxtOcx.Runtime.rt(server)
      assert is_pid(rt)
      assert Process.alive?(rt)
    end

    test "stop/1 terminates the GenServer and frees the underlying runtime" do
      {:ok, server} = CcxtOcx.Runtime.start_link([])
      rt = CcxtOcx.Runtime.rt(server)
      ref = Process.monitor(rt)
      :ok = CcxtOcx.Runtime.stop(server)
      refute Process.alive?(server)
      assert_receive {:DOWN, ^ref, :process, ^rt, _reason}, 1_000
    end

    test "start_link/0 boots with default opts" do
      {:ok, server} = CcxtOcx.Runtime.start_link()
      on_exit(fn -> if Process.alive?(server), do: CcxtOcx.Runtime.stop(server) end)
      assert Process.alive?(server)
    end
  end

  describe "JS surface" do
    test "eval/3 round-trip", %{server: server} do
      assert {:ok, 3} = CcxtOcx.Runtime.eval(server, "1 + 2")
    end

    test "call/4 round-trip via define-then-call", %{server: server} do
      {:ok, _} = CcxtOcx.Runtime.eval(server, "globalThis.foo = (x) => x * 2;")
      assert {:ok, 42} = CcxtOcx.Runtime.call(server, "foo", [21])
    end

    test "with_runtime/2 hands the raw rt to the caller", %{server: server} do
      result =
        CcxtOcx.Runtime.with_runtime(server, fn rt ->
          assert is_pid(rt)
          QuickBEAM.eval(rt, "5 + 5")
        end)

      assert {:ok, 10} = result
    end
  end

  describe "browser stubs" do
    test "self and window aliased to globalThis", %{server: server} do
      assert {:ok, true} =
               CcxtOcx.Runtime.eval(server, "typeof self === 'object' && self === globalThis")

      assert {:ok, true} =
               CcxtOcx.Runtime.eval(server, "typeof window === 'object' && window === globalThis")
    end

    test "navigator userAgent set", %{server: server} do
      assert {:ok, "QuickBEAM/CcxtOcx"} = CcxtOcx.Runtime.eval(server, "navigator.userAgent")
    end

    test "location populated", %{server: server} do
      assert {:ok, "https:"} = CcxtOcx.Runtime.eval(server, "location.protocol")
    end
  end

  describe "ccxt bundle" do
    test "version reachable and starts with 4.5.", %{server: server} do
      assert {:ok, "4.5." <> _} = CcxtOcx.Runtime.eval(server, "self.ccxt.version")
    end

    test "info/1 reports version, exchange_count, bundle_path", %{server: server} do
      info = CcxtOcx.Runtime.info(server)
      assert is_binary(info.ccxt_version)
      assert info.exchange_count > 100
      assert is_binary(info.bundle_path)
      assert String.ends_with?(info.bundle_path, "ccxt.browser.min.js")
    end

    # Risk Register pin from ROADMAP: this bundle exposes `self.ccxt.exchanges`
    # as an Object and `self.ccxt.default.exchanges` as the Array. Anything
    # downstream that wants the list of supported exchanges must use
    # `default.exchanges`. If ccxt restructures, this fails LOUD instead of
    # silently corrupting consumers.
    test "default.exchanges is the Array, exchanges is the Object", %{server: server} do
      assert {:ok, true} =
               CcxtOcx.Runtime.eval(server, "Array.isArray(self.ccxt.default.exchanges)")

      assert {:ok, false} = CcxtOcx.Runtime.eval(server, "Array.isArray(self.ccxt.exchanges)")
    end
  end

  describe "isolation" do
    test "caller crash mid-with_runtime/2 does not affect the runtime", %{server: server} do
      info_before = CcxtOcx.Runtime.info(server)
      parent = self()

      pid =
        spawn(fn ->
          CcxtOcx.Runtime.with_runtime(server, fn _rt ->
            send(parent, :inside)
            Process.exit(self(), :kill)
          end)
        end)

      ref = Process.monitor(pid)
      assert_receive :inside, 1_000
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000

      # Runtime is unharmed
      assert Process.alive?(server)
      assert {:ok, 7} = CcxtOcx.Runtime.eval(server, "3 + 4")
      assert CcxtOcx.Runtime.info(server) == info_before
    end
  end

  describe "configuration" do
    test "missing bundle path produces a labeled error" do
      Process.flag(:trap_exit, true)
      bogus = Path.join(System.tmp_dir!(), "ccxt-#{System.unique_integer([:positive])}.js")

      assert {:error, {:bundle_missing, msg}} = CcxtOcx.Runtime.start_link(bundle_path: bogus)
      assert msg =~ bogus
    end

    test "bundle that fails to eval produces a labeled error" do
      Process.flag(:trap_exit, true)
      bogus = Path.join(System.tmp_dir!(), "ccxt-syntax-#{System.unique_integer([:positive])}.js")
      File.write!(bogus, "const x = (((;")
      on_exit(fn -> File.rm(bogus) end)

      assert {:error, {:bundle_load_failed, _reason}} =
               CcxtOcx.Runtime.start_link(bundle_path: bogus)
    end

    test "terminate/2 with no :rt in state is a no-op" do
      assert :ok = CcxtOcx.Runtime.terminate(:shutdown, %{})
    end

    # TODO(Task 3): add :vars / :timeout / :name option-pass-through tests for
    # eval/3 + call/4 + start_link/1 before RuntimePool work lands.
  end

  describe "telemetry (Task 14)" do
    test "memory/1 returns measurements and emits [:ccxt_ocx, :runtime, :memory]", %{server: server} do
      handler_id = make_ref()
      test_pid = self()

      :telemetry.attach(
        handler_id,
        [:ccxt_ocx, :runtime, :memory],
        fn event, meas, meta, _config ->
          send(test_pid, {:telemetry, event, meas, meta})
        end,
        %{}
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      measurements = CcxtOcx.Runtime.memory(server)

      assert is_map(measurements)
      assert Map.has_key?(measurements, :malloc_size)
      assert Map.has_key?(measurements, :memory_used_size)
      assert Map.has_key?(measurements, :obj_count)

      assert_receive {:telemetry, [:ccxt_ocx, :runtime, :memory], ^measurements, %{server: ^server}}, 1_000
    end

    test "memory/1 emits pid metadata for named runtimes" do
      handler_id = make_ref()
      test_pid = self()
      name = :"runtime_#{System.unique_integer([:positive])}"

      {:ok, server} = CcxtOcx.Runtime.start_link(name: name)

      :telemetry.attach(
        handler_id,
        [:ccxt_ocx, :runtime, :memory],
        fn event, meas, meta, _config ->
          send(test_pid, {:telemetry, event, meas, meta})
        end,
        %{}
      )

      on_exit(fn ->
        :telemetry.detach(handler_id)
        if Process.alive?(server), do: CcxtOcx.Runtime.stop(server)
      end)

      measurements = CcxtOcx.Runtime.memory(name)

      assert_receive {:telemetry, [:ccxt_ocx, :runtime, :memory], ^measurements, %{server: ^server}}, 1_000
    end

    test "baseline memory event is emitted during init", _context do
      handler_id = make_ref()
      test_pid = self()

      :telemetry.attach(
        handler_id,
        [:ccxt_ocx, :runtime, :memory],
        fn event, _meas, meta, _config ->
          send(test_pid, {:telemetry_init, event, meta})
        end,
        %{}
      )

      {:ok, server} = CcxtOcx.Runtime.start_link([])

      on_exit(fn ->
        :telemetry.detach(handler_id)
        if Process.alive?(server), do: CcxtOcx.Runtime.stop(server)
      end)

      assert_receive {:telemetry_init, [:ccxt_ocx, :runtime, :memory], %{server: ^server, phase: :init}}, 2_000

      # Also verify the explicit path still works
      _ = CcxtOcx.Runtime.memory(server)
    end
  end
end
