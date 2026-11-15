defmodule Mix.Tasks.ChrisChecks.InstallTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.ChrisChecks.Install

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    {_, 0} = System.cmd("git", ["init", "-q", tmp_dir], env: [{"GIT_DIR", nil}])
    :ok
  end

  defp install(dir, args) do
    File.mkdir_p!(dir)
    File.cd!(dir, fn -> Install.run(args) end)
    messages()
  end

  defp messages(acc \\ []) do
    receive do
      {:mix_shell, _, [line]} -> messages([line | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  test "installs into a plain root app with base branch main", %{tmp_dir: root} do
    output = install(root, [])

    assert Enum.count(output, &String.starts_with?(&1, "created")) == 8
    verify = File.read!(Path.join(root, "scripts/verify.sh"))
    assert verify =~ ~s(APP_DIR="${CHRIS_CHECKS_APP_DIR:-.}")
    assert verify =~ ~s(BASE_BRANCH="${CHRIS_CHECKS_BASE_BRANCH:-main}")
    refute verify =~ "__APP_DIR__"
    assert File.stat!(Path.join(root, "scripts/verify.sh")).mode |> Bitwise.band(0o111) != 0

    assert File.stat!(Path.join(root, "scripts/format-edited.sh")).mode |> Bitwise.band(0o111) !=
             0

    for path <-
          ~w(.claude/settings.json .cursor/hooks.json CLAUDE.md AGENTS.md .credo.exs .sobelow-conf) do
      assert File.exists?(Path.join(root, path)), path
    end

    assert root |> Path.join(".claude/settings.json") |> File.read!() |> JSON.decode!()
    assert root |> Path.join(".cursor/hooks.json") |> File.read!() |> JSON.decode!()
  end

  test "installs for an app in a subdirectory with base branch staging", %{tmp_dir: root} do
    app = Path.join(root, "apps/my_app")
    install(app, ["--base-branch", "staging"])

    verify = File.read!(Path.join(root, "scripts/verify.sh"))
    assert verify =~ ~s(APP_DIR="${CHRIS_CHECKS_APP_DIR:-apps/my_app}")
    assert verify =~ ~s(BASE_BRANCH="${CHRIS_CHECKS_BASE_BRANCH:-staging}")
    assert File.read!(Path.join(root, "scripts/format-edited.sh")) =~ "apps/my_app"
    assert File.exists?(Path.join(app, ".credo.exs"))
    assert File.exists?(Path.join(app, ".sobelow-conf"))
    refute File.exists?(Path.join(root, ".credo.exs"))
    refute File.exists?(Path.join(app, "scripts/verify.sh"))
  end

  test "is idempotent and never clobbers without --force", %{tmp_dir: root} do
    install(root, [])
    assert Enum.all?(install(root, []), &String.starts_with?(&1, "unchanged"))

    verify = Path.join(root, "scripts/verify.sh")
    credo = Path.join(root, ".credo.exs")
    File.write!(verify, "local edit\n")
    File.write!(credo, "local config\n")

    output = install(root, [])
    assert Enum.count(output, &String.starts_with?(&1, "skipped")) == 2
    assert File.read!(verify) == "local edit\n"
    assert File.read!(credo) == "local config\n"

    output = install(root, ["--force"])
    assert Enum.count(output, &String.starts_with?(&1, "overwritten")) == 2
    assert File.read!(verify) =~ "scripts/verify.sh --fast"
  end

  test "a re-run keeps the installed app dir and base branch", %{tmp_dir: root} do
    install(Path.join(root, "apps/my_app"), ["--base-branch", "staging"])
    verify = Path.join(root, "scripts/verify.sh")
    File.write!(verify, File.read!(verify) <> "# local edit\n")

    install(root, ["--force"])
    assert File.read!(verify) =~ ~s(BASE_BRANCH="${CHRIS_CHECKS_BASE_BRANCH:-staging}")
    assert File.read!(verify) =~ ~s(APP_DIR="${CHRIS_CHECKS_APP_DIR:-apps/my_app}")
    refute File.read!(verify) =~ "# local edit"
    assert install(root, ["--check"]) == ["chris_checks templates are current"]
  end

  test "--check fails only when a managed file drifts", %{tmp_dir: root} do
    install(root, ["--app-dir", "."])
    assert install(root, ["--check"]) == ["chris_checks templates are current"]

    File.write!(Path.join(root, ".credo.exs"), "ChrisChecks.Credo.config()\n")
    assert install(root, ["--check"]) == ["chris_checks templates are current"]

    File.write!(Path.join(root, ".cursor/hooks.json"), "{}\n")

    assert_raise Mix.Error, ~r/mix chris_checks.install --force/, fn ->
      install(root, ["--check"])
    end

    assert File.read!(Path.join(root, ".cursor/hooks.json")) == "{}\n"
  end
end
