# IEx auto-attach for ccxt_ocx maintainer dogfooding.
#
# Guarded so it only fires in :dev — `mix test` and any prod release path
# stay untouched. Also guarded on `Code.ensure_loaded?/1` so a stripped
# release (where CcxtOcx.DevTelemetry might be filtered out) doesn't blow
# up the shell.

if Mix.env() == :dev and Code.ensure_loaded?(CcxtOcx.DevTelemetry) do
  CcxtOcx.DevTelemetry.watch()

  IO.puts("""
  📡 CcxtOcx.DevTelemetry attached.
     Call `CcxtOcx.DevTelemetry.summary/0` anytime to see counts + last values.
     `reset/0` clears, `detach/0` stops counting. See docs/tidewave_examples.md.
  """)
end
