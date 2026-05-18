defmodule CcxtOcx.OrderBook do
  @moduledoc """
  Canonical struct for `fetchOrderBook` / `watchOrderBook` returns.

  `bids` and `asks` are lists of `[price, size]` pairs. In v0.1 the inner
  values are passed through as the raw numbers CCXT emits; stringifying them
  to match the rest of the money-field contract is tracked as a follow-up.

  TODO: stringify bid/ask `[price, size]` pairs to honor the same money-string
  contract used by `:money_string` fields elsewhere (Ticker, Trade, Candle).

  Example shape (BTC/USDT:USDT, live capture):

      %{
        "symbol" => "BTC/USDT:USDT",
        "bids" => [[76899.9, 13.439], [76899.8, 0.37]],
        "asks" => [[76900, 1.009], [76900.1, 0.002]]
      }
  """
  use CcxtOcx.Struct

  field(:symbol, :string, from: "symbol")
  field(:timestamp, :timestamp_ms, from: "timestamp")
  field(:datetime, :string, from: "datetime")
  field(:nonce, :integer, from: "nonce")
  # TODO: bids/asks arrive as [[Num, Num], ...] from CCXT and are passed
  # through untouched for v0.1; see moduledoc.
  field(:bids, :list, from: "bids")
  field(:asks, :list, from: "asks")
end
