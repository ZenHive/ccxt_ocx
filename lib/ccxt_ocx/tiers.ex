defmodule CcxtOcx.Tiers do
  @moduledoc """
  Priority-tier classification for CCXT exchanges.

  Tier membership has two layers:

    * **Roots** — hand-curated in `priv/priority_tiers.json`. The
      canonical per-tier exchange lists `ccxt_ocx` commits to deriving
      recipes for.
    * **Members** — roots **plus** any CCXT exchange whose
      prototype-chain parent (transitively) is a root. Variants
      (`binance` → `binanceus`, `binancecoinm`, `binanceusdm`; `okx` →
      `okxus`, `myokx`; `kucoin` → `kucoinfutures`) and aliases
      (`htx` → `huobi`; `gate` → `gateio`) inherit their root's tier.

  The variant map is derived at compile time by walking
  `Object.getPrototypeOf` on every exchange class in the loaded CCXT
  bundle (`CcxtOcx.Tiers.Compile.derive_inheritance!/1`). Inheritance is
  **provable** from the JS class graph, not guessed — this mirrors
  `ccxt_extract`'s honesty rule.

  The four member buckets are:

    * `:tier1` — must-have priority (roots: binance, bybit, okx, deribit,
      coinbaseexchange)
    * `:tier2` — valuable, specific use cases (roots: kraken, kucoin,
      gate, htx, bitmex, bitfinex)
    * `:tier3` — explicitly deprioritized; supported but tasks defer
      until a real consumer surfaces a need
    * `:dex` — priority DEX track (perps + on-chain options)

  Anything not in any member set is `:unclassified`.

  Loaded at compile time via `@external_resource` on the bundle file
  and `priv/priority_tiers.json` — bumping CCXT or editing curation
  triggers a recompile.

  ## Drift policy

  `ccxt_extract`'s `priv/priority_tiers.json` is the inspiration but
  not the contract — when curation changes there, manually port
  relevant changes here. `ccxt_ocx` ships to hex.pm and cannot
  path-dep on its sibling.
  """

  alias CcxtOcx.Tiers.Compile

  @bundle_path Compile.bundle_path()
  @tier_roots_path Path.join(__DIR__, "../../priv/priority_tiers.json")

  @external_resource @bundle_path
  @external_resource @tier_roots_path

  tier_roots = @tier_roots_path |> File.read!() |> JSON.decode!()
  inheritance_map = Compile.derive_inheritance!(@bundle_path)

  @tier1_exchanges Map.fetch!(tier_roots, "tier1")
  @tier2_exchanges Map.fetch!(tier_roots, "tier2")
  @tier3_exchanges Map.fetch!(tier_roots, "tier3")
  @dex_exchanges Map.fetch!(tier_roots, "dex")

  @tier1_members Compile.expand(@tier1_exchanges, inheritance_map)
  @tier2_members Compile.expand(@tier2_exchanges, inheritance_map)
  @tier3_members Compile.expand(@tier3_exchanges, inheritance_map)
  @dex_members Compile.expand(@dex_exchanges, inheritance_map)

  @tier_member_map Enum.reduce(
                     [
                       {:tier1, @tier1_members},
                       {:tier2, @tier2_members},
                       {:tier3, @tier3_members},
                       {:dex, @dex_members}
                     ],
                     %{},
                     fn {tier, members}, acc ->
                       Enum.reduce(members, acc, &Map.put(&2, &1, tier))
                     end
                   )

  @doc "Returns Priority Tier 1 **roots** (hand-curated, does not include variants)."
  @spec tier1_exchanges() :: [String.t()]
  def tier1_exchanges, do: @tier1_exchanges

  @doc "Returns Priority Tier 2 **roots** (hand-curated, does not include variants)."
  @spec tier2_exchanges() :: [String.t()]
  def tier2_exchanges, do: @tier2_exchanges

  @doc "Returns Priority Tier 3 **roots** (hand-curated, does not include variants)."
  @spec tier3_exchanges() :: [String.t()]
  def tier3_exchanges, do: @tier3_exchanges

  @doc "Returns priority DEX **roots** (hand-curated, does not include variants)."
  @spec dex_exchanges() :: [String.t()]
  def dex_exchanges, do: @dex_exchanges

  @doc """
  Returns Tier 1 **members**: roots plus all variants/aliases inheriting
  from a Tier 1 root. This is the set used by `--tier1` scoping.
  """
  @spec tier1_members() :: [String.t()]
  def tier1_members, do: @tier1_members

  @doc "Returns Tier 2 **members** (roots + variants/aliases)."
  @spec tier2_members() :: [String.t()]
  def tier2_members, do: @tier2_members

  @doc "Returns Tier 3 **members** (roots + variants/aliases)."
  @spec tier3_members() :: [String.t()]
  def tier3_members, do: @tier3_members

  @doc "Returns DEX **members** (roots + variants/aliases)."
  @spec dex_members() :: [String.t()]
  def dex_members, do: @dex_members

  @doc """
  Returns the **root** exchanges for a given priority tier atom.

      iex> "binance" in CcxtOcx.Tiers.exchanges_for_tier(:tier1)
      true

      iex> "binanceus" in CcxtOcx.Tiers.exchanges_for_tier(:tier1)
      false
  """
  @spec exchanges_for_tier(:tier1 | :tier2 | :tier3 | :dex) :: [String.t()]
  def exchanges_for_tier(:tier1), do: @tier1_exchanges
  def exchanges_for_tier(:tier2), do: @tier2_exchanges
  def exchanges_for_tier(:tier3), do: @tier3_exchanges
  def exchanges_for_tier(:dex), do: @dex_exchanges

  @doc """
  Returns the **members** (roots + variants/aliases) for a given priority
  tier atom. This is the set used by `--tier*` scoping.

      iex> members = CcxtOcx.Tiers.members_for_tier(:tier1)
      iex> "binance" in members and "binanceus" in members
      true
  """
  @spec members_for_tier(:tier1 | :tier2 | :tier3 | :dex) :: [String.t()]
  def members_for_tier(:tier1), do: @tier1_members
  def members_for_tier(:tier2), do: @tier2_members
  def members_for_tier(:tier3), do: @tier3_members
  def members_for_tier(:dex), do: @dex_members

  @doc """
  Returns the priority tier for an exchange ID. Variants and aliases
  inherit their family root's tier.

      iex> CcxtOcx.Tiers.get_priority_tier("binance")
      :tier1

      iex> CcxtOcx.Tiers.get_priority_tier("binanceus")
      :tier1

      iex> CcxtOcx.Tiers.get_priority_tier("huobi")
      :tier2

      iex> CcxtOcx.Tiers.get_priority_tier("hyperliquid")
      :dex

      iex> CcxtOcx.Tiers.get_priority_tier("not_a_real_exchange")
      :unclassified
  """
  @spec get_priority_tier(String.t()) :: :tier1 | :tier2 | :tier3 | :dex | :unclassified
  def get_priority_tier(exchange_id) do
    Map.get(@tier_member_map, exchange_id, :unclassified)
  end

  @doc "True when `exchange_id` is a Tier 1 member (root or variant/alias)."
  @spec tier1?(String.t()) :: boolean()
  def tier1?(exchange_id), do: get_priority_tier(exchange_id) == :tier1

  @doc "True when `exchange_id` is a Tier 2 member (root or variant/alias)."
  @spec tier2?(String.t()) :: boolean()
  def tier2?(exchange_id), do: get_priority_tier(exchange_id) == :tier2

  @doc "True when `exchange_id` is a Tier 3 member (root or variant/alias)."
  @spec tier3?(String.t()) :: boolean()
  def tier3?(exchange_id), do: get_priority_tier(exchange_id) == :tier3

  @doc "True when `exchange_id` is a priority DEX member (root or variant/alias)."
  @spec dex?(String.t()) :: boolean()
  def dex?(exchange_id), do: get_priority_tier(exchange_id) == :dex

  @doc """
  Returns the human-readable display name for a tier.

      iex> CcxtOcx.Tiers.tier_display_name(:tier1)
      "TIER 1"

      iex> CcxtOcx.Tiers.tier_display_name(:dex)
      "DEX"
  """
  @spec tier_display_name(:tier1 | :tier2 | :tier3 | :dex) :: String.t()
  def tier_display_name(:tier1), do: "TIER 1"
  def tier_display_name(:tier2), do: "TIER 2"
  def tier_display_name(:tier3), do: "TIER 3"
  def tier_display_name(:dex), do: "DEX"

  @doc """
  True when any of `:tier1`, `:tier2`, `:tier3`, `:dex` is truthy in opts.

      iex> CcxtOcx.Tiers.has_tier_flags?(tier1: true)
      true

      iex> CcxtOcx.Tiers.has_tier_flags?(strict: true)
      false
  """
  @spec has_tier_flags?(keyword()) :: boolean()
  def has_tier_flags?(opts) do
    opts[:tier1] || opts[:tier2] || opts[:tier3] || opts[:dex] || false
  end

  @doc """
  Collects tier **members** (roots + variants/aliases) from all enabled
  tier flags, for use as a scope filter.

  Returns `{exchanges, label}` where `exchanges` is sorted-uniq and
  `label` is a header string like `"TIER 1 + DEX (14)"`. Empty opts
  return `{[], " (0)"}`.

      iex> {exchanges, _label} = CcxtOcx.Tiers.collect_tier_exchanges(tier1: true, dex: true)
      iex> "binance" in exchanges and "binanceus" in exchanges and "hyperliquid" in exchanges
      true
  """
  @spec collect_tier_exchanges(keyword()) :: {[String.t()], String.t()}
  def collect_tier_exchanges(opts) do
    tiers = Enum.filter([:tier1, :tier2, :tier3, :dex], fn tier -> opts[tier] end)

    exchanges =
      tiers
      |> Enum.flat_map(&members_for_tier/1)
      |> Enum.uniq()
      |> Enum.sort()

    label = build_tier_label(tiers, length(exchanges))
    {exchanges, label}
  end

  @spec build_tier_label([atom()], non_neg_integer()) :: String.t()
  defp build_tier_label(tiers, count) do
    tier_names = Enum.map_join(tiers, " + ", &tier_display_name/1)
    "#{tier_names} (#{count})"
  end
end
