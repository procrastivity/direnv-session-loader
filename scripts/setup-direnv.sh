#!/bin/bash
# setup-direnv.sh — direnv-backed loader
#
# Loads the nearest direnv .envrc into a Claude Code session at SessionStart by
# running the real `direnv` binary, so the full direnv stdlib works — including
# `use flake` / nix-direnv, `source_url`, `has`, layouts, etc. The previous
# variant sourced .envrc directly, which only ran plain `export` lines and
# silently skipped every direnv directive (so a Nix dev shell never activated).
#
# Worktree-aware: walks up from $CLAUDE_PROJECT_DIR for a .envrc, then falls
# back to the main git repo root via --git-common-dir.
#
# Requires: the `direnv` binary on PATH, and the .envrc must be `direnv allow`ed.
# For `use flake`, Nix must be installed too.
#
# Credit for the discovery logic: eshaham
# https://gist.github.com/eshaham/8e3b63fb077530dffc2964b648145ec9

# Make direnv (and nix, for `use flake`) discoverable in the non-interactive
# hook shell, which does not source your interactive rc files.
export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

[ -z "$CLAUDE_ENV_FILE" ] && exit 0
command -v direnv >/dev/null 2>&1 || exit 0

project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"

find_envrc() {
  local dir="$1"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/.envrc" ]; then
      echo "$dir/.envrc"
      return 0
    fi
    dir=$(dirname "$dir")
  done

  if git -C "$project_dir" rev-parse --show-toplevel >/dev/null 2>&1; then
    local toplevel
    toplevel=$(git -C "$project_dir" rev-parse --show-toplevel 2>/dev/null)
    if [ -f "$toplevel/.envrc" ]; then
      echo "$toplevel/.envrc"
      return 0
    fi

    local common_dir
    common_dir=$(git -C "$project_dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    if [ -n "$common_dir" ]; then
      local main_repo
      main_repo=$(dirname "$common_dir")
      if [ -f "$main_repo/.envrc" ]; then
        echo "$main_repo/.envrc"
        return 0
      fi
    fi
  fi

  return 1
}

envrc_path=$(find_envrc "$project_dir") || exit 0
envrc_dir=$(dirname "$envrc_path")

# Evaluate the .envrc through direnv from its own directory so the full direnv
# stdlib (use flake, source_url, has, layout, ...) runs. This is what makes the
# Nix dev shell — and therefore node, git-cliff, etc. — actually land on PATH.
# Produces nothing if the .envrc is not `direnv allow`ed (fails safe).
exports=$(cd "$envrc_dir" && direnv export bash 2>/dev/null)

if [ -n "$exports" ]; then
  printf '%s\n' "$exports" >> "$CLAUDE_ENV_FILE"
  echo "direnv: loaded $envrc_path"
fi
