defmodule CcxtOcx.BundleSurfaceTest do
  use ExUnit.Case, async: false

  alias CcxtOcx.BundleSurface
  alias CcxtOcx.BundleSurface.Compile
  alias CcxtOcx.BundleSurface.Manifest

  @moduletag :integration

  describe "manifest" do
    test "committed manifest is readable and contains the expected keys" do
      manifest = Manifest.read()
      assert is_map(manifest)
      assert Map.has_key?(manifest, :unified_methods)
      assert is_list(manifest.unified_methods)
      assert length(manifest.unified_methods) > 50
    end
  end

  describe "OXC extraction" do
    test "extract_unified_methods finds the smoke surface from Exchange.d.ts" do
      path = Compile.exchange_dts_path()
      methods = Compile.extract_unified_methods(path)

      # The five methods the Phase 1 smoke test already asserts on
      for m <- ["fetchTicker", "fetchOrderBook", "fetchOHLCV", "fetchTrades", "watchTicker"] do
        assert m in methods, "expected #{m} to be present in extracted unified methods"
      end
    end
  end

  describe "BundleSurface facade" do
    test "manifest_path points at the committed file" do
      assert File.exists?(BundleSurface.manifest_path())
    end
  end
end
