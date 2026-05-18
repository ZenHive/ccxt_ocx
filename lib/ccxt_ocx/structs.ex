defmodule CcxtOcx.Structs do
  @moduledoc """
  Registry + hydration facade for the Task 8 typed structs (v0.1 data plane).

  Consumed by `defunified` (Task 7) so that a single call site can turn a raw
  CCXT-shaped term (map or list) into the correct canonical struct without
  duplicating the "return_type string → module" table in every macro expansion.

  Public for tests and dogfooding; the main surface for callers is still the
  individual `CcxtOcx.Ticker.from_ccxt/1` etc. functions.
  """

  alias CcxtOcx.Candle
  alias CcxtOcx.Currency
  alias CcxtOcx.Market
  alias CcxtOcx.OrderBook
  alias CcxtOcx.Ticker
  alias CcxtOcx.Trade

  @type return_type :: String.t()
  @type raw :: map() | list() | nil

  @registry %{
    "Ticker" => Ticker,
    "OrderBook" => OrderBook,
    "Trade" => Trade,
    "Market" => Market,
    "Currency" => Currency,
    "OHLCV" => Candle,
    "OHLCVC" => Candle
  }

  @doc """
  Hydrate a raw CCXT value according to the declared return type string
  (e.g. "Promise<Ticker>", "Trade[]", "OHLCV[]").

  Returns the struct (or list of structs) or the raw value unchanged if the
  type is not one of the 6 we know how to hydrate.
  """
  @spec hydrate(return_type(), raw()) :: term()
  def hydrate(type_str, raw) when is_binary(type_str) do
    # Strip Promise<...> or other single-wrapper first so `Promise<Trade[]>`
    # collapses to `Trade[]` BEFORE the array branch tries to strip `[]>`.
    # Earlier shape stripped `[].*$` first, leaving `"Promise<Trade"` and
    # silently returning raw data for every `Promise<X[]>` return type.
    unwrapped =
      type_str
      |> String.replace(~r/^Promise<(.+)>$/, "\\1")
      |> String.replace(~r/^(.+)<(.+)>$/, "\\2")

    if String.ends_with?(unwrapped, "[]") do
      base = String.replace_suffix(unwrapped, "[]", "")
      mod = Map.get(@registry, base)

      if mod && raw do
        Enum.map(List.wrap(raw), &mod.from_ccxt/1)
      else
        raw
      end
    else
      case Map.get(@registry, unwrapped) do
        nil -> raw
        mod -> mod.from_ccxt(raw)
      end
    end
  end

  def hydrate(_type_str, raw), do: raw

  @doc "The internal registry (useful for tests and docs generation)."
  @spec registry() :: %{optional(String.t()) => module()}
  def registry, do: @registry

  @doc "List of struct modules we know how to hydrate."
  @spec known_structs() :: [module()]
  def known_structs, do: @registry |> Map.values() |> Enum.uniq()
end
