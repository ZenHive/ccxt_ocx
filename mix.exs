defmodule CcxtOcx.MixProject do
  use Mix.Project

  def project do
    [
      app: :ccxt_ocx,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      dialyzer: [
        plt_add_deps: :apps_direct,
        plt_add_apps: [:mix],
        plt_local_path: "priv/plts",
        plt_core_path: "priv/plts",
        ignore_warnings: ".dialyzer_ignore.exs"
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {CcxtOcx.Application, []}
    ]
  end

  def cli do
    [preferred_envs: ["test.json": :test, "dialyzer.json": :dev]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Volt — JS on the BEAM (CCXT is a JS library)
      {:oxc, "~> 0.12.1"},
      {:quickbeam, "~> 0.10.12"},
      {:npm, "~> 0.7.1"},

      # Pooling — long-lived CCXT runtimes (Task 3)
      {:nimble_pool, "~> 1.1"},

      # JSON
      {:jason, "~> 1.4.5"},

      # Dev/test tooling
      {:ex_unit_json, "~> 0.4.3", only: [:dev, :test], runtime: false},
      {:dialyzer_json, "~> 0.2.0", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.11.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7.18", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.2", only: :dev, runtime: false},
      {:doctor, "~> 0.23.0", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.14.1", only: [:dev, :test], runtime: false},

      # Code analysis
      {:ex_dna, "~> 1.5.1", only: [:dev, :test], runtime: false},
      {:ex_ast, "~> 0.12.0", only: [:dev, :test], runtime: false},
      {:reach, "~> 2.3.4", only: [:dev, :test], runtime: false},

      # Tidewave (non-Phoenix)
      {:tidewave, "~> 0.5.6", only: :dev},
      {:bandit, "~> 1.11.1", only: :dev}
    ]
  end

  defp aliases do
    [
      tidewave: [
        "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4014) end)'"
      ]
    ]
  end
end
