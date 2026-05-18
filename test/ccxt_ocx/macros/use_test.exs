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
  # This now triggers real (cached) probes via defexchange, so the describe
  # block is tagged :integration.
  @moduletag :integration

  defmodule ScopedConsumer do
    @moduledoc false
    use CcxtOcx, exchanges: [:deribit, :binance]
  end

  test "use emits real per-exchange modules with the Task 9 capability surface" do
    assert Code.ensure_loaded?(CcxtOcx.Deribit)
    assert Code.ensure_loaded?(CcxtOcx.Binance)

    assert CcxtOcx.Deribit.__exchange_id__() == :deribit
    assert CcxtOcx.Binance.__exchange_id__() == :binance

    # Task 9 surface (replaces the old 6b marker)
    refute function_exported?(CcxtOcx.Deribit, :__generated_by_task_6b__, 0)
    assert function_exported?(CcxtOcx.Binance, :has?, 1)
    assert CcxtOcx.Binance.has?("fetchTicker") == true
    assert CcxtOcx.Binance.has?("createOrder") == true
    assert CcxtOcx.Binance.has?("nonexistentMethod") == false
    assert is_map(CcxtOcx.Binance.urls())
    assert is_map(CcxtOcx.Binance.timeframes())
    assert is_struct(CcxtOcx.Binance.exchange(), CcxtOcx.Binance.Exchange)

    # has_table available for Task 7 compile-time gating
    has = CcxtOcx.Binance.has_table()
    assert is_map(has)
    assert has["fetchTicker"] in [true, "emulated"]

    # Per-module emission is a global side-effect on the BEAM, so refuting a
    # specific module's existence would be brittle across test files (any future
    # `use CcxtOcx, tier: :tier1` in another suite would load the same modules).
    # Scope-limiting is verified at the resolver level in the "explicit list is
    # normalized" test above.
  end

  # Scope attribute on the caller is a future extension point (see __using__ docs).
  # For v0.1 the important contract is the emitted per-exchange modules.

  # The QuickBEAM probe integration for `CcxtOcx.Macros.ExchangeCaps` lives in
  # `exchange_caps_integration_test.exs` — `async: false, @moduletag :integration`
  # since it boots a runtime and writes to `priv/exchange_caps/`.

  # Pure rejection path — no QuickBEAM, no filesystem touch. Verifies the trust
  # boundary added in Task 6b: fetch_or_build/1 rejects atoms outside the
  # known-exchange-id set BEFORE the path is built or Code.eval_file/1 runs.
  describe "ExchangeCaps.fetch_or_build/1 input validation" do
    alias CcxtOcx.Macros.ExchangeCaps

    test "raises ArgumentError on an unknown exchange id" do
      assert_raise ArgumentError, ~r/unknown exchange id/, fn ->
        ExchangeCaps.fetch_or_build(:not_a_real_exchange)
      end
    end

    test "raises ArgumentError on an atom that would traverse the path" do
      assert_raise ArgumentError, ~r/unknown exchange id/, fn ->
        ExchangeCaps.fetch_or_build(:"../../tmp/pwn")
      end
    end
  end
end
