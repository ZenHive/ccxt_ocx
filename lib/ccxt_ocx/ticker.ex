defmodule CcxtOcx.Ticker do
  @moduledoc """
  Canonical Elixir struct for unified `fetchTicker` / `watchTicker` returns.

  All money/price/volume fields are strings (never floats or bare numbers) to
  preserve precision. `timestamp` is an integer millisecond epoch or nil.

  ## Field mapping (CCXT `Ticker` interface)

  - `symbol` → `:string`
  - price fields (`last`, `bid`, `ask`, `high`, `low`, `open`, `close`, `vwap`, ...) → `:money_string`
  - `timestamp` → `:timestamp_ms`
  - `info` → `:map` (opaque venue response, untouched)

  ## Example

  Real data captured via Tidewave + live QuickBEAM runtime (Binance USDT-M):

      iex> raw = %{
      ...>   "symbol" => "BTC/USDT:USDT",
      ...>   "timestamp" => 1779096435424,
      ...>   "last" => 76888.9,
      ...>   "bid" => 76899.9,
      ...>   "info" => %{"lastPrice" => "76888.90"}
      ...> }
      iex> t = CcxtOcx.Ticker.from_ccxt(raw)
      iex> t.last
      "76888.9"
      iex> t.bid
      "76899.9"
      iex> t.timestamp
      1779096435424
      iex> is_map(t.info)
      true
  """
  use CcxtOcx.Struct

  field(:symbol, :string, from: "symbol")
  field(:timestamp, :timestamp_ms, from: "timestamp")
  field(:datetime, :string, from: "datetime")
  field(:high, :money_string, from: "high")
  field(:low, :money_string, from: "low")
  field(:bid, :money_string, from: "bid")
  field(:bid_volume, :money_string, from: "bidVolume")
  field(:ask, :money_string, from: "ask")
  field(:ask_volume, :money_string, from: "askVolume")
  field(:vwap, :money_string, from: "vwap")
  field(:open, :money_string, from: "open")
  field(:close, :money_string, from: "close")
  field(:last, :money_string, from: "last")
  field(:previous_close, :money_string, from: "previousClose")
  field(:change, :money_string, from: "change")
  field(:percentage, :money_string, from: "percentage")
  field(:average, :money_string, from: "average")
  field(:quote_volume, :money_string, from: "quoteVolume")
  field(:base_volume, :money_string, from: "baseVolume")
  field(:index_price, :money_string, from: "indexPrice")
  field(:mark_price, :money_string, from: "markPrice")
  field(:info, :map, from: "info")
end
