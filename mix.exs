defmodule ChrisChecks.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/chrisohalloran/chris_checks"

  def project do
    [
      app: :chris_checks,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: false,
      deps: deps(),
      elixirc_paths: ["lib"],
      test_load_filters: [&(String.ends_with?(&1, "_test.exs") and not fixture?(&1))],
      test_ignore_filters: [&fixture?/1],
      description:
        "Deterministic check stack for Elixir/Phoenix repos: strict Credo config, " <>
          "custom Credo checks, verify.sh and agent hook templates",
      source_url: @source_url,
      package: [
        licenses: ["MIT"],
        links: %{"GitHub" => @source_url},
        files: ~w(lib priv mix.exs README.md LICENSE)
      ]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp fixture?(path), do: String.starts_with?(path, "test/fixtures/")

  defp deps do
    [
      {:credo, "~> 1.7"},
      {:ex_slop, "~> 0.4"},
      {:jump_credo_checks, "~> 0.5"},
      {:sobelow, "~> 0.14"},
      {:mix_audit, "~> 2.1"}
    ]
  end
end
