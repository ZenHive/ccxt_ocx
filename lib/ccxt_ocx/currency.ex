defmodule CcxtOcx.Currency do
  @moduledoc """
  Canonical struct for currency metadata.

  Fee schedules, network limits, and venue-specific details are typically
  found inside the `info` and `networks` maps.
  """
  use CcxtOcx.Struct

  field(:id, :string, from: "id")
  field(:code, :string, from: "code")
  field(:numeric_id, :integer, from: "numericId")
  field(:precision, :integer, from: "precision")
  field(:name, :string, from: "name")
  field(:active, :bool, from: "active")
  field(:deposit, :bool, from: "deposit")
  field(:withdraw, :bool, from: "withdraw")
  field(:fee, :money_string, from: "fee")
  field(:info, :map, from: "info")
  field(:limits, :map, from: "limits")
  field(:networks, :map, from: "networks")
end
