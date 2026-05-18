defmodule CcxtOcx.Macros.ExchangeCapsIntegrationTest do
  # async: false — boots a QuickBEAM runtime + writes to priv/exchange_caps/,
  # both global side effects unsafe to run concurrently with peers.
  # @moduletag :integration — excluded from the default offline suite (see
  # test/test_helper.exs); opt in with `mix test --include integration`.
  use ExUnit.Case, async: false

  alias CcxtOcx.Macros.ExchangeCaps

  @moduletag :integration

  describe "fetch_or_build/1 (probe)" do
    test "returns shaped map and materializes cache file" do
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
