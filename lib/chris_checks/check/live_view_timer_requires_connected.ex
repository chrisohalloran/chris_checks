defmodule ChrisChecks.Check.LiveViewTimerRequiresConnected do
  @moduledoc false

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      LiveView `mount/3` runs twice: for the static render, then again when the
      WebSocket connects. A timer started in the static mount fires into a
      process that has already gone. Start timers only when connected, with
      `connected?(socket)` written in the condition itself:

          if connected?(socket), do: Process.send_after(self(), :tick, 1_000)

      Understood guards: `if`/`unless` (including `not`/`!` and `and`/`&&`) and
      `cond` clauses. Not followed: helper functions called from `mount/3`, and
      `connected?` stored in a variable first.
      (jump_credo_checks' LiveViewPubSubRequiresConnected covers subscriptions.)
      """
    ]

  @timers [
    {"Process", :send_after},
    {":timer", :send_after},
    {":timer", :send_interval},
    {":timer", :apply_after},
    {":timer", :apply_interval}
  ]

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    ast = SourceFile.ast(source_file)
    aliases = aliases(ast)

    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {kind, _, [head, body]} = node, issues when kind in [:def, :defp] ->
          if mount?(head) do
            found = walk(Keyword.get(List.wrap(body), :do), false, aliases, issue_meta)
            {node, found ++ issues}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.sort_by(issues, & &1.line_no)
  end

  defp mount?({:when, _, [head | _]}), do: mount?(head)
  defp mount?({:mount, _, [_, _, _]}), do: true
  defp mount?(_), do: false

  # `connected` is true inside a branch that runs only when the socket is
  # connected. Conditions are always walked unguarded.
  defp walk({:if, _, [condition, blocks]}, connected, aliases, meta) when is_list(blocks) do
    walk(condition, connected, aliases, meta) ++
      walk(blocks[:do], connected or connected?(condition), aliases, meta) ++
      walk(blocks[:else], connected or disconnected?(condition), aliases, meta)
  end

  defp walk({:unless, _, [condition, blocks]}, connected, aliases, meta) when is_list(blocks) do
    walk(condition, connected, aliases, meta) ++
      walk(blocks[:do], connected or disconnected?(condition), aliases, meta) ++
      walk(blocks[:else], connected or connected?(condition), aliases, meta)
  end

  defp walk({:cond, _, [[do: clauses]]}, connected, aliases, meta) when is_list(clauses) do
    Enum.flat_map(clauses, fn
      {:->, _, [[condition], body]} ->
        walk(condition, connected, aliases, meta) ++
          walk(body, connected or connected?(condition), aliases, meta)

      other ->
        walk(other, connected, aliases, meta)
    end)
  end

  defp walk({{:., call_meta, [module, fun]}, _, args} = node, connected, aliases, meta) do
    own =
      if not connected and timer?(module, fun, aliases),
        do: [issue(meta, node, call_meta[:line])],
        else: []

    own ++ walk(args, connected, aliases, meta)
  end

  defp walk({form, _, args}, connected, aliases, meta) when is_list(args),
    do: walk(form, connected, aliases, meta) ++ walk(args, connected, aliases, meta)

  defp walk({left, right}, connected, aliases, meta),
    do: walk(left, connected, aliases, meta) ++ walk(right, connected, aliases, meta)

  defp walk(list, connected, aliases, meta) when is_list(list),
    do: Enum.flat_map(list, &walk(&1, connected, aliases, meta))

  defp walk(_leaf, _connected, _aliases, _meta), do: []

  defp connected?({:connected?, _, [_]}), do: true
  defp connected?({{:., _, [_, :connected?]}, _, [_]}), do: true

  defp connected?({op, _, [left, right]}) when op in [:and, :&&],
    do: connected?(left) or connected?(right)

  defp connected?(_), do: false

  defp disconnected?({op, _, [inner]}) when op in [:not, :!], do: connected?(inner)
  defp disconnected?(_), do: false

  defp timer?(module, fun, aliases), do: {resolve(module, aliases), fun} in @timers

  defp resolve({:__aliases__, _, parts} = ast, aliases) do
    case aliases do
      %{^parts => target} -> target
      _ -> if Enum.all?(parts, &is_atom/1), do: module_name(parts), else: ast
    end
  end

  defp resolve(module, _aliases) when is_atom(module), do: inspect(module)
  defp resolve(module, _aliases), do: module

  defp aliases(ast) do
    {_ast, aliases} =
      Macro.prewalk(ast, %{}, fn
        {:alias, _, [target, [as: {:__aliases__, _, as}]]} = node, acc ->
          {node, Map.put(acc, as, alias_target(target))}

        node, acc ->
          {node, acc}
      end)

    aliases
  end

  defp alias_target({:__aliases__, _, parts} = ast) do
    if Enum.all?(parts, &is_atom/1), do: module_name(parts), else: ast
  end

  defp alias_target(atom) when is_atom(atom), do: inspect(atom)
  defp alias_target(other), do: other

  defp module_name([:"Elixir" | parts]), do: module_name(parts)
  defp module_name(parts), do: Enum.map_join(parts, ".", &Atom.to_string/1)

  defp issue(issue_meta, {{:., _, [module, fun]}, _, _}, line_no) do
    name = if is_atom(module), do: inspect(module), else: Macro.to_string(module)

    format_issue(issue_meta,
      message: "#{name}.#{fun} in `mount/3`: start timers only `if connected?(socket)`.",
      trigger: "#{name}.#{fun}",
      line_no: line_no
    )
  end
end
