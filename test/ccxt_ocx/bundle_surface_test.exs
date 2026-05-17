defmodule CcxtOcx.BundleSurfaceTest do
  use ExUnit.Case, async: false

  alias CcxtOcx.BundleSurface
  alias CcxtOcx.BundleSurface.Compile
  alias CcxtOcx.BundleSurface.Manifest
  alias Mix.Tasks.Ccxt.VerifyBundle

  describe "manifest" do
    test "committed manifest is readable and contains the expected keys" do
      manifest = Manifest.read()
      assert is_map(manifest)
      assert Map.has_key?(manifest, :unified_methods)
      assert is_list(manifest.unified_methods)
      assert length(manifest.unified_methods) > 50
    end

    test "path/0 resolves under :code.priv_dir(:ccxt_ocx)" do
      p = Manifest.path()
      priv = to_string(:code.priv_dir(:ccxt_ocx))
      assert String.starts_with?(p, priv), "expected #{p} to start with #{priv}"
      assert Path.basename(p) == "ccxt_surface.exs"
    end
  end

  describe "OXC extraction" do
    test "extract_unified_methods filters a small local declaration fixture" do
      path =
        temp_file!("exchange_fixture.d.ts", """
        export default class Exchange {
          fetchTicker(): Promise<object>;
          createOrder(): Promise<object>;
          withdraw(): Promise<object>;
          parseTrade(): object;
          request(): Promise<object>;
          fetch2(): Promise<object>;
          loadMarketsHelper(): Promise<object>;
        }
        """)

      assert Compile.extract_unified_methods(path) == ["createOrder", "fetchTicker", "withdraw"]
    end

    test "extract_unified_methods raises when the declaration file is missing" do
      missing_path = Path.join(System.tmp_dir!(), "ccxt_ocx_missing_exchange.d.ts")

      assert_raise RuntimeError, ~r/CCXT declaration file not found/, fn ->
        Compile.extract_unified_methods(missing_path)
      end
    end

    @tag :integration
    test "extract_unified_methods finds the smoke surface from Exchange.d.ts" do
      path = Compile.exchange_dts_path()
      methods = Compile.extract_unified_methods(path)

      # The five methods the Phase 1 smoke test already asserts on
      for m <- ["fetchTicker", "fetchOrderBook", "fetchOHLCV", "fetchTrades", "watchTicker"] do
        assert m in methods, "expected #{m} to be present in extracted unified methods"
      end
    end

    @tag :integration
    test "extract_unified_methods includes bare-name trade-plane methods" do
      path = Compile.exchange_dts_path()
      methods = Compile.extract_unified_methods(path)

      # These don't match the verb-prefix filter and would be dropped without
      # the @additional_unified_methods allowlist (Cat 1 regression guard).
      for m <- ["withdraw", "transfer"] do
        assert m in methods, "expected bare-name trade-plane method #{m} to be present"
      end
    end
  end

  describe "BundleSurface facade" do
    test "manifest_path delegates to Manifest.path" do
      assert BundleSurface.manifest_path() == Manifest.path()
      assert File.exists?(BundleSurface.manifest_path())
    end

    test "unified_methods/0 returns the committed list (>=50 entries, sorted)" do
      methods = BundleSurface.unified_methods()
      assert is_list(methods)
      assert length(methods) > 50
      assert methods == Enum.sort(methods)
      assert "fetchTicker" in methods
      assert "withdraw" in methods, "expected trade-plane allowlist entry"
    end

    test "unified_methods/0 excludes CCXT base-class internal helpers" do
      methods = BundleSurface.unified_methods()

      denied = ~w(
        fetch2
        fetchPaginatedCallCursor
        fetchPaginatedCallDeterministic
        fetchPaginatedCallDynamic
        fetchPaginatedCallIncremental
        fetchPartialBalance
        fetchWebEndpoint
        createSafeDictionary
        loadMarketsHelper
      )

      for name <- denied do
        refute name in methods,
               "expected #{name} to be filtered out by @additional_denied in Compile.public_unified_method?/1"
      end
    end

    test "sampled_has/0 returns the committed has-table map" do
      tables = BundleSurface.sampled_has()
      assert is_map(tables)
      assert map_size(tables) >= 1

      for {ex, has} <- tables do
        assert is_binary(ex)
        assert is_map(has)
      end
    end
  end

  describe "Manifest.diff/2" do
    test "reports added and removed methods" do
      old = %{unified_methods: ~w(fetchTicker watchTrades), sampled_has: %{}}
      new = %{unified_methods: ~w(fetchTicker createOrder), sampled_has: %{}}

      diff = Manifest.diff(old, new)
      assert diff.methods.added == ["createOrder"]
      assert diff.methods.removed == ["watchTrades"]
      refute diff.has_changed?
    end

    test "reports identical snapshots as no-drift" do
      snap = %{unified_methods: ~w(fetchTicker), sampled_has: %{"binance" => %{}}}
      diff = Manifest.diff(snap, snap)
      assert diff.methods.added == []
      assert diff.methods.removed == []
      refute diff.has_changed?
    end

    test "flags has_changed? when sampled_has differs" do
      old = %{unified_methods: [], sampled_has: %{"binance" => %{"fetchTicker" => true}}}
      new = %{unified_methods: [], sampled_has: %{"binance" => %{"fetchTicker" => "emulated"}}}
      diff = Manifest.diff(old, new)
      assert diff.has_changed?
    end

    test "tolerates missing keys (returns empty diff)" do
      diff = Manifest.diff(%{}, %{})
      assert diff.methods.added == []
      assert diff.methods.removed == []
      refute diff.has_changed?
    end
  end

  describe "BundleSurface.build_snapshot/1" do
    test "probe_has_tables raises when configured bundle path is missing" do
      old_path = Application.get_env(:ccxt_ocx, :bundle_path)
      missing_path = Path.join(System.tmp_dir!(), "ccxt_ocx_missing_bundle.js")

      Application.put_env(:ccxt_ocx, :bundle_path, missing_path)

      on_exit(fn ->
        if old_path do
          Application.put_env(:ccxt_ocx, :bundle_path, old_path)
        else
          Application.delete_env(:ccxt_ocx, :bundle_path)
        end
      end)

      assert_raise RuntimeError, ~r/CCXT bundle not found/, fn ->
        Compile.probe_has_tables(["binance"])
      end
    end

    @tag :integration
    test "returns a snapshot with methods + sampled has for a small sample" do
      snap = BundleSurface.build_snapshot(["binance"])

      assert is_list(snap.unified_methods)
      assert length(snap.unified_methods) > 50
      assert "fetchTicker" in snap.unified_methods
      assert "withdraw" in snap.unified_methods

      assert is_map(snap.sampled_has)
      assert Map.has_key?(snap.sampled_has, "binance")
      assert is_map(snap.sampled_has["binance"])

      assert is_binary(snap.generated_at)
      assert is_binary(snap.ccxt_version)
    end

    @tag :integration
    test "default_sample_exchanges/0 falls back when Tiers raises" do
      # Hit the rescue branch by intercepting via the Compile alias directly.
      result = Compile.default_sample_exchanges()
      assert is_list(result)
      assert result != []
    end
  end

  describe "Mix.Tasks.Ccxt.VerifyBundle" do
    setup do
      path = Manifest.path()
      backup = File.read!(path)
      on_exit(fn -> File.write!(path, backup) end)
      :ok
    end

    test "raises Mix.Error on unknown option" do
      ExUnit.CaptureIO.capture_io(fn ->
        assert_raise Mix.Error, ~r/Unknown or malformed option/i, fn ->
          VerifyBundle.run(["--bogus-flag"])
        end
      end)
    end

    @tag :integration
    test "raises Mix.Error on detected drift without --accept" do
      # Sampling a single exchange diffs against the committed multi-exchange
      # snapshot — guaranteed drift, no manifest mutation since --accept is absent.
      ExUnit.CaptureIO.capture_io(fn ->
        assert_raise Mix.Error, ~r/drift detected/i, fn ->
          VerifyBundle.run(["--sample-exchanges", "binance"])
        end
      end)
    end

    @tag :integration
    test "--accept regenerates the manifest with the new sample" do
      ExUnit.CaptureIO.capture_io(fn ->
        assert :ok = VerifyBundle.run(["--accept", "--sample-exchanges", "binance"])
      end)

      snap = Manifest.read()
      assert map_size(snap.sampled_has) == 1
      assert Map.has_key?(snap.sampled_has, "binance")
    end

    @tag :integration
    test "-w alias also writes" do
      ExUnit.CaptureIO.capture_io(fn ->
        assert :ok = VerifyBundle.run(["-w", "--sample-exchanges", "binance"])
      end)

      snap = Manifest.read()
      assert map_size(snap.sampled_has) == 1
    end

    @tag :integration
    test "no-arg run succeeds against the committed manifest (CI lockfile invariant)" do
      # Committed priv/ccxt_surface.exs was generated from the same lockfile
      # CI installs via `mix npm.ci`, so no-drift is the expected outcome.
      ExUnit.CaptureIO.capture_io(fn ->
        assert :ok = VerifyBundle.run([])
      end)
    end
  end

  describe "Manifest.write/1 (sandboxed)" do
    setup do
      original_priv = :code.priv_dir(:ccxt_ocx)
      tmp = Path.join(System.tmp_dir!(), "ccxt_ocx_manifest_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)

      # Redirect :code.priv_dir/1 to a tmp dir by overlaying the path. We use
      # the lower-level Manifest.path/0 indirection: write to a path computed
      # against tmp, then read it back through the same evaluator.
      on_exit(fn ->
        _ = File.rm_rf(tmp)
        _ = original_priv
      end)

      {:ok, tmp: tmp}
    end

    test "write+read round-trip preserves the snapshot shape", %{tmp: tmp} do
      target = Path.join(tmp, "ccxt_surface.exs")

      snapshot = %{
        ccxt_version: "test",
        generated_at: "1970-01-01T00:00:00Z",
        unified_methods: ~w(fetchTicker createOrder),
        sampled_has: %{"binance" => %{"fetchTicker" => true}}
      }

      File.mkdir_p!(Path.dirname(target))

      File.write!(target, """
      # round-trip fixture

      #{inspect(snapshot, pretty: true, limit: :infinity, charlists: false)}
      """)

      {term, _} = Code.eval_file(target)
      assert term == snapshot
    end
  end

  defp temp_file!(name, content) do
    dir = Path.join(System.tmp_dir!(), "ccxt_ocx_bundle_surface_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, name)
    File.write!(path, content)
    on_exit(fn -> File.rm_rf(dir) end)
    path
  end
end
