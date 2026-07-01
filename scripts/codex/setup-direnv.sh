#!/bin/bash
# setup-direnv.sh (Codex variant) — locate the nearest .envrc and cache its
# directory for the PreToolUse wrapper.
#
# Codex's SessionStart hook cannot export env vars into subsequent shell
# tool calls (unlike Claude Code's $CLAUDE_ENV_FILE), so this script only
# does the discovery half: it writes the resolved envrc directory to
# $PLUGIN_DATA/envrc_dir, which wrap-bash.py reads on every shell call to
# prepend `direnv exec`.
#
# Worktree-aware: walks up from the session cwd for a .envrc, then falls
# back to the main git repo root via --git-common-dir.

# Make direnv (and nix, for `use flake`) discoverable in the non-interactive
# hook shell, which does not source your interactive rc files.
export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

[ -z "$PLUGIN_DATA" ] && exit 0
command -v direnv >/dev/null 2>&1 || exit 0

# Codex passes the hook payload as JSON on stdin. We need `cwd` from it to
# anchor the .envrc walk; fall back to $PWD if parsing fails.
project_dir=""
if command -v python3 >/dev/null 2>&1; then
  project_dir=$(python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
    print(d.get("cwd", ""))
except Exception:
    pass' 2>/dev/null) || project_dir=""
fi
[ -z "$project_dir" ] && project_dir="$PWD"

# shellcheck source=../lib/find-envrc.sh
. "$(dirname "$0")/../lib/find-envrc.sh"

envrc_path=$(find_envrc "$project_dir") || exit 0
envrc_dir=$(dirname "$envrc_path")

mkdir -p "$PLUGIN_DATA"
printf '%s\n' "$envrc_dir" > "$PLUGIN_DATA/envrc_dir"

# Codex surfaces stdout as developer context — matches the Claude UX.
echo "direnv: loaded $envrc_path"
