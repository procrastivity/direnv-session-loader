#!/usr/bin/env bash
# reprobe-direnv.sh — PostToolUse hook that re-runs setup-direnv.sh
# after any `direnv` command completes.
#
# SessionStart's probe caches direnv_bin + envrc_dir once, at the start
# of the session. If the user then runs `direnv allow` (or `direnv
# reload`, `direnv deny`, etc.), the .envrc's loadability changes but
# the cache is stale until the next SessionStart. That's especially
# painful in "recovery mode": SessionStart cached only direnv_bin
# (probe failed), the user ran `direnv allow` to fix it, and now every
# non-direnv command passes through unwrapped until the session
# restarts.
#
# This hook fires after any Bash tool call whose first token is
# `direnv` and re-invokes setup-direnv.sh with the same session_id +
# cwd so the cache reflects the new state on the very next call.

DIR=$(cd "$(dirname "$0")" && pwd)

# Codex includes tool_name, tool_input, and session_id/cwd in the
# PostToolUse payload. Read stdin once (it's a stream), decide whether
# to re-probe, and if so pipe the same payload into setup-direnv.sh —
# which already knows how to pluck cwd + session_id out of it.
payload=$(cat)

command -v python3 >/dev/null 2>&1 || exit 0

matches=$(printf '%s' "$payload" | python3 -c '
import json, os, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print(0); raise SystemExit
if d.get("tool_name") != "Bash":
    print(0); raise SystemExit
cmd = (d.get("tool_input") or {}).get("command") or ""
tokens = cmd.split(None, 1)
# Match by basename because wrap-bash.py rewrites bare `direnv` to the
# cached absolute path (e.g. /opt/homebrew/bin/direnv) BEFORE the tool
# runs, and Codex builds the PostToolUse payload from the rewritten
# tool_input. A plain "direnv" check would miss the rewritten form and
# the recovery path would never trigger a re-probe.
print(1 if tokens and os.path.basename(tokens[0]) == "direnv" else 0)
' 2>/dev/null) || matches=0

if [ "$matches" = "1" ]; then
  printf '%s' "$payload" | "$DIR/setup-direnv.sh"
fi
