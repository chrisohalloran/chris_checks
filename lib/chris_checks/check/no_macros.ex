defmodule ChrisChecks.Check.NoMacros do
  @moduledoc false

  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [allowed: []],
    explanations: [
      check: """
      A function, not a macro (Elixir's "Unnecessary macros" and "`use` instead
      of `import`" anti-patterns). Macros run at compile time, hide what code
      does, and create compile-time dependencies; a plain function or `import`
      does the same job in almost every case.

      A module that genuinely needs a macro (Phoenix's `use MyAppWeb, :live_view`
      entry point, an Ecto query fragment) is listed in `allowed`, with the
      reason in `.credo.exs`.
      """,
      params: [allowed: "Modules allowed to define macros, e.g. `[MyAppWeb]`."]
    ]

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    allowed = params |> Params.get(:allowed, __MODULE__) |> MapSet.new(&inspect/1)

    {_ast, {issues, _stack}} =
      source_file
      |> SourceFile.ast()
      |> Macro.traverse({[], []}, &enter(&1, &2, allowed, issue_meta), &leave/2)

    Enum.reverse(issues)
  end

  # The stack holds each enclosing module (its alias parts, or :unknown when the
  # name can't be read statically), innermost first.
  defp enter({:defmodule, _, [name | _]} = node, {issues, stack}, _, _) do
    {node, {issues, [module_parts(name, stack) | stack]}}
  end

  defp enter({kind, meta, [head | _]} = node, {issues, stack}, allowed, issue_meta)
       when kind in [:defmacro, :defmacrop] do
    if allowed?(stack, allowed) do
      {node, {issues, stack}}
    else
      {node, {[issue(issue_meta, kind, name(head), meta[:line]) | issues], stack}}
    end
  end

  defp enter(node, acc, _allowed, _issue_meta), do: {node, acc}

  defp leave({:defmodule, _, _} = node, {issues, [_ | stack]}), do: {node, {issues, stack}}
  defp leave(node, acc), do: {node, acc}

  defp module_parts({:__aliases__, _, [{:__MODULE__, _, _} | rest]}, stack),
    do: resolved(outer(stack), rest)

  defp module_parts({:__aliases__, _, parts}, stack), do: resolved(outer(stack), parts)
  defp module_parts(_name, _stack), do: :unknown

  defp resolved(:unknown, _parts), do: :unknown

  defp resolved(outer, parts) do
    if Enum.all?(parts, &is_atom/1), do: outer ++ parts, else: :unknown
  end

  defp outer([]), do: []
  defp outer([parts | _]), do: parts

  defp allowed?([parts | _], allowed) when is_list(parts),
    do: MapSet.member?(allowed, module_name(parts))

  defp allowed?(_stack, _allowed), do: false

  defp module_name([:"Elixir" | parts]), do: module_name(parts)
  defp module_name(parts), do: Enum.map_join(parts, ".", &Atom.to_string/1)

  defp name({:when, _, [head | _]}), do: name(head)
  defp name({name, _, _}) when is_atom(name), do: name
  defp name(_), do: :macro

  defp issue(issue_meta, kind, name, line_no) do
    format_issue(issue_meta,
      message:
        "`#{kind} #{name}`: use a function (or `import`) instead of a macro, " <>
          "or add this module to NoMacros' `allowed` list with a reason.",
      trigger: to_string(kind),
      line_no: line_no
    )
  end
end
