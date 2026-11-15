defmodule ChrisChecks.ConsumerTest do
  use ExUnit.Case, async: false

  @moduletag :consumer
  @moduletag :tmp_dir
  @moduletag timeout: 600_000

  @fixture Path.expand("fixtures/consumer", __DIR__)

  @broken """
  defmodule Consumer.Broken do
    @moduledoc "Deliberately broken."

    defmacro trace(expr), do: expr

    def run(step) do
      with {:ok, b} <- step.() do
        b
      else
        {:error, :x} -> :x
        {:error, :y} -> :y
        :error -> :other
      end
    end
  end
  """

  @claude ~s({"hook_event_name":"Stop","session_id":"t","stop_hook_active":false})

  setup_all do
    shared =
      Path.join(System.tmp_dir!(), "chris_checks_consumer_#{System.unique_integer([:positive])}")

    File.mkdir_p!(shared)
    on_exit(fn -> File.rm_rf!(shared) end)

    env =
      [
        {"MIX_ENV", "test"},
        {"MIX_DEPS_PATH", Path.join(shared, "deps")},
        {"MIX_BUILD_ROOT", Path.join(shared, "_build")},
        {"CHRIS_CHECKS_PATH", File.cwd!()}
      ] ++
        for var <- ["CHRIS_CHECKS_GIT_REF", "CHRIS_CHECKS_GIT_URL"],
            value = System.get_env(var),
            do: {var, value}

    %{env: env}
  end

  defp sh(env, dir, command, stdin \\ "") do
    input = Path.join(dir, ".stdin")
    err = Path.join(dir, ".stderr")
    File.write!(input, stdin)
    {out, status} = System.cmd("bash", ["-c", "#{command} <#{input} 2>#{err}"], cd: dir, env: env)
    {status, out, File.read!(err)}
  end

  defp ok!(env, dir, command) do
    {status, out, err} = sh(env, dir, command)
    assert status == 0, "#{command} exited #{status}\n#{out}\n#{err}"
    out
  end

  defp repo!(env, root, app_dir, branch) do
    app = Path.join(root, app_dir)
    File.mkdir_p!(Path.dirname(app))
    File.cp_r!(@fixture, app)

    for installed <- ~w(scripts .claude .cursor CLAUDE.md AGENTS.md .sobelow-conf),
        do: File.rm_rf!(Path.join(app, installed))

    File.write!(Path.join(root, ".gitignore"), "_build/\ndeps/\nmix.lock\n.stdin\n.stderr\n")
    ok!(env, root, "git init -q -b #{branch} && git add -A && #{commit()} -qm fixture")
    app
  end

  defp commit, do: "git -c user.email=t@example.com -c user.name=t commit"

  test "a root app on main: credo through the dep, verify.sh and the hook contract", %{
    env: env,
    tmp_dir: root
  } do
    app = repo!(env, root, ".", "main")
    ok!(env, app, "mix deps.get")
    install = ok!(env, app, "mix chris_checks.install")
    assert install =~ "created      #{root}/scripts/verify.sh"
    ok!(env, root, "git add -A && #{commit()} -qm install")

    assert ok!(env, app, "mix credo --strict") =~ "found no issues"
    assert ok!(env, root, "bash scripts/verify.sh --fast") =~ "==> credo"

    File.write!(Path.join(app, "lib/consumer/broken.ex"), @broken)

    {status, out, _} = sh(env, root, "bash scripts/verify.sh --fast")
    assert status != 0
    assert out =~ "`defmacro trace`: use a function"
    assert out =~ "`with` has 3 `else` clauses (at most 2)"

    {status, out, err} = sh(env, root, "bash scripts/verify.sh --fast --hook", @claude)
    assert status == 2
    assert out == ""
    assert err =~ "scripts/verify.sh --fast failed"
    assert err =~ "Fix the root cause"
    assert err =~ "`defmacro trace`"

    cursor = ~s({"cursor_version":"1.7","workspace_roots":["#{root}"],"status":"completed"})
    {status, out, _} = sh(env, root, "bash scripts/verify.sh --fast --hook", cursor)
    assert status == 0
    assert %{"followup_message" => message} = JSON.decode!(out)
    assert message =~ "`defmacro trace`"

    active = ~s({"hook_event_name":"Stop","session_id":"t","stop_hook_active":true})
    assert {0, "", ""} = sh(env, root, "bash scripts/verify.sh --fast --hook", active)
    aborted = ~s({"cursor_version":"1.7","status":"aborted"})
    assert {0, "", ""} = sh(env, root, "bash scripts/verify.sh --fast --hook", aborted)

    File.rm!(Path.join(app, "lib/consumer/broken.ex"))
    assert {0, "", ""} = sh(env, root, "bash scripts/verify.sh --fast --hook", @claude)

    ugly = Path.join(app, "lib/consumer/ugly.ex")
    File.write!(ugly, "defmodule Consumer.Ugly do\n@moduledoc false\ndef one,do: 1\nend\n")
    edit = ~s({"hook_event_name":"PostToolUse","tool_input":{"file_path":"#{ugly}"}})
    assert {0, _, _} = sh(env, root, "bash scripts/format-edited.sh", edit)

    assert File.read!(ugly) ==
             "defmodule Consumer.Ugly do\n  @moduledoc false\n  def one, do: 1\nend\n"

    File.rm!(ugly)

    assert ok!(env, root, "bash scripts/verify.sh --full") =~ "==> deps.audit"
  end

  test "an app in apps/my_app on staging: tests for the changed files", %{
    env: env,
    tmp_dir: root
  } do
    app = repo!(env, root, "apps/my_app", "staging")
    ok!(env, app, "mix deps.get")
    ok!(env, app, "mix chris_checks.install --base-branch staging")
    assert File.exists?(Path.join(app, ".sobelow-conf"))
    ok!(env, root, "git add -A && #{commit()} -qm install && git checkout -qb feature")
    assert ok!(env, app, "mix chris_checks.install --check") =~ "current"

    pricing = Path.join(app, "lib/consumer/pricing.ex")

    File.write!(
      pricing,
      String.replace(File.read!(pricing), "\nend\n", "\n\n  def zero, do: 0\nend\n")
    )

    assert ok!(
             env,
             root,
             "bash scripts/verify.sh --tests-for apps/my_app/lib/consumer/pricing.ex"
           ) ==
             "test/consumer/pricing_test.exs\n"

    out = ok!(env, root, "bash scripts/verify.sh --fast")
    assert out =~ "tests: test/consumer/pricing_test.exs"

    File.mkdir_p!(Path.join(app, "config"))
    File.write!(Path.join(app, "config/config.exs"), "import Config\n")
    assert ok!(env, root, "bash scripts/verify.sh --fast") =~ "running the full suite"
  end
end
