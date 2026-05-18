defmodule CcxtOcx.DeclarationsTest do
  use ExUnit.Case, async: false

  alias CcxtOcx.Declarations
  alias CcxtOcx.Declarations.Compile

  describe "public_unified_method?/1 (filter ownership)" do
    test "accepts core smoke methods" do
      assert Compile.public_unified_method?("fetchTicker")
      assert Compile.public_unified_method?("createOrder")
      assert Compile.public_unified_method?("watchTicker")
    end

    test "accepts bare trade-plane methods from the allowlist" do
      assert Compile.public_unified_method?("withdraw")
      assert Compile.public_unified_method?("transfer")
    end

    test "rejects internal helpers even when they match a verb prefix" do
      refute Compile.public_unified_method?("parseOrder")
      refute Compile.public_unified_method?("handleTicker")
      refute Compile.public_unified_method?("sign")
    end

    test "rejects the explicit denylist" do
      refute Compile.public_unified_method?("fetch2")
      refute Compile.public_unified_method?("loadMarketsHelper")
    end
  end

  describe "type renderer (pure)" do
    test "renders primitive keywords" do
      assert Compile.render_type(%{type: :ts_string_keyword}) == "string"
      assert Compile.render_type(%{type: :ts_number_keyword}) == "number"
      assert Compile.render_type(%{type: :ts_boolean_keyword}) == "boolean"
    end

    test "renders type references with and without type args" do
      assert Compile.render_type(%{type: :ts_type_reference, typeName: %{name: "Ticker"}}) == "Ticker"

      assert Compile.render_type(%{
               type: :ts_type_reference,
               typeName: %{name: "Promise"},
               typeArguments: %{params: [%{type: :ts_type_reference, typeName: %{name: "Order"}}]}
             }) == "Promise<Order>"
    end

    test "renders inline object and array forms" do
      assert Compile.render_type(%{type: :ts_type_literal}) == "{}"
      assert Compile.render_type(%{type: :ts_array_type, elementType: %{type: :ts_string_keyword}}) == "string[]"
    end

    test "falls back loudly on unknown nodes (test guard)" do
      assert Compile.render_type(%{type: :ts_foo_bar_baz}) == "UNKNOWN(ts_foo_bar_baz)"
    end
  end

  describe "parse_unified_surface/0 (integration — real CCXT .d.ts)" do
    @tag :integration
    test "extracts the three smoke methods with correct primary surface and basic shape" do
      terms = Declarations.parse_unified_surface()
      names = Enum.map(terms, & &1.name)

      for m <- ["fetchTicker", "createOrder", "watchTicker"] do
        assert m in names, "expected #{m} in parsed unified surface"
      end

      ticker = Enum.find(terms, &(&1.name == "fetchTicker"))
      assert ticker.primary.surface == :base
      assert String.ends_with?(ticker.primary.source, "Exchange.d.ts")
      assert length(ticker.params) >= 2
      assert ticker.return_type =~ "Promise"
      assert ticker.return_type =~ "Ticker"

      create = Enum.find(terms, &(&1.name == "createOrder"))
      assert create.primary.surface == :base
      assert length(create.params) >= 5

      watch = Enum.find(terms, &(&1.name == "watchTicker"))
      assert watch.primary.surface == :base
    end

    @tag :integration
    test "distinguishes base / exchange / pro surfaces and populates overrides" do
      terms = Declarations.parse_unified_surface()

      # `overrides` is keyed by "surface:exchange_id" strings, so we must read the
      # surface atoms off the override VALUES, not Map.keys/1.
      primary_surfaces =
        terms
        |> Enum.map(& &1.primary.surface)
        |> Enum.uniq()

      override_surfaces =
        terms
        |> Enum.flat_map(fn t -> t.overrides |> Map.values() |> Enum.map(& &1.surface) end)
        |> Enum.uniq()

      assert :base in primary_surfaces
      assert :exchange in override_surfaces, "expected at least one :exchange override across the unified surface"
      assert :pro in override_surfaces, "expected at least one :pro override across the unified surface"
    end
  end

  describe "path helpers" do
    test "base_dts_path ends with the expected file" do
      p = Compile.base_dts_path()
      assert String.ends_with?(p, "base/Exchange.d.ts")
    end

    @tag :integration
    test "exchange and pro globs return a plausible number of files" do
      # Non-empty + presence of a known-canonical exchange is sufficient.
      # A `> 50` threshold would track upstream CCXT's exchange catalog
      # churn instead of catching real parser-glob regressions.
      assert Compile.exchange_dts_paths() != []
      assert Compile.pro_dts_paths() != []
      assert Enum.any?(Compile.exchange_dts_paths(), &String.ends_with?(&1, "binance.d.ts"))
      assert Enum.any?(Compile.pro_dts_paths(), &String.ends_with?(&1, "binance.d.ts"))
    end
  end
end
