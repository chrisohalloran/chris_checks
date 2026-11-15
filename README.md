# chris_checks

A deterministic check stack for Elixir/Phoenix repositories, shared as one git
dependency: a strict Credo config (Credo, [ex_slop], [jump_credo_checks] and
three custom checks), Sobelow and mix_audit, a `scripts/verify.sh` that agents,
hooks, CI and humans all run, and the Claude Code and Cursor hook configs that
call it.

Every correction an agent needs more than once becomes a check in code, not a
line of prose. The same script runs under Claude Code, Cursor, cloud agents, CI
or a terminal, so the result never depends on the harness.

## Install

In the Mix project's `mix.exs` (for an umbrella-style repo, the app's):

```elixir
{:chris_checks,
 git: "https://github.com/chrisohalloran/chris_checks.git",
 tag: "v0.1.0",
 only: [:dev, :test],
 runtime: false}
```

That brings `credo`, `ex_slop`, `jump_credo_checks`, `sobelow` and `mix_audit`
with it. Then, from the Mix project directory:

```sh
mix deps.get
mix chris_checks.install                         # base branch main
mix chris_checks.install --base-branch staging   # or staging
```

The task finds the repository root (git top level) and the app dir (where you
ran it, e.g. `.` or `apps/my_app`) and writes:

| File | Where | Kind |
| --- | --- | --- |
| `scripts/verify.sh`, `scripts/format-edited.sh` | repo root | managed |
| `.claude/settings.json`, `.cursor/hooks.json`, `CLAUDE.md` | repo root | managed |
| `AGENTS.md` | repo root | seeded |
| `.credo.exs`, `.sobelow-conf` | app dir | seeded |

An existing file that differs is never overwritten without `--force`. Managed
files track the package: after bumping the tag, run
`mix chris_checks.install --force`; `mix chris_checks.install --check` fails
when a managed file has drifted. Seeded files are written once and then owned
by the repository. Re-runs keep the app dir and base branch already in
`scripts/verify.sh`.

## Credo config

`.credo.exs` is a call into the dependency, so the check list has one source:

```elixir
ChrisChecks.Credo.config(
  checks: [
    {ChrisChecks.Check.NoMacros, allowed: [MyAppWeb]},
    {Jump.CredoChecks.ForbiddenFunction,
     functions:
       ChrisChecks.Credo.forbidden_functions() ++
         [{Ecto.Adapters.SQL, :query!, "Use a query in the context module."}]}
  ],
  files: %{
    included: ["lib/", "test/", "config/", "priv/repo/", "credo/"],
    excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
  },
  requires: ["credo/checks/*.ex"]
)
```

- `checks:` params for a shared check merge into its defaults, `{check, false}`
  disables it, and any other check is added.
- `disabled:`, `files:`, `requires:` and `name:` are also accepted.
- `ChrisChecks.Credo.checks/0` is the full list, with the reasons for what is
  left off in the module docs.

`mix credo` evaluates `.credo.exs` as Elixir after loading dependency paths, so
the call works. `test/fixtures/consumer` proves it, both as a path and as a git
dependency, in this repository's CI.

### Custom checks

| Check | Flags |
| --- | --- |
| `ChrisChecks.Check.NoMacros` | `defmacro`/`defmacrop` outside modules listed in `allowed` |
| `ChrisChecks.Check.LiveViewTimerRequiresConnected` | `Process.send_after` and `:timer.*` in `mount/3` not guarded by `connected?(socket)` |
| `ChrisChecks.Check.WithElseClauses` | a `with` whose `else` has more than `max_clauses` (3) clauses |

## verify.sh

```sh
scripts/verify.sh --fast          # format, compile --warnings-as-errors, credo --strict, tests for changed files
scripts/verify.sh --full          # + deps.unlock --check-unused, sobelow, deps.audit, hex.audit, full mix test
scripts/verify.sh --fast --hook   # stop hook: reads the hook JSON on stdin
scripts/verify.sh --tests-for lib/my_app/foo.ex
scripts/verify.sh --doctor
```

`--fast` runs the tests for files changed since the base branch (committed,
staged, unstaged, untracked): a changed test runs itself; a lib file runs its
mirror test and every test naming one of its modules; a change to `mix.exs`,
`mix.lock`, `config/`, `priv/`, `test/support/` or the tool configs runs the
whole suite, as does a lib file no test reaches. A repository with a
`scripts/tests_for.exs` uses that for selection instead.

With `--hook`, a failure goes back to the agent: Claude Code gets exit 2 with
the log on stderr, Cursor gets `{"followup_message": ...}` on stdout. A Claude
payload with `stop_hook_active: true` and a Cursor payload with status
`aborted` or `error` exit 0 without running.

Configuration is the top of the script, each overridable by environment:

| Variable | Env | Default |
| --- | --- | --- |
| `APP_DIR` | `CHRIS_CHECKS_APP_DIR` | set by install |
| `BASE_BRANCH` | `CHRIS_CHECKS_BASE_BRANCH` | set by install |
| `BROAD_PATHS` | `CHRIS_CHECKS_BROAD_PATHS` | none (extra globs that run the whole suite) |
| `FALLBACK_TESTS` | `CHRIS_CHECKS_FALLBACK_TESTS` | none (whole suite) |

Repository-specific steps go in an optional `scripts/verify.local.sh`, which
may set those variables and define `extra_fast` and `extra_full` functions; the
script itself is never forked. The scripts need Elixir 1.18+ (they parse hook
JSON with Elixir's `JSON` module) and nothing else.

## CI: the reusable workflow

`.github/workflows/verify.yml` checks out the caller, sets up Elixir/OTP,
restores the `deps`/`_build` cache, runs `mix deps.get`, and then
`scripts/verify.sh --full`, so CI runs the same list as the stop hook:

```yaml
# .github/workflows/ci.yml in a consumer
name: CI
on:
  pull_request:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  verify:
    uses: chrisohalloran/chris_checks/.github/workflows/verify.yml@v0.1.0
    with:
      elixir-version: "1.20.4"
      otp-version: "27.3.4.18"
      postgres: true
      setup: mix ecto.create
```

| Input | Default | |
| --- | --- | --- |
| `elixir-version`, `otp-version` | empty | both empty: read `version-file` |
| `version-file` | `.tool-versions` | |
| `working-directory` | `.` | the Mix project, e.g. `apps/my_app` |
| `verify-script` | `scripts/verify.sh` | relative to the repository root |
| `postgres` | `false` | starts `postgres-image` (`postgres:17`) and exports `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `DATABASE_URL` (user and password `postgres`, Phoenix's test defaults) |
| `env` | empty | extra `KEY=VALUE` lines (not for secrets) |
| `setup` | empty | shell run in `working-directory` after `deps.get` |
| `runs-on` | `ubuntu-24.04` | |

`MIX_ENV` is `test` throughout. This repository's own CI calls the workflow
against `test/fixtures/consumer` with both version styles and with postgres.

## Boundary

[Boundary] is a compiler, so it must be a direct dependency of the consumer,
not something this package can bring:

```elixir
# mix.exs
compilers: [:boundary] ++ Mix.compilers(),   # Phoenix: [:boundary, :phoenix_live_view] ++ Mix.compilers()
{:boundary, "~> 0.10", runtime: false},
```

```elixir
defmodule MyApp do
  use Boundary, deps: [], exports: [Accounts]
end

defmodule MyAppWeb do
  use Boundary, deps: [MyApp], exports: [Endpoint]
end
```

Boundary violations are compiler warnings, so `mix compile --warnings-as-errors`
in both tiers fails on them.

## Development

```sh
mix test                     # unit tests
mix test --include consumer  # plus the fixture consumer end to end
```

## License

MIT. See [LICENSE](LICENSE).

[ex_slop]: https://hex.pm/packages/ex_slop
[jump_credo_checks]: https://hex.pm/packages/jump_credo_checks
[Boundary]: https://hex.pm/packages/boundary
