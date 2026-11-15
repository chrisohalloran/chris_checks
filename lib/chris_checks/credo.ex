defmodule ChrisChecks.Credo do
  @moduledoc """
  The shared strict Credo config. A consumer's `.credo.exs` is:

      ChrisChecks.Credo.config(
        checks: [{ChrisChecks.Check.NoMacros, allowed: [MyAppWeb]}]
      )

  Options:

    * `:checks` - `{check, params}` overrides. Params for a check in the
      shared list are merged into its defaults; `{check, false}` disables it;
      any other check is added.
    * `:disabled` - checks to disable, as modules or `{check, params}`.
    * `:files` - replaces the default `files` map.
    * `:requires` - extra check files to compile, e.g. `["credo/checks/*.ex"]`.
    * `:name` - the config name (default `"default"`).

  Off by design (do not add them back in a consumer without a reason in its
  `.credo.exs`): `Design.AliasUsage`, ExSlop `UnaliasedModuleUse`,
  `DocFalseOnPublicFunction`, `PathExpandPriv`, `ListLast`, Refactor
  `CondInsteadOfIfElse`, `ABCSize`, `PerceivedComplexity`, `AppendSingleItem`,
  Readability `Specs`, `StrictModuleLayout`, `ImplTrue`, Jump
  `TooManyAssertions`, `TopLevelAliasImportRequire`, `DoctestIExExamples`,
  `PreferTextColumns`, `UseObanProWorker`.
  """

  @files %{
    included: ["lib/", "test/", "config/", "priv/repo/"],
    excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
  }

  @supervise "Start processes under a supervisor (Task.Supervisor)."
  @debug "Debug output left in; use Logger if it should stay."

  @doc "The `ForbiddenFunction` list, for consumers that extend it."
  def forbidden_functions do
    [
      {Kernel, :spawn, @supervise},
      {Kernel, :spawn_link, @supervise},
      {:spawn, 1, @supervise},
      {:spawn, 3, @supervise},
      {:spawn_link, 1, @supervise},
      {:spawn_link, 3, @supervise},
      {:dbg, 0, @debug},
      {:dbg, 1, @debug},
      {:dbg, 2, @debug},
      {Task, :start, "Use Task.Supervisor.start_child/2 under the app's Task.Supervisor."},
      {GenServer, :start, "Start GenServers under a supervisor (start_link in a child spec)."},
      {Agent, :start, "Start Agents under a supervisor (start_link in a child spec)."},
      {IO, :inspect, @debug},
      {Code, :eval_string, "Never evaluate strings."},
      {:erlang, :binary_to_term, "Use Plug.Crypto.non_executable_binary_to_term/2."}
    ]
  end

  @doc "The shared enabled checks, in order."
  def checks do
    [
      {Credo.Check.Refactor.CyclomaticComplexity, [max_complexity: 15]},
      {Credo.Check.Refactor.Nesting, [max_nesting: 4]},
      {Credo.Check.Refactor.FunctionArity, [max_arity: 8]},
      {Credo.Check.Warning.UnsafeToAtom, [files: %{included: ["lib/"]}]},
      {Credo.Check.Warning.MixEnv, [files: %{excluded: ["lib/mix/"]}]},
      {Credo.Check.Warning.LeakyEnvironment, []},
      {Credo.Check.Warning.MapGetUnsafePass, []},
      {Credo.Check.Design.SkipTestWithoutComment, []},
      {Credo.Check.Refactor.PassAsyncInTestCases, []},
      {Credo.Check.Readability.WithCustomTaggedTuple, []},
      {Credo.Check.Refactor.FilterReject, []},
      {Credo.Check.Refactor.RejectFilter, []},
      {Credo.Check.Refactor.MapMap, []},
      {Credo.Check.Refactor.NegatedIsNil, []},
      {Credo.Check.Refactor.DoubleBooleanNegation, []},
      {Credo.Check.Refactor.UtcNowTruncate, []},
      {ExSlop.Check.Warning.BlanketRescue, []},
      {ExSlop.Check.Warning.RescueWithoutReraise, []},
      {ExSlop.Check.Warning.DualKeyAccess, []},
      {ExSlop.Check.Warning.GenserverAsKvStore, []},
      {ExSlop.Check.Warning.QueryInEnumMap, []},
      {ExSlop.Check.Warning.RepoAllThenFilter, []},
      {ExSlop.Check.Readability.NarratorComment, []},
      {ExSlop.Check.Readability.NarratorDoc, []},
      {ExSlop.Check.Readability.ObviousComment, []},
      {ExSlop.Check.Readability.StepComment, []},
      {ExSlop.Check.Readability.BoilerplateDocParams, []},
      {ExSlop.Check.Refactor.CaseTrueFalse, []},
      {ExSlop.Check.Refactor.ExplicitSumReduce, []},
      {ExSlop.Check.Refactor.FilterNil, []},
      {ExSlop.Check.Refactor.FlatMapFilter, []},
      {ExSlop.Check.Refactor.GraphemesLength, []},
      {ExSlop.Check.Refactor.IdentityMap, []},
      {ExSlop.Check.Refactor.IdentityPassthrough, []},
      {ExSlop.Check.Refactor.LengthComparison, [files: %{included: ["lib/"]}]},
      {ExSlop.Check.Refactor.LengthInGuard, []},
      {ExSlop.Check.Refactor.ListFold, []},
      {ExSlop.Check.Refactor.ManualStringReverse, []},
      {ExSlop.Check.Refactor.MapIntoLiteral, []},
      {ExSlop.Check.Refactor.PreferEnumSlice, []},
      {ExSlop.Check.Refactor.ReduceAsMap, []},
      {ExSlop.Check.Refactor.ReduceMapPut, []},
      {ExSlop.Check.Refactor.RedundantBooleanIf, []},
      {ExSlop.Check.Refactor.RedundantEnumJoinSeparator, []},
      {ExSlop.Check.Refactor.RejectNil, []},
      {ExSlop.Check.Refactor.SortForTopK, []},
      {ExSlop.Check.Refactor.SortThenAt, []},
      {ExSlop.Check.Refactor.SortThenReverse, []},
      {ExSlop.Check.Refactor.StringConcatInReduce, []},
      {ExSlop.Check.Refactor.TryRescueWithSafeAlternative, []},
      {ExSlop.Check.Refactor.UseMapJoin, []},
      {ExSlop.Check.Refactor.WithIdentityDo, []},
      {ExSlop.Check.Refactor.WithIdentityElse, []},
      {ChrisChecks.Check.NoMacros, [files: %{included: ["lib/"]}]},
      {ChrisChecks.Check.LiveViewTimerRequiresConnected, []},
      {ChrisChecks.Check.WithElseClauses, [max_clauses: 3]},
      {Jump.CredoChecks.TestHasNoAssertions, []},
      {Jump.CredoChecks.VacuousTest, []},
      {Jump.CredoChecks.WeakAssertion, []},
      {Jump.CredoChecks.ConditionalAssertion, []},
      {Jump.CredoChecks.AssertElementSelectorCanNeverFail, []},
      {Jump.CredoChecks.AssertReceiveTimeout,
       [min_assert_receive_timeout: 1_000, max_refute_receive_timeout: 200]},
      {Jump.CredoChecks.AvoidSocketAssignsInTest, []},
      {Jump.CredoChecks.AvoidLoggerConfigureInTest, []},
      {Jump.CredoChecks.LiveViewPubSubRequiresConnected, []},
      {Jump.CredoChecks.LiveViewFormCanBeRehydrated, []},
      {Jump.CredoChecks.UnusedLiveViewAssign, []},
      {Jump.CredoChecks.AvoidFunctionLevelElse, []},
      {Jump.CredoChecks.PreferChangeOverUpDownMigrations, []},
      {Jump.CredoChecks.SafeBinaryToTerm, []},
      {Jump.CredoChecks.NoManualContentDisposition, []},
      {Jump.CredoChecks.UndeclaredExternalResource, []},
      {Jump.CredoChecks.ForbiddenFunction,
       [files: %{included: ["lib/"]}, functions: forbidden_functions()]}
    ]
  end

  @doc "The shared disabled checks."
  def disabled, do: [{Credo.Check.Design.AliasUsage, []}]

  @doc "A complete `.credo.exs` term: the shared config with `opts` applied."
  def config(opts \\ []) do
    {extra, disabled} = apply_overrides(checks(), Keyword.get(opts, :checks, []))
    extra_disabled = Enum.map(Keyword.get(opts, :disabled, []), &check_tuple/1)

    %{
      configs: [
        %{
          name: Keyword.get(opts, :name, "default"),
          strict: true,
          requires: Keyword.get(opts, :requires, []),
          files: Keyword.get(opts, :files, @files),
          checks: %{
            extra: drop(extra, extra_disabled),
            disabled: disabled() ++ disabled ++ extra_disabled
          }
        }
      ]
    }
  end

  defp apply_overrides(checks, overrides) do
    Enum.reduce(overrides, {checks, []}, fn override, {extra, disabled} ->
      {check, params} = check_tuple(override)

      cond do
        params == false -> {drop(extra, [{check, []}]), disabled ++ [{check, []}]}
        List.keymember?(extra, check, 0) -> {merge(extra, check, params), disabled}
        true -> {extra ++ [{check, params}], disabled}
      end
    end)
  end

  defp merge(checks, check, params) do
    List.keyreplace(checks, check, 0, {check, Keyword.merge(params_of(checks, check), params)})
  end

  defp params_of(checks, check) do
    {^check, params} = List.keyfind(checks, check, 0)
    params
  end

  defp drop(checks, removed) do
    modules = Enum.map(removed, &elem(&1, 0))
    Enum.reject(checks, fn {check, _} -> check in modules end)
  end

  defp check_tuple({check, params}) when is_atom(check), do: {check, params}
  defp check_tuple(check) when is_atom(check), do: {check, []}
end
