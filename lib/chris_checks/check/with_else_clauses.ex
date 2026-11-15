defmodule ChrisChecks.Check.WithElseClauses do
  @moduledoc false

  use Credo.Check,
    base_priority: :normal,
    category: :refactor,
    param_defaults: [max_clauses: 3],
    explanations: [
      check: """
      Elixir's "Complex else clauses in with" anti-pattern: one `else` sorting
      out the errors of every step hides which step failed and couples the
      steps together. Let the steps return tagged errors that pass through
      unchanged (no `else`), normalise each step's error in the step, or, where
      each error becomes a response, map them in one named multi-clause
      function (Phoenix's action_fallback idiom):

          else
            error -> render_error(conn, error)
      """,
      params: [max_clauses: "The most clauses a `with`'s `else` may have."]
    ]

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    max = Params.get(params, :max_clauses, __MODULE__)

    {_ast, issues} =
      source_file
      |> SourceFile.ast()
      |> Macro.prewalk([], fn
        {:with, meta, args} = node, issues when is_list(args) ->
          count = else_clauses(List.last(args))

          if count > max,
            do: {node, [issue(issue_meta, count, max, meta[:line]) | issues]},
            else: {node, issues}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  defp else_clauses(opts) when is_list(opts) do
    case Keyword.get(opts, :else) do
      clauses when is_list(clauses) -> Enum.count(clauses, &match?({:->, _, _}, &1))
      _ -> 0
    end
  end

  defp else_clauses(_), do: 0

  defp issue(issue_meta, count, max, line_no) do
    format_issue(issue_meta,
      message:
        "`with` has #{count} `else` clauses (at most #{max}): let the steps' tagged errors " <>
          "pass through, or map them in one named multi-clause function " <>
          "(`else error -> render_error(conn, error)`, like Phoenix's action_fallback).",
      trigger: "with",
      line_no: line_no
    )
  end
end
