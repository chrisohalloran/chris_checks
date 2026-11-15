defmodule ChrisChecks.ScriptHardeningTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  @templates Path.expand("../../priv/templates/scripts", __DIR__)

  setup %{tmp_dir: tmp} do
    repo = Path.join(tmp, "repo")
    File.mkdir_p!(Path.join(repo, "scripts"))
    File.mkdir_p!(Path.join(repo, "lib"))

    for name <- ~w(format-edited.sh verify.sh) do
      body =
        @templates
        |> Path.join(name)
        |> File.read!()
        |> String.replace("__APP_DIR__", ".")
        |> String.replace("__BASE_BRANCH__", "main")

      dest = Path.join(repo, "scripts/#{name}")
      File.write!(dest, body)
      File.chmod!(dest, 0o755)
    end

    File.write!(Path.join(repo, "mix.exs"), """
    defmodule Example.MixProject do
      use Mix.Project
      def project, do: [app: :example, version: "0.1.0"]
    end
    """)

    outside = Path.join(tmp, "outside.ex")
    File.write!(outside, "defmodule Outside do\ndef one,do: 1\nend\n")
    %{repo: repo, outside: outside}
  end

  defp sh(repo, command, stdin \\ "") do
    File.write!(Path.join(repo, ".stdin"), stdin)

    {out, status} =
      System.cmd(
        System.find_executable("bash"),
        ["-c", "#{command} <#{repo}/.stdin 2>#{repo}/.stderr"],
        cd: repo,
        env: [{"PATH", System.get_env("PATH")}, {"GIT_DIR", nil}]
      )

    {status, out, File.read!(Path.join(repo, ".stderr"))}
  end

  defp path_without_realpath(repo) do
    bin = Path.join(repo, "no-realpath")
    File.rm_rf!(bin)
    File.mkdir_p!(bin)

    for name <- ~w(dirname basename readlink cat) do
      File.ln_s!(System.find_executable(name), Path.join(bin, name))
    end

    beam =
      System.get_env("PATH")
      |> String.split(":")
      |> Enum.filter(&String.contains?(&1, ".beam"))

    Enum.join([bin | beam], ":")
  end

  test "format-edited rejects a path that escapes the app with ..", %{
    repo: repo,
    outside: outside
  } do
    original = File.read!(outside)
    attack = repo <> "/./../outside.ex"
    assert String.starts_with?(attack, repo <> "/.")

    {status, _out, _err} = sh(repo, "bash scripts/format-edited.sh #{attack}")
    assert status == 0
    assert File.read!(outside) == original

    inside = Path.join(repo, "lib/inside.ex")
    File.write!(inside, "defmodule Inside do\ndef one,do: 1\nend\n")
    {status, _, err} = sh(repo, "bash scripts/format-edited.sh #{inside}")
    assert status == 0, err
    assert File.read!(inside) == "defmodule Inside do\n  def one, do: 1\nend\n"
  end

  test "format-edited rejects the escape without realpath on PATH", %{
    repo: repo,
    outside: outside
  } do
    original = File.read!(outside)
    attack = repo <> "/./../outside.ex"
    path = path_without_realpath(repo)
    refute path |> String.split(":") |> Enum.any?(&File.exists?(Path.join(&1, "realpath")))

    bash = System.find_executable("bash")

    {status, _, err} =
      sh(repo, "PATH=#{path} #{bash} scripts/format-edited.sh #{attack}")

    assert err == ""

    assert status == 0
    assert File.read!(outside) == original
  end

  test "verify.sh --hook blocks on malformed JSON", %{repo: repo} do
    {status, out, err} = sh(repo, "bash scripts/verify.sh --fast --hook", "{not json")
    assert status == 2
    assert out == ""
    assert err =~ "could not parse the hook payload, so it is blocking"
  end

  test "verify.sh --hook blocks when Elixir has no JSON module", %{repo: repo} do
    bin = Path.join(repo, "bin")
    File.mkdir_p!(bin)

    File.write!(Path.join(bin, "elixir"), """
    #!/bin/sh
    echo "elixir: undefined function JSON.decode/1" >&2
    exit 1
    """)

    File.chmod!(Path.join(bin, "elixir"), 0o755)
    marker = Path.join(repo, "mix-ran")

    File.write!(Path.join(bin, "mix"), """
    #!/bin/sh
    echo ran > "#{marker}"
    exit 0
    """)

    File.chmod!(Path.join(bin, "mix"), 0o755)

    payload = ~s({"hook_event_name":"Stop","session_id":"t","stop_hook_active":false})

    {status, out, err} =
      sh(repo, "PATH=#{bin}:$PATH bash scripts/verify.sh --fast --hook", payload)

    assert status == 2
    assert out == ""
    assert err =~ "could not parse the hook payload"
    assert err =~ "JSON module"
    refute File.exists?(marker)
  end

  test "verify.sh --hook still honours a parsed stop_hook_active payload", %{repo: repo} do
    payload = ~s({"hook_event_name":"Stop","session_id":"t","stop_hook_active":true})
    assert {0, "", ""} = sh(repo, "bash scripts/verify.sh --fast --hook", payload)
  end
end
