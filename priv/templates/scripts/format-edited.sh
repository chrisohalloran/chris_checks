#!/usr/bin/env bash
# Format one Elixir or HEEx file after an agent edit. Cursor afterFileEdit and
# Claude Code PostToolUse both call this. The path is an argument, or the hook
# JSON on stdin (Cursor's file_path, Claude's tool_input.file_path).
set -euo pipefail

APP_DIR="${CHRIS_CHECKS_APP_DIR:-__APP_DIR__}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$ROOT/scripts/verify.local.sh" ]; then
  # shellcheck disable=SC1091
  source "$ROOT/scripts/verify.local.sh"
fi
APP="$ROOT/$APP_DIR"

# Physical path. realpath on Linux and macOS 13+; otherwise walk symlinks and
# take pwd -P, which still collapses "..".
resolve_path() {
  local path="$1" dir name link hops=0
  if command -v realpath >/dev/null 2>&1; then
    realpath "$path"
    return
  fi
  while [ -L "$path" ]; do
    hops=$((hops + 1))
    [ "$hops" -le 20 ] || return 1
    link="$(readlink "$path")"
    case "$link" in
      /*) path="$link" ;;
      *) path="$(dirname -- "$path")/$link" ;;
    esac
  done
  dir="$(dirname -- "$path")"
  name="$(basename -- "$path")"
  dir="$(cd -- "$dir" && pwd -P)" || return 1
  printf '%s/%s\n' "$dir" "$name"
}

if ! command -v mix >/dev/null 2>&1; then
  echo "mix is not on PATH; install Elixir" >&2
  exit 2
fi

file="${1:-}"
if [ "$#" -ge 1 ]; then
  if [ ! -t 0 ]; then
    cat >/dev/null
  fi
else
  file="$(elixir -e '
    data =
      case JSON.decode(IO.read(:stdio, :eof)) do
        {:ok, %{} = map} -> map
        _ -> %{}
      end

    tool = if is_map(data["tool_input"]), do: data["tool_input"], else: %{}
    IO.write(data["file_path"] || tool["file_path"] || tool["path"] || "")
  ' 2>/dev/null || true)"
fi

[ -n "$file" ] || exit 0
case "$file" in
  *.ex | *.exs | *.heex) ;;
  *) exit 0 ;;
esac
case "$file" in
  /*) ;;
  *) file="$ROOT/$file" ;;
esac
[ -f "$file" ] || exit 0
# Resolve before the prefix check, so "$APP/../x.ex" is outside and is not formatted.
file="$(resolve_path "$file")"
app="$(resolve_path "$APP")"
case "$file" in
  "$app"/*) ;;
  *) exit 0 ;;
esac

cd "$app"
if ! mix format "$file"; then
  echo "mix format failed for $file" >&2
  exit 2
fi
