defmodule ChrisChecks.Check.WithElseClausesTest do
  use Credo.Test.Case, async: true

  alias ChrisChecks.Check.WithElseClauses

  @four """
  defmodule MyApp.Orders do
    def place(params) do
      with {:ok, a} <- step_a(params),
           {:ok, b} <- step_b(a) do
        {:ok, b}
      else
        {:error, :a} -> :a
        {:error, :b} -> :b
        {:error, :c} -> :c
        :error -> :other
      end
    end
  end
  """

  test "flags a with whose else has more than 3 clauses" do
    @four
    |> to_source_file()
    |> run_check(WithElseClauses)
    |> assert_issue(fn issue ->
      assert issue.line_no == 3
      assert issue.trigger == "with"

      assert issue.message ==
               "`with` has 4 `else` clauses (at most 3): let the steps' tagged errors " <>
                 "pass through, or map them in one named multi-clause function " <>
                 "(`else error -> render_error(conn, error)`, like Phoenix's action_fallback)."
    end)
  end

  test "max_clauses is configurable" do
    @four
    |> to_source_file()
    |> run_check(WithElseClauses, max_clauses: 4)
    |> refute_issues()
  end

  test "allows up to 3 clauses and a with without else" do
    """
    defmodule MyApp.Orders do
      def place(params) do
        with {:ok, a} <- step_a(params) do
          a
        else
          {:error, :a} -> :a
          {:error, :b} -> :b
          error -> render_error(error)
        end
      end

      def pass(params) do
        with {:ok, a} <- step_a(params), do: {:ok, a}
      end
    end
    """
    |> to_source_file()
    |> run_check(WithElseClauses)
    |> refute_issues()
  end
end
