defmodule Mix.Tasks.ChrisChecks.Install do
  @shortdoc "Copies the chris_checks templates into this repository"

  @moduledoc """
  Copies verify.sh, format-edited.sh, the Claude Code and Cursor hooks,
  CLAUDE.md, AGENTS.md, `.credo.exs` and `.sobelow-conf` into the repository.

      mix chris_checks.install [--base-branch main] [--app-dir PATH] [--root PATH] [--force]
      mix chris_checks.install --check

  Run it from the Mix project. The repository root is the git top level (or
  `--root`); the app dir is the Mix project relative to it (or `--app-dir`).
  Once installed, the app dir and base branch already in `scripts/verify.sh`
  are kept unless given again, so `--force` upgrades and `--check` need no flags.

  An existing file that differs is left alone unless `--force` is given.
  `--check` writes nothing and exits non-zero when a managed file (the scripts,
  hook configs and CLAUDE.md) is missing or differs from the template, so CI
  can hold every repository to the package's version. `.credo.exs`,
  `.sobelow-conf` and AGENTS.md are seeded once and then owned by the repo.
  """

  use Mix.Task

  @switches [
    base_branch: :string,
    app_dir: :string,
    root: :string,
    force: :boolean,
    check: :boolean
  ]

  @templates [
    {"scripts/verify.sh", :root, :managed},
    {"scripts/format-edited.sh", :root, :managed},
    {".claude/settings.json", :root, :managed},
    {".cursor/hooks.json", :root, :managed},
    {"CLAUDE.md", :root, :managed},
    {"AGENTS.md", :root, :seed},
    {".credo.exs", :app, :seed},
    {".sobelow-conf", :app, :seed}
  ]

  @impl Mix.Task
  def run(argv) do
    {opts, _args} = OptionParser.parse!(argv, strict: @switches)
    cwd = File.cwd!()
    root = Path.expand(opts[:root] || git(cwd, "--show-toplevel") || cwd)
    installed = installed_config(root)
    app_dir = opts[:app_dir] || installed["APP_DIR"] || app_dir(cwd, opts[:root])

    bindings = %{
      "__APP_DIR__" => app_dir,
      "__BASE_BRANCH__" => opts[:base_branch] || installed["BASE_BRANCH"] || "main"
    }

    results =
      for {template, place, kind} <- @templates do
        dest = destination(root, app_dir, place, template)
        contents = render(template, bindings)
        {template, kind, apply_template(dest, contents, kind, opts)}
      end

    if opts[:check] do
      check(results)
    else
      Enum.each(results, fn {template, _kind, result} -> report(template, result) end)
    end
  end

  defp apply_template(dest, contents, kind, opts) do
    current = if File.exists?(dest), do: File.read!(dest)

    cond do
      current == contents -> :unchanged
      opts[:check] -> if kind == :managed, do: {:drift, dest}, else: :unchanged
      is_nil(current) -> write(dest, contents, :created)
      opts[:force] -> write(dest, contents, :overwritten)
      true -> {:skipped, dest}
    end
  end

  defp write(dest, contents, result) do
    File.mkdir_p!(Path.dirname(dest))
    File.write!(dest, contents)
    if String.ends_with?(dest, ".sh"), do: File.chmod!(dest, 0o755)
    {result, dest}
  end

  defp report(template, :unchanged), do: Mix.shell().info("unchanged    #{template}")
  defp report(_template, {:created, dest}), do: Mix.shell().info("created      #{dest}")
  defp report(_template, {:overwritten, dest}), do: Mix.shell().info("overwritten  #{dest}")

  defp report(_template, {:skipped, dest}),
    do: Mix.shell().info("skipped      #{dest} (differs; re-run with --force to replace it)")

  defp check(results) do
    drifted = for {_template, _kind, {:drift, dest}} <- results, do: dest

    if drifted == [] do
      Mix.shell().info("chris_checks templates are current")
    else
      Enum.each(drifted, &Mix.shell().error("out of date: #{&1}"))
      Mix.raise("Run `mix chris_checks.install --force` and commit the result.")
    end
  end

  defp render(template, bindings) do
    :chris_checks
    |> :code.priv_dir()
    |> Path.join("templates/#{template}")
    |> File.read!()
    |> String.replace(Map.keys(bindings), &Map.fetch!(bindings, &1))
  end

  defp destination(root, _app_dir, :root, template), do: Path.join(root, template)

  defp destination(root, app_dir, :app, template),
    do: root |> Path.join(app_dir) |> Path.join(template) |> Path.expand()

  defp installed_config(root) do
    case File.read(Path.join(root, "scripts/verify.sh")) do
      {:ok, script} ->
        for [_, name, value] <-
              Regex.scan(~r/^(APP_DIR|BASE_BRANCH)="\$\{CHRIS_CHECKS_\w+:-([^}]*)\}"$/m, script),
            into: %{},
            do: {name, value}

      {:error, _} ->
        %{}
    end
  end

  defp app_dir(cwd, nil) do
    case git(cwd, "--show-prefix") do
      nil -> "."
      "" -> "."
      prefix -> String.trim_trailing(prefix, "/")
    end
  end

  defp app_dir(cwd, root) do
    case Path.relative_to(cwd, Path.expand(root)) do
      ^cwd -> "."
      rel -> rel
    end
  end

  defp git(cwd, flag) do
    env = [{"GIT_DIR", nil}, {"GIT_WORK_TREE", nil}]

    case System.cmd("git", ["rev-parse", flag], cd: cwd, env: env, stderr_to_stdout: true) do
      {out, 0} -> String.trim(out)
      _ -> nil
    end
  rescue
    ErlangError -> nil
  end
end
