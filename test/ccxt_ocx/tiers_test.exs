defmodule CcxtOcx.TiersTest do
  use ExUnit.Case, async: true

  alias CcxtOcx.Tiers

  doctest Tiers

  describe "roots (hand-curated)" do
    test "tier1_exchanges/0 returns the 5 curated roots" do
      roots = Tiers.tier1_exchanges()
      assert length(roots) == 5
      assert "binance" in roots
      assert "bybit" in roots
      assert "okx" in roots
      assert "deribit" in roots
      assert "coinbaseexchange" in roots
    end

    test "tier2_exchanges/0 returns the 6 curated roots" do
      roots = Tiers.tier2_exchanges()
      assert length(roots) == 6
      assert "kraken" in roots
      assert "kucoin" in roots
      assert "gate" in roots
      assert "htx" in roots
      assert "bitmex" in roots
      assert "bitfinex" in roots
    end

    test "tier3_exchanges/0 returns the 13 curated roots" do
      roots = Tiers.tier3_exchanges()
      assert length(roots) == 13
      assert "bitget" in roots
      assert "dydx" in roots
      assert "paradex" in roots
      assert "modetrade" in roots
    end

    test "dex_exchanges/0 returns the 4 curated roots" do
      roots = Tiers.dex_exchanges()
      assert length(roots) == 4
      assert "hyperliquid" in roots
      assert "aster" in roots
      assert "lighter" in roots
      assert "derive" in roots
    end
  end

  describe "members (roots + prototype-chain variants)" do
    test "tier1_members/0 includes binance family via prototype walk" do
      members = Tiers.tier1_members()
      assert "binance" in members
      assert "binanceus" in members
      assert "binancecoinm" in members
      assert "binanceusdm" in members
    end

    test "tier1_members/0 includes okx family via prototype walk" do
      members = Tiers.tier1_members()
      assert "okx" in members
      assert "okxus" in members
      assert "myokx" in members
    end

    test "tier2_members/0 includes htx alias huobi via prototype walk" do
      members = Tiers.tier2_members()
      assert "htx" in members
      assert "huobi" in members
    end

    test "tier2_members/0 includes gate alias gateio and kucoin variant via prototype walk" do
      members = Tiers.tier2_members()
      assert "gate" in members
      assert "gateio" in members
      assert "kucoin" in members
      assert "kucoinfutures" in members
    end

    test "members lists are sorted" do
      assert Tiers.tier1_members() == Enum.sort(Tiers.tier1_members())
      assert Tiers.tier2_members() == Enum.sort(Tiers.tier2_members())
      assert Tiers.tier3_members() == Enum.sort(Tiers.tier3_members())
      assert Tiers.dex_members() == Enum.sort(Tiers.dex_members())
    end

    test "members lists have no duplicates" do
      assert Tiers.tier1_members() == Enum.uniq(Tiers.tier1_members())
      assert Tiers.tier2_members() == Enum.uniq(Tiers.tier2_members())
      assert Tiers.tier3_members() == Enum.uniq(Tiers.tier3_members())
      assert Tiers.dex_members() == Enum.uniq(Tiers.dex_members())
    end

    test "roots ⊆ members for each tier" do
      for tier <- [:tier1, :tier2, :tier3, :dex] do
        roots = tier |> Tiers.exchanges_for_tier() |> MapSet.new()
        members = tier |> Tiers.members_for_tier() |> MapSet.new()
        assert MapSet.subset?(roots, members), "#{tier}: roots ⊄ members"
      end
    end

    test "tiers are pairwise disjoint" do
      all_members =
        Tiers.tier1_members() ++
          Tiers.tier2_members() ++
          Tiers.tier3_members() ++
          Tiers.dex_members()

      assert length(all_members) == length(Enum.uniq(all_members)),
             "an exchange appears in more than one tier"
    end
  end

  describe "exchanges_for_tier/1" do
    test "returns roots only — no variants" do
      assert Tiers.exchanges_for_tier(:tier1) == Tiers.tier1_exchanges()
      assert Tiers.exchanges_for_tier(:tier2) == Tiers.tier2_exchanges()
      assert Tiers.exchanges_for_tier(:tier3) == Tiers.tier3_exchanges()
      assert Tiers.exchanges_for_tier(:dex) == Tiers.dex_exchanges()
    end
  end

  describe "members_for_tier/1" do
    test "returns the expanded member set" do
      assert Tiers.members_for_tier(:tier1) == Tiers.tier1_members()
      assert Tiers.members_for_tier(:tier2) == Tiers.tier2_members()
      assert Tiers.members_for_tier(:tier3) == Tiers.tier3_members()
      assert Tiers.members_for_tier(:dex) == Tiers.dex_members()
    end
  end

  describe "get_priority_tier/1" do
    test "root exchanges return their own tier" do
      assert Tiers.get_priority_tier("binance") == :tier1
      assert Tiers.get_priority_tier("kraken") == :tier2
      assert Tiers.get_priority_tier("bitget") == :tier3
      assert Tiers.get_priority_tier("hyperliquid") == :dex
    end

    test "variants inherit their root's tier" do
      assert Tiers.get_priority_tier("binanceus") == :tier1
      assert Tiers.get_priority_tier("binancecoinm") == :tier1
      assert Tiers.get_priority_tier("okxus") == :tier1
      assert Tiers.get_priority_tier("myokx") == :tier1
      assert Tiers.get_priority_tier("huobi") == :tier2
      assert Tiers.get_priority_tier("gateio") == :tier2
      assert Tiers.get_priority_tier("kucoinfutures") == :tier2
    end

    test "unknown exchanges return :unclassified" do
      assert Tiers.get_priority_tier("not_a_real_exchange") == :unclassified
      assert Tiers.get_priority_tier("") == :unclassified
      assert Tiers.get_priority_tier("ftx") == :unclassified
    end
  end

  describe "predicates" do
    test "tier1?/1 agrees with get_priority_tier/1" do
      assert Tiers.tier1?("binance")
      assert Tiers.tier1?("binanceus")
      refute Tiers.tier1?("kraken")
      refute Tiers.tier1?("not_real")
    end

    test "tier2?/1 agrees with get_priority_tier/1" do
      assert Tiers.tier2?("kraken")
      assert Tiers.tier2?("huobi")
      refute Tiers.tier2?("binance")
      refute Tiers.tier2?("not_real")
    end

    test "tier3?/1 agrees with get_priority_tier/1" do
      assert Tiers.tier3?("bitget")
      refute Tiers.tier3?("binance")
      refute Tiers.tier3?("not_real")
    end

    test "dex?/1 agrees with get_priority_tier/1" do
      assert Tiers.dex?("hyperliquid")
      assert Tiers.dex?("derive")
      refute Tiers.dex?("binance")
      refute Tiers.dex?("not_real")
    end
  end

  describe "tier_display_name/1" do
    test "returns the canonical label strings" do
      assert Tiers.tier_display_name(:tier1) == "TIER 1"
      assert Tiers.tier_display_name(:tier2) == "TIER 2"
      assert Tiers.tier_display_name(:tier3) == "TIER 3"
      assert Tiers.tier_display_name(:dex) == "DEX"
    end
  end

  describe "has_tier_flags?/1" do
    test "empty opts returns false" do
      refute Tiers.has_tier_flags?([])
    end

    test "non-tier flags return false" do
      refute Tiers.has_tier_flags?(strict: true, verbose: true)
    end

    test "any tier flag set to truthy returns true" do
      assert Tiers.has_tier_flags?(tier1: true)
      assert Tiers.has_tier_flags?(tier2: true)
      assert Tiers.has_tier_flags?(tier3: true)
      assert Tiers.has_tier_flags?(dex: true)
    end

    test "tier flag set to false returns false" do
      refute Tiers.has_tier_flags?(tier1: false)
    end

    test "mix of tier and non-tier flags returns true when any tier is truthy" do
      assert Tiers.has_tier_flags?(strict: true, tier1: true)
      refute Tiers.has_tier_flags?(strict: true, tier1: false)
    end

    test "coerces truthy non-boolean values to boolean true" do
      assert Tiers.has_tier_flags?(tier1: :yes) === true
      assert Tiers.has_tier_flags?(tier2: "set") === true
      assert Tiers.has_tier_flags?(tier3: [1, 2]) === true
      assert Tiers.has_tier_flags?(dex: 42) === true
    end

    test "coerces falsy values to boolean false" do
      assert Tiers.has_tier_flags?([]) === false
      assert Tiers.has_tier_flags?(tier1: nil) === false
      assert Tiers.has_tier_flags?(tier1: false) === false
    end
  end

  describe "collect_tier_exchanges/1" do
    test "empty opts returns empty list and the zero label" do
      assert Tiers.collect_tier_exchanges([]) == {[], " (0)"}
    end

    test "single tier returns that tier's members and labeled count" do
      {exchanges, label} = Tiers.collect_tier_exchanges(tier1: true)
      assert exchanges == Tiers.tier1_members()
      assert label == "TIER 1 (#{length(exchanges)})"
    end

    test "multiple tiers union, sort, dedup with combined label" do
      {exchanges, label} = Tiers.collect_tier_exchanges(tier1: true, dex: true)
      assert "binance" in exchanges
      assert "binanceus" in exchanges
      assert "hyperliquid" in exchanges
      assert exchanges == Enum.sort(exchanges)
      assert exchanges == Enum.uniq(exchanges)
      assert label == "TIER 1 + DEX (#{length(exchanges)})"
    end

    test "all four tiers combine and label" do
      {exchanges, label} =
        Tiers.collect_tier_exchanges(tier1: true, tier2: true, tier3: true, dex: true)

      expected_count =
        (Tiers.tier1_members() ++
           Tiers.tier2_members() ++
           Tiers.tier3_members() ++
           Tiers.dex_members())
        |> Enum.uniq()
        |> length()

      assert length(exchanges) == expected_count
      assert label == "TIER 1 + TIER 2 + TIER 3 + DEX (#{expected_count})"
    end

    test "ignores tier flags set to false" do
      {exchanges, label} = Tiers.collect_tier_exchanges(tier1: true, tier2: false)
      assert exchanges == Tiers.tier1_members()
      assert label == "TIER 1 (#{length(exchanges)})"
    end
  end
end
