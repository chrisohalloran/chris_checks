# Agent instructions

## Test and check

- `scripts/verify.sh --fast`: format, compile with warnings as errors, `mix credo --strict`, then the tests that reach the files changed since the base branch. The stop hook runs this and sends failures back to the agent.
- `scripts/verify.sh --full`: what CI runs (adds sobelow, deps.audit and the whole suite).
- After an edit, `scripts/format-edited.sh` formats that Elixir or HEEx file.
- Fix the root cause of a finding. Never disable a check, skip a test, or loosen a bound to get green.
- When a review corrects you, turn the correction into a check (a Credo check or a test), not a note.
