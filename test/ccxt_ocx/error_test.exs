defmodule CcxtOcx.ErrorTest do
  # Needs a real QuickBEAM runtime for the integration-style error cases.
  use ExUnit.Case, async: false

  alias CcxtOcx.Error, as: E
  alias CcxtOcx.Runtime

  @bundle_path "node_modules/ccxt/dist/ccxt.browser.min.js"

  setup_all do
    if File.exists?(@bundle_path) do
      :ok
    else
      flunk("""
      ccxt browser bundle not found at #{@bundle_path}.

      Install ccxt before running these tests:
        npm install
      or, equivalently:
        mix npm.install ccxt
      """)
    end
  end

  describe "closed 9-tag taxonomy" do
    test "tags/0 returns exactly the nine canonical tags" do
      tags = E.tags()

      assert length(tags) == 9

      assert Enum.sort(tags) ==
               Enum.sort([
                 :bad_symbol,
                 :network,
                 :rate_limit,
                 :auth,
                 :not_found,
                 :permission,
                 :exchange,
                 :timeout,
                 :unknown
               ])
    end
  end

  describe "tag_for_ccxt_class/1" do
    test "maps well-known CCXT classes to the correct canonical tag" do
      assert E.tag_for_ccxt_class("BadSymbol") == :bad_symbol
      assert E.tag_for_ccxt_class("RateLimitExceeded") == :rate_limit
      assert E.tag_for_ccxt_class("DDoSProtection") == :rate_limit
      assert E.tag_for_ccxt_class("AuthenticationError") == :auth
      assert E.tag_for_ccxt_class("PermissionDenied") == :permission
      assert E.tag_for_ccxt_class("AccountSuspended") == :permission
      assert E.tag_for_ccxt_class("OrderNotFound") == :not_found
      assert E.tag_for_ccxt_class("RequestTimeout") == :timeout
      assert E.tag_for_ccxt_class("ExchangeError") == :exchange
      assert E.tag_for_ccxt_class("OperationRejected") == :exchange
    end

    test "unknown or future CCXT error classes fall back to :unknown" do
      assert E.tag_for_ccxt_class("FutureNewError") == :unknown
      assert E.tag_for_ccxt_class("CompletelyMadeUp") == :unknown
      assert E.tag_for_ccxt_class("BaseError") == :unknown
    end
  end

  describe "normalize/2 and from_js_error/2" do
    test "accepts a raw JS error map and injects context" do
      raw = %{"name" => "BadSymbol", "message" => "invalid symbol"}

      err =
        E.normalize(raw,
          exchange: :binance,
          method: "fetchTicker",
          meta: %{attempt: 1}
        )

      assert %E{
               tag: :bad_symbol,
               source: :js,
               source_name: "BadSymbol",
               exchange: :binance,
               method: "fetchTicker",
               original: ^raw,
               meta: %{attempt: 1}
             } = err
    end

    test "accepts a %QuickBEAM.JSError{} struct" do
      js_err = %QuickBEAM.JSError{
        name: "RateLimitExceeded",
        message: "rate limit",
        stack: "stack trace here"
      }

      err = E.from_js_error(js_err, exchange: :okx, method: "fetchOHLCV")

      assert err.tag == :rate_limit
      assert err.source == :js
      assert err.source_name == "RateLimitExceeded"
      assert err.exchange == :okx
      assert err.method == "fetchOHLCV"
      assert err.original == js_err
    end

    test "accepts a bare canonical tag (manual construction path)" do
      err = E.normalize(:not_found, exchange: :kraken, method: "fetchOrder")

      assert err.tag == :not_found
      assert err.source == :js
      assert err.source_name == "tag:not_found"
      assert err.exchange == :kraken
    end

    test "accepts an already-built Error struct and merges additional context" do
      base = E.normalize("OrderNotFound", exchange: :bybit)

      enriched =
        E.normalize(base,
          method: "cancelOrder",
          meta: %{order_id: "123"}
        )

      assert enriched.tag == :not_found
      assert enriched.exchange == :bybit
      assert enriched.method == "cancelOrder"
      assert enriched.meta == %{order_id: "123"}
    end

    test "preserves original payload when provided explicitly" do
      raw = %{"name" => "AuthenticationError", "code" => 401}
      err = E.normalize(raw, exchange: :binance, original: %{sanitized: true})

      assert err.original == %{sanitized: true}
    end
  end

  describe "Exception behaviour" do
    test "implements message/1 usefully" do
      err = E.normalize("PermissionDenied", exchange: :coinbase, method: "createOrder")

      assert Exception.message(err) =~ "[permission]"
      assert Exception.message(err) =~ "coinbase.createOrder"
    end

    test "can be raised and rescued as CcxtOcx.Error" do
      assert_raise E, ~r/\[auth\].*js:AuthenticationError/, fn ->
        raise E.normalize("AuthenticationError", exchange: :ftx)
      end
    end
  end

  describe "parse_ccxt_classes/1 (compile-time gate logic)" do
    test "extracts every concrete `declare class Foo extends Bar` name" do
      content = """
      declare class BaseError extends Error {
          constructor(message: string);
      }
      declare class BadSymbol extends BadRequest {
          constructor(message: string);
      }
      declare class RateLimitExceeded extends NetworkError {
          constructor(message: string);
      }
      """

      classes = E.parse_ccxt_classes(content)

      assert "BaseError" in classes
      assert "BadSymbol" in classes
      assert "RateLimitExceeded" in classes
    end

    test "ignores `_default` and other non-`extends` declarations" do
      content = """
      declare class BadSymbol extends BadRequest {
          constructor(message: string);
      }
      declare const _default: {
          BadSymbol: typeof BadSymbol;
      };
      """

      assert E.parse_ccxt_classes(content) == ["BadSymbol"]
    end

    test "detects unmapped classes (proves the gate would fire on drift)" do
      content = """
      declare class BadSymbol extends BadRequest {
          constructor(message: string);
      }
      declare class BrandNewError extends ExchangeError {
          constructor(message: string);
      }
      """

      missing = E.parse_ccxt_classes(content) -- Map.keys(E.ccxt_to_tag_for_test())

      assert "BrandNewError" in missing
      refute "BadSymbol" in missing
    end

    test "every class in the real errors.d.ts is mapped in @ccxt_to_tag" do
      path = "node_modules/ccxt/js/src/base/errors.d.ts"

      # If the bundle isn't installed (CI without `npm install`), skip rather
      # than flunk — setup_all at the top of this module already enforces the
      # `ccxt.browser.min.js` presence check for the integration tests below.
      if File.exists?(path) do
        classes = E.parse_ccxt_classes(File.read!(path))
        missing = classes -- Map.keys(E.ccxt_to_tag_for_test())

        assert missing == [],
               """
               These CCXT error classes are declared upstream but missing from
               @ccxt_to_tag. The compile-time gate should have caught this:

                   #{inspect(missing)}
               """
      end
    end
  end

  describe "from_js_error/2 defensive coercion" do
    test "non-binary `:name` (atom) does not crash — normalizes to :unknown" do
      raw = %{"name" => :rate_limit_exceeded, "message" => "weird shape"}

      err = E.from_js_error(raw)

      assert err.tag == :unknown
      assert err.source_name == "Error"
      assert err.original == raw
    end

    test "non-binary `:name` (integer) does not crash — normalizes to :unknown" do
      raw = %{"name" => 42, "message" => "very weird shape"}

      err = E.from_js_error(raw)

      assert err.tag == :unknown
      assert err.source_name == "Error"
    end

    test "missing `:name` entirely falls back to \"Error\"" do
      raw = %{"message" => "no name field"}

      err = E.from_js_error(raw)

      assert err.tag == :unknown
      assert err.source_name == "Error"
    end

    test "from_js_error/2 with a non-map/non-JSError term (last-resort fallback)" do
      err = E.from_js_error("just a string", exchange: :binance)

      assert err.tag == :unknown
      assert err.source == :js
      assert err.source_name == "Error"
      assert err.original == "just a string"
      assert err.exchange == :binance
    end
  end

  describe "normalize/2 fallback paths" do
    test "arbitrary string not in @ccxt_to_tag and not ending in \"Error\" goes to original" do
      err = E.normalize("totally arbitrary payload")

      assert err.tag == :unknown
      assert err.source_name == "Error"
      assert err.original == "totally arbitrary payload"
    end

    test "string ending in \"Error\" but not in @ccxt_to_tag treated as CCXT class" do
      err = E.normalize("SomeFutureMadeUpError")

      assert err.tag == :unknown
      assert err.source_name == "SomeFutureMadeUpError"
      # Treated as a class name — original stays nil
      assert err.original == nil
    end

    test "non-supported term (atom not in @tags) falls through to last-resort" do
      err = E.normalize(:not_a_canonical_tag, exchange: :binance)

      assert err.tag == :unknown
      assert err.source == :js
      assert err.original == :not_a_canonical_tag
      assert err.exchange == :binance
    end
  end

  describe "Exception protocol callbacks" do
    test "Exception.exception/1 routes through normalize/1" do
      # The `Exception` behaviour's exception/1 is called by `raise/1` when
      # given a non-struct term.
      err = E.exception(:rate_limit)

      assert err.tag == :rate_limit
      assert err.source_name == "tag:rate_limit"
    end

    test "message/1 renders the exchange-only context shape" do
      err = E.normalize(:auth, exchange: :binance)
      assert Exception.message(err) == "[auth] js:tag:auth (binance)"
    end

    test "message/1 renders the method-only context shape" do
      err = E.normalize(:auth, method: "createOrder")
      assert Exception.message(err) == "[auth] js:tag:auth (createOrder)"
    end

    test "message/1 renders the no-context shape" do
      err = E.normalize(:auth)
      assert Exception.message(err) == "[auth] js:tag:auth"
    end
  end

  describe "real CCXT JS errors via QuickBEAM runtime" do
    setup do
      {:ok, server} = Runtime.start_link([])
      on_exit(fn -> if Process.alive?(server), do: Runtime.stop(server) end)
      {:ok, server: server}
    end

    # We exercise the error path by asking CCXT to construct one of its
    # typed error objects directly. This is reliable, does not require
    # network or credentials, and produces real instances of the classes
    # defined in errors.d.ts.
    test "CCXT BadSymbol error normalizes correctly", %{server: server} do
      # ccxt.base.errors.BadSymbol is the constructor exposed on the bundle
      script = """
      const { BadSymbol } = self.ccxt;
      const e = new BadSymbol("symbol foo/bar is invalid");
      ({ name: e.name, message: e.message });
      """

      {:ok, raw} = Runtime.eval(server, script)

      err = E.normalize(raw, exchange: :binance, method: "fetchTicker")

      assert err.tag == :bad_symbol
      assert err.source == :js
      assert err.source_name == "BadSymbol"
      assert err.exchange == :binance
      assert err.method == "fetchTicker"
      assert is_map(err.original)
    end

    test "CCXT RateLimitExceeded error normalizes correctly", %{server: server} do
      script = """
      const { RateLimitExceeded } = self.ccxt;
      const e = new RateLimitExceeded("rate limit hit");
      ({ name: e.name, message: e.message });
      """

      {:ok, raw} = Runtime.eval(server, script)

      err = E.normalize(raw, exchange: :bybit, method: "fetchBalance")

      assert err.tag == :rate_limit
      assert err.source_name == "RateLimitExceeded"
      assert err.exchange == :bybit
    end

    test "CCXT AuthenticationError error normalizes correctly", %{server: server} do
      script = """
      const { AuthenticationError } = self.ccxt;
      const e = new AuthenticationError("api key invalid");
      ({ name: e.name, message: e.message });
      """

      {:ok, raw} = Runtime.eval(server, script)

      err = E.normalize(raw, exchange: :okx)

      assert err.tag == :auth
      assert err.source_name == "AuthenticationError"
    end
  end
end
