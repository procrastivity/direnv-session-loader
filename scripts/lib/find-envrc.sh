#!/bin/bash
# find-envrc.sh — shared .envrc discovery for the Claude and Codex variants.
#
# Sourced (not executed) by setup-direnv.sh in both plugin flavors. Walks up
# from the given starting directory looking for a .envrc, then falls back to
# the git toplevel and, finally, the main worktree root via --git-common-dir
# so worktrees inherit the parent repo's .envrc.
#
# Credit for the discovery logic: eshaham
# https://gist.github.com/eshaham/8e3b63fb077530dffc2964b648145ec9

# Usage: find_envrc <start-dir>
# Prints the absolute path to the discovered .envrc on stdout, or returns 1.
find_envrc() {
  local dir="$1"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/.envrc" ]; then
      echo "$dir/.envrc"
      return 0
    fi
    dir=$(dirname "$dir")
  done

  if git -C "$1" rev-parse --show-toplevel >/dev/null 2>&1; then
    local toplevel
    toplevel=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)
    if [ -f "$toplevel/.envrc" ]; then
      echo "$toplevel/.envrc"
      return 0
    fi

    local common_dir
    common_dir=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
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
