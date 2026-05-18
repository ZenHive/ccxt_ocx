defmodule CcxtOcx.Trade do
  @moduledoc """
  Canonical struct for `fetchTrades` / `watchTrades` items.

  Real example (live capture):

      iex> raw = %{
      ...>   "symbol" => "BTC/USDT:USDT",
      ...>   "price" => 76901.9,
      ...>   "amount" => 0.001,
      ...>   "side" => "sell",
      ...>   "info" => %{"m" => true, ...}
      ...> }
      iex> t = CcxtOcx.Trade.from_ccxt(raw)
      iex> t.price
      "76901.9"
      iex> t.amount
      "0.001"
      iex> is_map(t.info)
      true
  """
  use CcxtOcx.Struct

  field(:id, :string, from: "id")
  field(:timestamp, :timestamp_ms, from: "timestamp")
  field(:datetime, :string, from: "datetime")
  field(:symbol, :string, from: "symbol")
  field(:order, :string, from: "order")
  field(:type, :string, from: "type")
  field(:side, :string, from: "side")
  field(:price, :money_string, from: "price")
  field(:amount, :money_string, from: "amount")
  field(:cost, :money_string, from: "cost")
  field(:taker_or_maker, :string, from: "takerOrMaker")
  # fee and info are passed through as raw maps (numbers inside acceptable for v0.1)
  field(:fee, :map, from: "fee")
  field(:info, :map, from: "info")
end
