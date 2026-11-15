defmodule Consumer.MixProject do
  use Mix.Project

  def project do
    [
      app: :consumer,
      version: "0.1.0",
      elixir: "~> 1.18",
      compilers: [:boundary] ++ Mix.compilers(),
      deps: deps()
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps do
    [
      {:boundary, "~> 0.10", runtime: false},
      chris_checks()
    ]
  end

  defp chris_checks do
    opts = [only: [:dev, :test], runtime: false]

    case System.get_env("CHRIS_CHECKS_GIT_REF") do
      nil -> {:chris_checks, [path: System.get_env("CHRIS_CHECKS_PATH", "../../..")] ++ opts}
      ref -> {:chris_checks, [git: System.fetch_env!("CHRIS_CHECKS_GIT_URL"), ref: ref] ++ opts}
    end
  end
end
