%Doctor.Config{
  ignore_modules: [
    # Doctor (as of 0.23) does not recognize `@doc`/`@spec` on `defmacro` or
    # on `def`s emitted from inside `quote` blocks — `Code.fetch_docs/1` on
    # consumer modules confirms every emitted function IS documented and
    # spec'd, but Doctor's parser walks source and only credits inline `def`.
    # Exempt these macro-DSL modules; the rest of the codebase stays at the
    # 100% bar.
    CcxtOcx.Struct,
    CcxtOcx.Macros.Exchange
  ],
  ignore_paths: [],
  min_module_doc_coverage: 100,
  min_module_spec_coverage: 100,
  min_overall_doc_coverage: 100,
  min_overall_spec_coverage: 100,
  min_overall_moduledoc_coverage: 100,
  exception_moduledoc_required: true,
  raise: false,
  reporter: Doctor.Reporters.Full,
  struct_type_spec_required: true,
  umbrella: false,
  failed: false
}
