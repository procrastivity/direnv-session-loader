#!/bin/bash
# setup-direnv.sh (Codex variant) — locate the nearest .envrc and cache its
# directory (plus direnv's resolved binary path) for the PreToolUse wrapper.
#
# Codex's SessionStart hook cannot export env vars into subsequent shell
# tool calls (unlike Claude Code's $CLAUDE_ENV_FILE), so this script only
# does the discovery half: it writes state under
# $PLUGIN_DATA/<session_id>/, which wrap-bash.py reads on every shell
# call to prepend `direnv exec`.
#
# The cache is partitioned by session_id because $PLUGIN_DATA is
# plugin-scoped, not session-scoped — two concurrent Codex sessions in
# different repos would otherwise clobber each other's cache.
#
# We also cache direnv's absolute path (resolved via the extra PATH set
# below) because the shell tool that runs the wrapped command does NOT
# inherit that PATH augmentation, and direnv may not be reachable via
# the tool's default PATH.
#
# Worktree-aware: walks up from the session cwd for a .envrc, then falls
# back to the main git repo root via --git-common-dir.

# Make direnv (and nix, for `use flake`) discoverable in the non-interactive
# hook shell, which does not source your interactive rc files.
export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

[ -z "$PLUGIN_DATA" ] && exit 0

# Codex passes the hook payload as JSON on stdin. We need `cwd` to anchor
# the .envrc walk and `session_id` to partition the cache. Fall back to
# $PWD and "default" respectively if parsing fails.
project_dir=""
session_id=""
if command -v python3 >/dev/null 2>&1; then
  payload_info=$(python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
print(d.get("cwd", ""))
print(d.get("session_id", ""))
' 2>/dev/null) || payload_info=""
  {
    IFS= read -r project_dir
    IFS= read -r session_id
  } <<<"$payload_info"
fi
[ -z "$project_dir" ] && project_dir="$PWD"
[ -z "$session_id" ] && session_id="default"

session_dir="$PLUGIN_DATA/$session_id"
mkdir -p "$session_dir"
cache_file="$session_dir/envrc_dir"
direnv_bin_file="$session_dir/direnv_bin"

# Every SessionStart begins with a clean cache for THIS session. Resumes
# into a directory without an .envrc must not inherit this session's
# earlier cache. Other sessions' caches are untouched (their subdirs).
rm -f "$cache_file" "$direnv_bin_file"

direnv_bin=$(command -v direnv 2>/dev/null) || exit 0
[ -z "$direnv_bin" ] && exit 0

# Cache the resolved direnv path BEFORE the probe. If the probe later
# fails (blocked .envrc, etc.), the user's `direnv allow` recovery
# command still needs an absolute path — otherwise it'd get passed
# through and fail with `direnv: command not found` in a shell tool
# whose PATH doesn't include the direnv binary. wrap-bash.py treats a
# cache with only direnv_bin (no envrc_dir) as recovery-only mode.
printf '%s\n' "$direnv_bin" > "$direnv_bin_file"

# shellcheck source=../lib/find-envrc.sh
. "$(dirname "$0")/../lib/find-envrc.sh"

envrc_path=$(find_envrc "$project_dir") || exit 0
envrc_dir=$(dirname "$envrc_path")

# Probe direnv before caching envrc_dir. If the .envrc is blocked (not
# `direnv allow`ed) or fails to evaluate, `direnv exec` in wrap-bash.py
# would error out before running the user's command. Only cache
# envrc_dir once we know `direnv export bash` succeeds; otherwise report
# the failure the same way the Claude variant does. direnv_bin stays
# cached (written above) so recovery commands still resolve.
err_file=$(mktemp -t direnv-loader.XXXXXX)
exports=$(cd "$envrc_dir" && direnv export bash 2>"$err_file")
status=$?

if [ $status -eq 0 ] && [ -n "$exports" ]; then
  printf '%s\n' "$envrc_dir" > "$cache_file"
  echo "direnv: loaded $envrc_path"
elif [ $status -ne 0 ]; then
  first_err=$(head -n 1 "$err_file")
  echo "direnv: failed to load $envrc_path${first_err:+ ($first_err)}"
fi

rm -f "$err_file"
