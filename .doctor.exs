%Doctor.Config{
  ignore_modules: [
    # Doctor (as of 0.23) does not recognize `@doc`/`@spec` on `defmacro` —
    # `Code.fetch_docs(CcxtOcx.Struct)` confirms every macro IS documented
    # and spec'd, but Doctor's parser only credits `def`. Exempt this single
    # macro-DSL module; the rest of the codebase stays at the 100% bar.
    CcxtOcx.Struct
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
