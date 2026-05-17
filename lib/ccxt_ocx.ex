defmodule CcxtOcx do
  @moduledoc """
  ccxt_ocx — macro-first Elixir wrapper around CCXT running inside QuickBEAM.

  ## Telemetry

  All instrumentation is under the `[:ccxt_ocx]` prefix.

  - `[:ccxt_ocx, :runtime, :memory]` — emitted by `CcxtOcx.Runtime.memory/1`,
    `CcxtOcx.RuntimePool.memory/1`, and at worker init/terminate.
  - `[:ccxt_ocx, :rest, :start|stop|exception]` and `[:ccxt_ocx, :ws, :tick]`
    are reserved for the Phase 2/3 macro layers.

  See `CcxtOcx.Telemetry` for the full contract, shapes, and examples.
  """
end
