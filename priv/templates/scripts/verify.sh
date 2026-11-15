#!/usr/bin/env bash
# One check list for agents, hooks, CI and humans. Installed by
# `mix chris_checks.install`; update it by re-running that with --force.
#
#   scripts/verify.sh --fast [--hook]
#   scripts/verify.sh --full [--hook]
#   scripts/verify.sh --tests-for <path>...
#   scripts/verify.sh --doctor
#
# --fast: format --check-formatted, compile --warnings-as-errors, credo
# --strict, then the tests that reach files changed since the base branch
# (committed, staged, unstaged and untracked).
# --full: format, compile, credo, sobelow, deps.audit, hex.audit, deps.unlock
# --check-unused, the whole mix test suite.
# --hook: read a stop-hook JSON payload on stdin. On failure Claude Code gets
# exit 2 with the log on stderr; Cursor gets {"followup_message": ...} on stdout.
#
# Optional scripts/verify.local.sh may define extra_fast and extra_full
# (run after each tier) and set any of the variables below.
set -euo pipefail

# Mix project directory, relative to the repository root.
APP_DIR="${CHRIS_CHECKS_APP_DIR:-__APP_DIR__}"
# Branch the --fast diff is taken against (origin/<branch>, else <branch>).
BASE_BRANCH="${CHRIS_CHECKS_BASE_BRANCH:-__BASE_BRANCH__}"
# Extra repository-relative globs whose change runs the whole suite.
BROAD_PATHS="${CHRIS_CHECKS_BROAD_PATHS:-}"
# Tests (relative to APP_DIR) run when a changed lib file maps to no test.
# Empty runs the whole suite, so a gate never passes on zero tests.
FALLBACK_TESTS="${CHRIS_CHECKS_FALLBACK_TESTS:-}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$ROOT/scripts/verify.local.sh" ]; then
  # shellcheck disable=SC1091
  source "$ROOT/scripts/verify.local.sh"
fi
APP="$ROOT/$APP_DIR"
export MIX_ENV=test

usage() {
  echo "usage: scripts/verify.sh --fast|--full [--hook] | --tests-for <path>... | --doctor" >&2
}

in_app() {
  (cd "$APP" && "$@")
}

base_ref() {
  if git -C "$ROOT" rev-parse --verify --quiet "origin/$BASE_BRANCH" >/dev/null; then
    echo "origin/$BASE_BRANCH"
  elif git -C "$ROOT" rev-parse --verify --quiet "$BASE_BRANCH" >/dev/null; then
    echo "$BASE_BRANCH"
  fi
}

changed_paths() {
  local ref base=""
  ref="$(base_ref)"
  if [ -n "$ref" ]; then
    base="$(git -C "$ROOT" merge-base HEAD "$ref" 2>/dev/null || true)"
  fi
  {
    if [ -n "$base" ]; then
      git -C "$ROOT" diff --name-only --diff-filter=ACMRD "$base"
    fi
    git -C "$ROOT" diff --name-only --diff-filter=ACMRD
    git -C "$ROOT" diff --name-only --cached --diff-filter=ACMRD
    git -C "$ROOT" ls-files --others --exclude-standard
  } | awk 'NF' | sort -u
}

app_relative() {
  case "$APP_DIR" in
    . | "") printf '%s\n' "$1" ;;
    *)
      case "$1" in
        "$APP_DIR"/*) printf '%s\n' "${1#"$APP_DIR"/}" ;;
        *) return 1 ;;
      esac
      ;;
  esac
}

is_broad() {
  local path="$1" rel glob
  for glob in $BROAD_PATHS; do
    # shellcheck disable=SC2254
    case "$path" in $glob) return 0 ;; esac
  done
  rel="$(app_relative "$path")" || return 1
  case "$rel" in
    mix.exs | mix.lock | .credo.exs | .formatter.exs | .sobelow-conf | config/* | priv/* | test/test_helper.exs | test/support/*)
      return 0
      ;;
  esac
  return 1
}

modules_in() {
  sed -nE 's/^[[:space:]]*defmodule[[:space:]]+([A-Z][A-Za-z0-9_.]*).*/\1/p' "$1"
}

tests_naming() {
  local mod
  [ -d "$APP/test" ] || return 0
  for mod in "$@"; do
    (cd "$APP" && { grep -rlwF --include='*_test.exs' -- "$mod" test || true; })
  done
}

# Prints test paths relative to APP_DIR, "ALL" for the whole suite, or nothing.
select_tests() {
  local path rel stem source found
  for path in "$@"; do
    if is_broad "$path"; then
      echo ALL
      continue
    fi
    rel="$(app_relative "$path")" || continue
    case "$rel" in
      test/*_test.exs)
        [ -f "$APP/$rel" ] && echo "$rel"
        ;;
      lib/*.ex | lib/*.heex)
        stem="${rel#lib/}"
        stem="${stem%.ex}"
        stem="${stem%.heex}"
        stem="${stem%.html}"
        found=""
        if [ -f "$APP/test/${stem}_test.exs" ]; then
          found="test/${stem}_test.exs"
        fi
        for source in "lib/$stem.ex" "$(dirname "lib/$stem").ex"; do
          if [ -f "$APP/$source" ]; then
            # shellcheck disable=SC2046
            found="$found
$(tests_naming $(modules_in "$APP/$source"))"
            break
          fi
        done
        found="$(printf '%s\n' "$found" | awk 'NF')"
        if [ -n "$found" ]; then
          printf '%s\n' "$found"
        elif [ -n "$FALLBACK_TESTS" ]; then
          printf '%s\n' "$FALLBACK_TESTS" | tr -s ' ' '\n'
        else
          echo ALL
        fi
        ;;
    esac
  done | sort -u
}

tests_for() {
  if [ -f "$ROOT/scripts/tests_for.exs" ]; then
    printf '%s\n' "$@" | xargs elixir "$ROOT/scripts/tests_for.exs"
  else
    select_tests "$@"
  fi
}

changed_tests() {
  local paths=() tests path args=()
  while IFS= read -r path; do
    paths+=("$path")
  done < <(changed_paths)
  if [ "${#paths[@]}" -eq 0 ]; then
    echo "no changes against ${BASE_BRANCH}"
    return 0
  fi
  for path in "${paths[@]}"; do
    if is_broad "$path"; then
      echo "diff touches shared project files ($path); running the full suite"
      in_app mix test
      return
    fi
  done
  tests="$(tests_for "${paths[@]}")"
  if [ -z "$tests" ]; then
    echo "no Elixir tests map to the diff"
    return 0
  fi
  if grep -qx ALL <<<"$tests"; then
    echo "a changed lib file maps to no test; running the full suite"
    in_app mix test
    return
  fi
  while IFS= read -r path; do
    args+=("$path")
  done <<<"$tests"
  echo "tests: ${args[*]}"
  in_app mix test "${args[@]}"
}

tier_fast() {
  echo "==> format"
  in_app mix format --check-formatted
  echo "==> compile"
  in_app mix compile --warnings-as-errors
  echo "==> credo"
  in_app mix credo --strict
  echo "==> tests for changed files"
  changed_tests
  if declare -F extra_fast >/dev/null; then
    echo "==> extra_fast (scripts/verify.local.sh)"
    extra_fast
  fi
}

tier_full() {
  echo "==> format"
  in_app mix format --check-formatted
  echo "==> compile"
  in_app mix compile --warnings-as-errors
  echo "==> unused locked deps"
  in_app mix deps.unlock --check-unused
  echo "==> credo"
  in_app mix credo --strict
  echo "==> sobelow"
  in_app mix sobelow --config
  echo "==> deps.audit"
  in_app mix deps.audit
  echo "==> hex.audit"
  in_app mix hex.audit
  echo "==> test"
  in_app mix test
  if declare -F extra_full >/dev/null; then
    echo "==> extra_full (scripts/verify.local.sh)"
    extra_full
  fi
}

doctor() {
  local ok=true
  check() {
    if eval "$2" >/dev/null 2>&1; then
      echo "pass  $1"
    else
      echo "FAIL  $1: $3"
      ok=false
    fi
  }
  check "git" "command -v git" "install git"
  check "mix on PATH" "command -v mix" "install Elixir (1.18+, for the JSON module)"
  check "elixir has JSON" "elixir -e 'JSON.encode!(1)'" "Elixir 1.18+ is required for --hook"
  check "app dir $APP_DIR has mix.exs" "test -f '$APP/mix.exs'" "set CHRIS_CHECKS_APP_DIR"
  check "base branch $BASE_BRANCH resolves" "test -n \"\$(base_ref)\"" \
    "git fetch origin $BASE_BRANCH, or set CHRIS_CHECKS_BASE_BRANCH"
  check "deps fetched" "test -d '$APP/deps/credo'" "cd $APP_DIR && mix deps.get"
  [ "$ok" = true ]
}

json_eval() {
  local code="$1"
  elixir -e "
    data =
      case JSON.decode(IO.read(:stdio, :eof)) do
        {:ok, %{} = map} -> map
        _ -> %{}
      end
    $code
  " 2>/dev/null || true
}

hook_kind() {
  printf '%s' "$1" | json_eval '
    cond do
      data["status"] in ["aborted", "error"] -> IO.puts("skip")
      data["cursor_version"] != nil or Map.has_key?(data, "workspace_roots") -> IO.puts("cursor")
      data["hook_event_name"] != nil or data["session_id"] != nil -> IO.puts("claude")
      true -> :ok
    end
  '
}

stop_hook_active() {
  [ "$(printf '%s' "$1" | json_eval 'IO.write(to_string(data["stop_hook_active"] == true))')" = true ]
}

report_failure() {
  local status="$1" kind="$2" output="$3" tier="$4" body msg
  if [ "${#output}" -gt 12000 ]; then
    body="[earlier output truncated]
${output: -12000}"
  else
    body="$output"
  fi
  printf -v msg 'scripts/verify.sh --%s failed (exit %s). Fix the root cause of each finding; do not disable a check, skip a test or loosen a bound. The stop hook runs this again.\n\n%s' "$tier" "$status" "$body"
  printf '%s\n' "$msg" >&2
  if [ "$kind" = "cursor" ]; then
    printf '%s' "$msg" | elixir -e 'IO.puts(JSON.encode!(%{followup_message: IO.read(:stdio, :eof)}))'
    exit 0
  fi
  exit 2
}

main() {
  local tier hook=false hook_input="" kind="" output status
  case "${1:-}" in
    --doctor)
      [ "$#" -eq 1 ] || { usage; exit 2; }
      doctor
      return
      ;;
    --tests-for)
      shift
      tests_for "$@"
      return
      ;;
    --fast) tier=fast ;;
    --full) tier=full ;;
    *) usage; exit 2 ;;
  esac
  case "$#:${2:-}" in
    1:) ;;
    2:--hook) hook=true ;;
    *) usage; exit 2 ;;
  esac
  if [ "$hook" = true ]; then
    hook_input="$(cat)"
  fi
  if [ -n "$hook_input" ]; then
    kind="$(hook_kind "$hook_input")"
  fi
  if [ "$kind" = "skip" ]; then
    exit 0
  fi
  if [ "$kind" = "claude" ] && stop_hook_active "$hook_input"; then
    exit 0
  fi
  if [ -n "$kind" ]; then
    set +e
    output="$(set -e; tier_"$tier" 2>&1)"
    status=$?
    set -e
    if [ "$status" -ne 0 ]; then
      report_failure "$status" "$kind" "$output" "$tier"
    fi
    exit 0
  fi
  tier_"$tier"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
