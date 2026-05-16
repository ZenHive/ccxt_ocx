defmodule CcxtOcx.Tiers.CompileTest do
  use ExUnit.Case, async: false

  alias CcxtOcx.Tiers.Compile

  describe "bundle_path/0" do
    setup do
      original = Application.get_env(:ccxt_ocx, :bundle_path)

      on_exit(fn ->
        case original do
          nil -> Application.delete_env(:ccxt_ocx, :bundle_path)
          value -> Application.put_env(:ccxt_ocx, :bundle_path, value)
        end
      end)

      :ok
    end

    test "default resolves the in-tree bundle path under cwd" do
      Application.delete_env(:ccxt_ocx, :bundle_path)

      path = Compile.bundle_path()

      assert Path.type(path) == :absolute
      assert String.ends_with?(path, "node_modules/ccxt/dist/ccxt.browser.min.js")
      assert String.starts_with?(path, File.cwd!())
    end

    test "absolute override returns the configured path unchanged" do
      Application.put_env(:ccxt_ocx, :bundle_path, "/tmp/custom/bundle.js")
      assert Compile.bundle_path() == "/tmp/custom/bundle.js"
    end

    test "relative override resolves relative to cwd" do
      Application.put_env(:ccxt_ocx, :bundle_path, "test/fixtures/bundle.js")

      path = Compile.bundle_path()

      assert Path.type(path) == :absolute
      assert String.ends_with?(path, "test/fixtures/bundle.js")
      assert String.starts_with?(path, File.cwd!())
    end
  end

  describe "derive_inheritance!/1" do
    test "raises with actionable message when the bundle file is missing" do
      assert_raise RuntimeError, ~r/CCXT bundle not found/, fn ->
        Compile.derive_inheritance!("/nonexistent/path/to/ccxt.browser.min.js")
      end
    end

    test "raise message points the operator at `mix npm.install`" do
      try do
        Compile.derive_inheritance!("/nonexistent/path/to/ccxt.browser.min.js")
        flunk("expected raise")
      rescue
        e in RuntimeError ->
          assert e.message =~ "mix npm.install"
          assert e.message =~ "node_modules/ccxt/dist/ccxt.browser.min.js"
      end
    end

    test "derives variant→parent map from the loaded CCXT bundle" do
      bundle_path = Compile.bundle_path()

      if not File.exists?(bundle_path) do
        flunk("""
        CCXT bundle not found at #{bundle_path}.

        This test requires the bundle to be installed. Run:
          mix npm.install
        """)
      end

      map = Compile.derive_inheritance!(bundle_path)

      assert is_map(map)
      refute Enum.empty?(map)

      # Known variant→parent pairs from the bundle's class graph.
      assert Map.get(map, "binanceus") == "binance"
      assert Map.get(map, "binancecoinm") == "binance"
      assert Map.get(map, "binanceusdm") == "binance"
      assert Map.get(map, "okxus") == "okx"
      assert Map.get(map, "myokx") == "okx"
      assert Map.get(map, "huobi") == "htx"
      assert Map.get(map, "gateio") == "gate"
      assert Map.get(map, "kucoinfutures") == "kucoin"

      # Pure exchanges extending the base `Exchange` class are absent
      # from the map (no exchange-class parent).
      refute Map.has_key?(map, "binance")
      refute Map.has_key?(map, "kraken")
    end
  end

  describe "expand/2" do
    test "returns sorted-unique roots when inheritance map is empty" do
      assert Compile.expand(["c", "a", "b"], %{}) == ["a", "b", "c"]
    end

    test "deduplicates duplicate roots in the input list" do
      assert Compile.expand(["a", "a", "b"], %{}) == ["a", "b"]
    end

    test "includes a variant whose direct parent is a root" do
      assert Compile.expand(["binance"], %{"binanceus" => "binance"}) == [
               "binance",
               "binanceus"
             ]
    end

    test "excludes a variant whose parent is not a root" do
      assert Compile.expand(["binance"], %{"foo" => "bar"}) == ["binance"]
    end

    test "resolves transitive parents through the inheritance chain" do
      inheritance = %{"grandchild" => "child", "child" => "parent"}

      result = Compile.expand(["parent"], inheritance)

      assert result == ["child", "grandchild", "parent"]
    end

    test "output is sorted and deduplicated across roots and variants" do
      inheritance = %{"y" => "x", "z" => "x", "w" => "y"}

      result = Compile.expand(["x"], inheritance)

      assert result == ["w", "x", "y", "z"]
    end

    test "caps the resolve walk on a two-node cycle (a ↔ b, neither root)" do
      # Without the depth cap, walking a→b→a→… would loop forever.
      # The cap returns the id at depth 0; neither a nor b is in roots,
      # so both are excluded from the expansion.
      inheritance = %{"a" => "b", "b" => "a"}

      assert Compile.expand(["root"], inheritance) == ["root"]
    end

    test "handles a self-parent (a → a) without infinite recursion" do
      assert Compile.expand(["root"], %{"a" => "a"}) == ["root"]
    end

    test "variant survives even when its chain bottoms out at depth 0 inside the roots" do
      # Long enough chain that the walk approaches the @walk_depth_cap.
      inheritance = %{
        "v1" => "v2",
        "v2" => "v3",
        "v3" => "v4",
        "v4" => "v5",
        "v5" => "root"
      }

      result = Compile.expand(["root"], inheritance)

      assert "root" in result
      assert "v1" in result
      assert "v5" in result
    end
  end
end
