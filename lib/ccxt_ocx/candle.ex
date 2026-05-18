defmodule CcxtOcx.Candle do
  @moduledoc """
  Struct for OHLCV / Candle data.

  CCXT returns `OHLCV = [timestamp, open, high, low, close, volume]` (or 7-tuple OHLCVC).
  This struct maps the positional list to named fields with money strings for prices/volume.

  Real example (captured live):

      iex> raw = [1779096360000, 76938.6, 76945.4, 76918.2, 76918.3, 39.009]
      iex> c = CcxtOcx.Candle.from_ccxt(raw)
      iex> c.open
      "76938.6"
      iex> c.close
      "76918.3"
      iex> c.timestamp
      1779096360000
  """
  @enforce_keys []
  defstruct [:timestamp, :open, :high, :low, :close, :volume]

  @type t :: %__MODULE__{
          timestamp: integer() | nil,
          open: String.t() | nil,
          high: String.t() | nil,
          low: String.t() | nil,
          close: String.t() | nil,
          volume: String.t() | nil
        }

  @doc """
  Hydrates a raw CCXT OHLCV value into a `%CcxtOcx.Candle{}`.

  Accepts:
  - `nil`
  - An already-hydrated `%CcxtOcx.Candle{}` (idempotent)
  - A raw positional list (the form CCXT actually returns for `fetchOHLCV`)

  This is the function called by `CcxtOcx.Structs.hydrate/2` and by
  `defunified` for `fetch_ohlcv` / `watch_ohlcv` methods.
  """
  @spec from_ccxt([term()] | t() | nil) :: t() | nil
  def from_ccxt(nil), do: nil
  def from_ccxt(%__MODULE__{} = c), do: c
  def from_ccxt(list) when is_list(list), do: from_list(list)

  @doc """
  Low-level converter from a raw CCXT OHLCV tuple (list) to `%CcxtOcx.Candle{}`.

  Converts the six (or seven) positional values and applies the standard
  money/timestamp normalizations.
  """
  @spec from_list([term()]) :: t() | nil
  def from_list([ts, o, h, l, c, v | _rest]) do
    %__MODULE__{
      timestamp: CcxtOcx.Struct.normalize(ts, :timestamp_ms),
      open: CcxtOcx.Struct.normalize(o, :money_string),
      high: CcxtOcx.Struct.normalize(h, :money_string),
      low: CcxtOcx.Struct.normalize(l, :money_string),
      close: CcxtOcx.Struct.normalize(c, :money_string),
      volume: CcxtOcx.Struct.normalize(v, :money_string)
    }
  end

  def from_list(_), do: nil
end
