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

# shellcheck source=lib/find-envrc.sh
. "$(dirname "$0")/lib/find-envrc.sh"

envrc_path=$(find_envrc "$project_dir") || exit 0
envrc_dir=$(dirname "$envrc_path")
# Normalize to realpath — `direnv exec DIR ...` (used below) keys its allow
# lookup on the realpath, so a symlinked project dir (e.g. macOS `/var/…`
# which shadows `/private/var/…`) would be treated as not-allowed even though
# it is. `cd && pwd -P` sidesteps that without needing coreutils' realpath.
envrc_dir=$(cd "$envrc_dir" && pwd -P) || exit 0

# Evaluate the .envrc through direnv from its own directory so the full direnv
# stdlib (use flake, source_url, has, layout, ...) runs. This is what makes the
# Nix dev shell — and therefore node, git-cliff, etc. — actually land on PATH.
# Produces nothing if the .envrc is not `direnv allow`ed (fails safe).
#
# Capture stderr separately so a partially-failing .envrc (e.g. `use flake`
# without Nix installed) surfaces the error instead of silently applying a
# partial export block.
err_file=$(mktemp -t direnv-loader.XXXXXX)

# The PATH this hook sees is exactly the tail direnv's `use flake` PATH will
# end with. Snapshot it so we can strip it back off and defer that tail to a
# literal $PATH — otherwise direnv's wholesale `export PATH=$'…'` overwrites
# Claude Code's Bash-tool base PATH and evicts every enabled plugin's bin/.
P0="$PATH"

exports=$(cd "$envrc_dir" && direnv export bash 2>"$err_file")
status=$?

if [ "$status" -eq 0 ] && [ -n "$exports" ]; then
  # Recompute the loaded PATH via `direnv exec` instead of parsing direnv's
  # $'…' quoting out of $exports.
  Pd=$(cd "$envrc_dir" && direnv exec "$envrc_dir" bash -c 'printf %s "$PATH"' 2>/dev/null)
  prefix="${Pd%"$P0"}"

  # Emit everything EXCEPT direnv's wholesale PATH assignment.
  non_path=$(printf '%s\n' "$exports" | perl -0pe "s/(?:^|;)\s*export PATH=\\\$?'[^']*';?//g")
  printf '%s\n' "$non_path" >> "$CLAUDE_ENV_FILE"

  # Then re-emit PATH as a deferred prepend so flake dirs land in front of
  # Claude Code's base PATH (which already carries every plugin's bin/).
  # The literal `$PATH` in the printf format expands at apply-time, not now.
  if [ -n "$prefix" ] && [ "$prefix" != "$Pd" ]; then
    printf 'export PATH=%s"$PATH"\n' "$prefix" >> "$CLAUDE_ENV_FILE"
  elif [ -n "$Pd" ] && [ "$prefix" = "$Pd" ]; then
    # .envrc reordered/removed entries — no clean suffix match. Fall back
    # to the wholesale assignment for correctness (accepts the clobber).
    printf 'export PATH=%q\n' "$Pd" >> "$CLAUDE_ENV_FILE"
  fi
  # prefix empty (or Pd empty) → emit no PATH line; base PATH stands.

  echo "direnv: loaded $envrc_path"
elif [ "$status" -ne 0 ]; then
  first_err=$(head -n 1 "$err_file")
  echo "direnv: failed to load $envrc_path${first_err:+ ($first_err)}"
fi

rm -f "$err_file"
