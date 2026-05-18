defmodule CcxtOcx.Market do
  @moduledoc """
  Canonical struct for market metadata (from `loadMarkets` / `fetchMarkets`).

  Most of the interesting per-market configuration lives in the nested
  `precision`, `limits`, and especially the opaque `info` map.
  """
  use CcxtOcx.Struct

  field(:id, :string, from: "id")
  field(:symbol, :string, from: "symbol")
  field(:base, :string, from: "base")
  field(:quote, :string, from: "quote")
  field(:type, :string, from: "type")
  field(:spot, :bool, from: "spot")
  field(:swap, :bool, from: "swap")
  field(:future, :bool, from: "future")
  field(:option, :bool, from: "option")
  field(:active, :bool, from: "active")
  field(:info, :map, from: "info")
  # precision and limits are nested maps — treat as :map for v0.1
  field(:precision, :map, from: "precision")
  field(:limits, :map, from: "limits")
end
