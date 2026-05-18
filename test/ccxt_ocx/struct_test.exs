defmodule CcxtOcx.StructTest do
  use ExUnit.Case, async: true

  alias CcxtOcx.Candle
  alias CcxtOcx.Currency
  alias CcxtOcx.Declarations.Compile
  alias CcxtOcx.Market
  alias CcxtOcx.OrderBook
  alias CcxtOcx.Struct
  alias CcxtOcx.Structs
  alias CcxtOcx.Ticker
  alias CcxtOcx.Trade

  doctest Ticker
  doctest Candle

  describe "normalize/2 (pure)" do
    test "money_string converts numbers and keeps strings, nil stays nil" do
      assert Struct.normalize(123.456, :money_string) == "123.456"
      assert Struct.normalize(100, :money_string) in ["100", "100.0"]
      assert Struct.normalize("99.99", :money_string) == "99.99"
      assert Struct.normalize(nil, :money_string) == nil
    end

    test "timestamp_ms and integer truncate and parse strings" do
      assert Struct.normalize(1_712_345_678_900.7, :timestamp_ms) == 1_712_345_678_900
      assert Struct.normalize("123", :integer) == 123
      assert Struct.normalize(nil, :timestamp_ms) == nil
    end
  end

  describe "Ticker hydration" do
    test "happy path from realistic CCXT-shaped map" do
      raw = %{
        "symbol" => "BTC/USDT:USDT",
        "last" => 67_234.5,
        "bid" => 67_230.0,
        "timestamp" => 1_712_345_678_000,
        "info" => %{"raw" => true}
      }

      t = Ticker.from_ccxt(raw)
      assert %Ticker{} = t
      assert t.symbol == "BTC/USDT:USDT"
      assert t.last == "67234.5"
      # normalize trims .0 for whole numbers
      assert t.bid in ["67230", "67230.0"]
      assert t.timestamp == 1_712_345_678_000
      assert t.info == %{"raw" => true}
    end

    test "missing keys become nil, extra keys ignored" do
      raw = %{"symbol" => "X", "last" => 1, "unknown" => 42}
      t = Ticker.from_ccxt(raw)
      assert t.symbol == "X"
      assert t.last in ["1", "1.0"]
      assert t.bid == nil
      # extra key not on struct
      refute Map.has_key?(Map.from_struct(t), :unknown)
    end
  end

  describe "Candle (positional OHLCV)" do
    test "from_list maps 6-tuple with conversions" do
      c = Candle.from_list([1_700_000_000_000, 10.1, 10.5, 9.9, 10.2, 123.45])
      assert c.timestamp == 1_700_000_000_000
      assert c.open == "10.1"
      assert c.volume == "123.45"
    end

    test "from_ccxt accepts list and delegates" do
      c = Candle.from_ccxt([0, 1, 2, 3, 4, 5, 6])
      assert c.close in ["4", "4.0"]
    end
  end

  describe "OrderBook / Trade (list-of-pairs and nested map)" do
    test "OrderBook keeps list shape (numbers left for v0.1)" do
      ob = OrderBook.from_ccxt(%{"bids" => [[1, 2], [3, 4]], "asks" => []})
      assert is_list(ob.bids)
    end

    test "Trade passes fee/info through as maps" do
      t = Trade.from_ccxt(%{"price" => 10, "fee" => %{"cost" => 0.1}, "info" => %{}})
      assert t.price in ["10", "10.0"]
      assert t.fee == %{"cost" => 0.1}
    end
  end

  describe "Structs facade (hydrate/2)" do
    test "dispatches Ticker and list forms" do
      t = Structs.hydrate("Ticker", %{"last" => 1})
      assert t.last in ["1", "1.0"]
      assert [%Trade{}] = Structs.hydrate("Trade[]", [%{"price" => 2}])
      assert [%Candle{}] = Structs.hydrate("OHLCV[]", [[1, 2, 3, 4, 5, 6]])
    end

    test "unknown types pass through" do
      assert "raw" == Structs.hydrate("FooBar", "raw")
    end
  end

  describe "introspection gate (Task 8 drift prevention)" do
    test "declared from: keys cover the CCXT interface for core structs" do
      # For each core interface we parse the real .d.ts and require that every
      # non-info/non-nested key we care about has a corresponding field decl.
      for intf <- Compile.core_struct_interfaces() do
        interface_keys =
          intf
          |> Compile.interface_fields()
          |> MapSet.new(& &1.name)

        # The struct modules we generated declare a subset; we only assert that
        # the ones we *did* declare exist in the interface (one-way coverage).
        # This catches accidental renames on our side after a bundle bump.
        case_result =
          case intf do
            "Ticker" -> Enum.map(Ticker.__ccxt_fields__(), fn {_, _, f} -> f end)
            "OrderBook" -> Enum.map(OrderBook.__ccxt_fields__(), fn {_, _, f} -> f end)
            "Trade" -> Enum.map(Trade.__ccxt_fields__(), fn {_, _, f} -> f end)
            "MarketInterface" -> Enum.map(Market.__ccxt_fields__(), fn {_, _, f} -> f end)
            "CurrencyInterface" -> Enum.map(Currency.__ccxt_fields__(), fn {_, _, f} -> f end)
            _ -> []
          end

        declared_froms = MapSet.new(case_result)

        missing = MapSet.difference(declared_froms, interface_keys)

        assert MapSet.size(missing) == 0,
               "Struct for #{intf} declares from keys not present in types.d.ts: #{inspect(missing)}"
      end
    end
  end
end
