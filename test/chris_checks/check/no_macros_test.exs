defmodule ChrisChecks.Check.NoMacrosTest do
  use Credo.Test.Case, async: true

  alias ChrisChecks.Check.NoMacros

  test "flags defmacro and defmacrop" do
    """
    defmodule MyApp.Helpers do
      defmacro trace(expr), do: expr
      defmacrop hidden(expr) when is_atom(expr), do: expr
    end
    """
    |> to_source_file()
    |> run_check(NoMacros)
    |> assert_issues(fn [first, second] ->
      assert first.line_no == 2
      assert first.trigger == "defmacro"

      assert first.message ==
               "`defmacro trace`: use a function (or `import`) instead of a macro, " <>
                 "or add this module to NoMacros' `allowed` list with a reason."

      assert second.line_no == 3
      assert second.trigger == "defmacrop"
      assert second.message =~ "`defmacrop hidden`"
    end)
  end

  test "allows a listed module" do
    """
    defmodule MyAppWeb do
      defmacro __using__(which), do: apply(__MODULE__, which, [])
    end
    """
    |> to_source_file()
    |> run_check(NoMacros, allowed: [MyAppWeb])
    |> refute_issues()
  end

  test "a module nested in an allowed module is not allowed itself" do
    """
    defmodule MyAppWeb do
      defmodule Inner do
        defmacro inner, do: :ok
      end

      defmacro __using__(_), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(NoMacros, allowed: [MyAppWeb])
    |> assert_issue(fn issue -> assert issue.line_no == 3 end)
  end

  test "resolves nested and __MODULE__ names against the enclosing module" do
    """
    defmodule MyApp do
      defmodule Web do
        defmacro a, do: :ok
      end

      defmodule __MODULE__.Router do
        defmacro b, do: :ok
      end
    end
    """
    |> to_source_file()
    |> run_check(NoMacros, allowed: [MyApp.Web, MyApp.Router])
    |> refute_issues()
  end

  test "a module named at run time is never allowed" do
    """
    defmodule unquote(name) do
      defmacro a, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(NoMacros, allowed: [MyApp])
    |> assert_issue()
  end

  test "plain functions pass" do
    """
    defmodule MyApp.Helpers do
      def trace(expr), do: expr
    end
    """
    |> to_source_file()
    |> run_check(NoMacros)
    |> refute_issues()
  end
end
