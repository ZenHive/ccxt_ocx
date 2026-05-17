defmodule CcxtOcx.Macros.UseTest do
  use ExUnit.Case, async: true

  alias CcxtOcx.Declarations
  alias CcxtOcx.Macros.Use

  # Pure (no JS) tests for the resolver and schema — can run in any mix env.
  describe "validate_and_normalize/2 (pure)" do
    defp caller, do: %{file: "test.exs", line: 42, module: __MODULE__}

    test "bare use (no opts) raises actionable CompileError (Option A policy)" do
      assert_raise CompileError, ~r/requires explicit scope/, fn ->
        Use.validate_and_normalize([], caller())
      end
    end

    test "unknown key raises via NimbleOptions (when a valid key is also present)" do
      assert_raise CompileError, ~r/unknown options/, fn ->
        Use.validate_and_normalize([exchanges: [:binance], foo: :bar], caller())
      end
    end

    test "mutually exclusive :exchanges + :tier raises clear error" do
      assert_raise CompileError, ~r/mutually exclusive/, fn ->
        Use.validate_and_normalize([exchanges: [:deribit], tier: :tier1], caller())
      end
    end

    test "explicit list is normalized, sorted, deduped" do
      scope = Use.validate_and_normalize([exchanges: [:deribit, :binance, :deribit]], caller())
      assert scope.mode == :explicit
      assert scope.exchanges == [:binance, :deribit]
      assert scope.source == [exchanges: [:deribit, :binance, :deribit]]
    end

    test "tier: :tier1 expands via Tiers" do
      scope = Use.validate_and_normalize([tier: :tier1], caller())
      assert scope.mode == :tier
      assert :binance in scope.exchanges
      assert :deribit in scope.exchanges
      assert length(scope.exchanges) >= 5
    end

    test "exchanges: :all is accepted (warning emitted at use site)" do
      scope = Use.validate_and_normalize([exchanges: :all], caller())
      # `:all` is eagerly expanded to the full known-exchange list — the
      # `mode` field is the canonical discriminator, `exchanges` is always [atom()].
      assert scope.mode == :all
      assert is_list(scope.exchanges)
      assert :binance in scope.exchanges
      assert length(scope.exchanges) > 50
    end

    test "empty explicit list is rejected" do
      assert_raise CompileError, ~r/not allowed/, fn ->
        Use.validate_and_normalize([exchanges: []], caller())
      end
    end
  end

  describe "unknown exchange id + did-you-mean" do
    test "suggests close matches" do
      assert_raise CompileError, ~r/did you mean \[:binance/, fn ->
        Use.validate_and_normalize([exchanges: [:binanse]], %{file: "t.exs", line: 1, module: __MODULE__})
      end
    end

    test "known_exchange_ids is non-empty and contains tier-1 roots" do
      ids = Declarations.known_exchange_ids()
      assert is_list(ids)
      assert length(ids) > 50
      assert :binance in ids
      assert :deribit in ids
      assert :okx in ids
    end
  end

  # ----------------------------------------------------------------------------
  # Integration: exercising the actual `use CcxtOcx` macro (emits real modules)
  # ----------------------------------------------------------------------------

  # We define a tiny "consumer" module inside the test so that the `use` runs
  # at test-compile time and the generated CcxtOcx.* modules become visible.
  defmodule ScopedConsumer do
    @moduledoc false
    use CcxtOcx, exchanges: [:deribit, :binance]
  end

  test "use emits real per-exchange modules with the expected contract" do
    assert Code.ensure_loaded?(CcxtOcx.Deribit)
    assert Code.ensure_loaded?(CcxtOcx.Binance)

    assert CcxtOcx.Deribit.__exchange_id__() == :deribit
    assert CcxtOcx.Binance.__exchange_id__() == :binance
    assert function_exported?(CcxtOcx.Deribit, :__generated_by_task_6b__, 0)
    # Per-module emission is a global side-effect on the BEAM, so refuting a
    # specific module's existence would be brittle across test files (any future
    # `use CcxtOcx, tier: :tier1` in another suite would load the same modules).
    # Scope-limiting is verified at the resolver level in the "explicit list is
    # normalized" test above.
  end

  # Scope attribute on the caller is a future extension point (see __using__ docs).
  # For v0.1 the important contract is the emitted per-exchange modules.

  # ----------------------------------------------------------------------------
  # Integration exercise for the ExchangeCaps helper (Task 6b prep for Task 9)
  # ----------------------------------------------------------------------------
  # This test actually boots a QuickBEAM, loads the CCXT browser bundle, and
  # probes a real exchange. It is intentionally separate so the pure resolver
  # tests stay fast. The first run creates the cache artifact under
  # priv/exchange_caps/; subsequent runs hit the fast path.
  describe "CcxtOcx.Macros.ExchangeCaps (probe integration)" do
    alias CcxtOcx.Macros.ExchangeCaps

    test "fetch_or_build/1 returns shaped map and materializes cache file" do
      id = :deribit
      caps = ExchangeCaps.fetch_or_build(id)

      assert caps.id == id
      assert is_map(caps.has)
      assert is_map(caps.urls)
      assert is_map(caps.timeframes)
      assert caps.rate_limit == nil or is_integer(caps.rate_limit)
      assert caps.default_type == nil or is_binary(caps.default_type)

      path = ExchangeCaps.caps_path(id)
      assert File.exists?(path)

      # The file is a pretty-printed .exs that Code.eval_file can read (already
      # proven by the read path inside fetch_or_build on second call).
      {reloaded, _} = Code.eval_file(path)
      assert reloaded.id == id
    end
  end
end
