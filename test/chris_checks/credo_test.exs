defmodule ChrisChecks.CredoTest do
  use ExUnit.Case, async: true

  alias ChrisChecks.Check.NoMacros

  defp default(opts \\ []) do
    %{configs: [config]} = ChrisChecks.Credo.config(opts)
    config
  end

  defp params(config, check) do
    {^check, params} = List.keyfind(config.checks.extra, check, 0)
    params
  end

  test "the default is strict with the shared checks and AliasUsage disabled" do
    config = default()

    assert config.name == "default"
    assert config.strict
    assert config.requires == []
    assert config.checks.extra == ChrisChecks.Credo.checks()
    assert config.checks.disabled == [{Credo.Check.Design.AliasUsage, []}]
    assert "lib/" in config.files.included
  end

  test "every shared check module exists" do
    for {check, _params} <- ChrisChecks.Credo.checks() do
      assert Code.ensure_loaded?(check), "#{inspect(check)} is not available"
    end
  end

  test "params for a shared check merge into its defaults, in place" do
    config = default(checks: [{NoMacros, allowed: [MyAppWeb]}])

    assert params(config, NoMacros) == [files: %{included: ["lib/"]}, allowed: [MyAppWeb]]
    assert length(config.checks.extra) == length(ChrisChecks.Credo.checks())
  end

  test "{check, false} disables a shared check" do
    config = default(checks: [{NoMacros, false}])

    refute List.keymember?(config.checks.extra, NoMacros, 0)
    assert {NoMacros, []} in config.checks.disabled
  end

  test "an unknown check is appended and :disabled removes shared ones" do
    config =
      default(
        checks: [{Credo.Check.Readability.Specs, []}],
        disabled: [ChrisChecks.Check.WithElseClauses]
      )

    assert List.last(config.checks.extra) == {Credo.Check.Readability.Specs, []}
    refute List.keymember?(config.checks.extra, ChrisChecks.Check.WithElseClauses, 0)
    assert {ChrisChecks.Check.WithElseClauses, []} in config.checks.disabled
  end

  test "files, requires and name are replaced" do
    files = %{included: ["lib/", "credo/"], excluded: []}
    config = default(files: files, requires: ["credo/checks/*.ex"], name: "ci")

    assert config.files == files
    assert config.requires == ["credo/checks/*.ex"]
    assert config.name == "ci"
  end
end
