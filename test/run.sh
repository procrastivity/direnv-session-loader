#!/usr/bin/env bash
# test/run.sh — integration tests for scripts/setup-direnv.sh.
#
# Each case builds a temp project with a .envrc, `direnv allow`s it under a
# hermetic XDG_DATA_HOME so the user's real direnv allowlist is untouched,
# runs the hook, then applies the emitted $CLAUDE_ENV_FILE over a synthetic
# BASE PATH and checks the result. `use flake` is stood in for by `PATH_add`,
# which triggers the same wholesale `export PATH=$'…'` shape from
# `direnv export bash` without requiring Nix.

set -u

test_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$test_dir/.." && pwd)
loader="$repo_root/scripts/setup-direnv.sh"

direnv_bin=$(command -v direnv 2>/dev/null || true)
if [ -z "$direnv_bin" ]; then
  echo "SKIP: direnv not installed"
  exit 0
fi
direnv_dir=$(dirname "$direnv_bin")

pass=0
fail=0
failures=()

setup_case() {
  # sets: work (project dir), env_file (CLAUDE_ENV_FILE), plugin_bin,
  # devshell_bin, xdg (hermetic direnv state)
  work=$(mktemp -d -t dsl-test.XXXXXX)
  env_file="$work/env"
  : > "$env_file"
  plugin_bin="$work/fakeplugin/bin"
  devshell_bin="$work/devshell/bin"
  mkdir -p "$plugin_bin" "$devshell_bin"
  xdg="$work/xdg"
  mkdir -p "$xdg"
}

teardown_case() {
  rm -rf "$work"
}

# Runs the loader against $work with a hermetic direnv state, using
# BASE_PATH as the hook's PATH so P0 is known and testable.
run_loader() {
  local base_path="$1"
  (
    unset DIRENV_DIR DIRENV_FILE DIRENV_WATCHES DIRENV_DIFF
    export XDG_DATA_HOME="$xdg/data" XDG_CONFIG_HOME="$xdg/cfg"
    export CLAUDE_ENV_FILE="$env_file"
    export CLAUDE_PROJECT_DIR="$work"
    # Sandwich: preserve the ambient direnv/nix path prefix the loader
    # itself prepends (line 21), then use base_path as the "hook baseline"
    # so P0 = <ambient>:base_path. Deferred prefix ends up = flake dirs
    # only.
    export PATH="$base_path"
    bash "$loader"
  ) >"$work/hook.out" 2>"$work/hook.err"
}

# Applies $env_file over base_path in a subshell and prints the resulting PATH.
apply_env() {
  local base_path="$1"
  (
    export PATH="$base_path"
    # shellcheck disable=SC1090
    . "$env_file"
    printf '%s' "$PATH"
  )
}

# Look up a bare command against a specific PATH (no side effects).
resolves() {
  ( export PATH="$1"; command -v "$2" 2>/dev/null; )
}

record_pass() { echo "PASS: $1"; pass=$((pass + 1)); }
record_fail() { echo "FAIL: $1: $2"; fail=$((fail + 1)); failures+=("$1"); }

allow_envrc() {
  (
    export XDG_DATA_HOME="$xdg/data" XDG_CONFIG_HOME="$xdg/cfg"
    cd "$work" && direnv allow >/dev/null 2>&1
  )
}

# -----------------------------------------------------------------------------
# Case 1: plugin bin survives a PATH-rewriting .envrc
# -----------------------------------------------------------------------------
case_plugin_bin_survives() {
  local name="plugin bin survives PATH-rewriting .envrc"
  setup_case
  cat > "$work/.envrc" <<EOF
PATH_add "$devshell_bin"
EOF
  # sentinel-bin only in the plugin dir (base PATH)
  cat > "$plugin_bin/sentinel-bin" <<'EOF'
#!/bin/sh
echo sentinel
EOF
  chmod +x "$plugin_bin/sentinel-bin"

  allow_envrc

  local base="$direnv_dir:/usr/bin:/bin:$plugin_bin"
  run_loader "$base"

  local applied
  applied=$(apply_env "$base")

  if ! resolves "$applied" sentinel-bin >/dev/null; then
    record_fail "$name" "sentinel-bin not resolvable after applying env_file. PATH=$applied"
    teardown_case; return
  fi

  case "$applied" in
    "$devshell_bin":*"$plugin_bin"*) record_pass "$name" ;;
    *) record_fail "$name" "devshell not ahead of plugin. PATH=$applied" ;;
  esac
  teardown_case
}

# -----------------------------------------------------------------------------
# Case 2: no-op .envrc (only exports FOO=bar) emits no PATH line
# -----------------------------------------------------------------------------
case_noop_envrc() {
  local name="no-op .envrc leaves PATH untouched, FOO passes through"
  setup_case
  cat > "$work/.envrc" <<'EOF'
export FOO=bar
EOF
  allow_envrc

  local base="$direnv_dir:/usr/bin:/bin:$plugin_bin"
  run_loader "$base"

  if grep -q '^export PATH=' "$env_file"; then
    record_fail "$name" "unexpected 'export PATH=' line emitted:
$(cat "$env_file")"
    teardown_case; return
  fi

  local applied foo_val
  applied=$(apply_env "$base")
  foo_val=$(
    export PATH="$base"
    # shellcheck disable=SC1090
    . "$env_file"
    printf '%s' "${FOO:-}"
  )

  if [ "$applied" != "$base" ]; then
    record_fail "$name" "PATH mutated. expected=$base got=$applied"
    teardown_case; return
  fi
  if [ "$foo_val" != "bar" ]; then
    record_fail "$name" "FOO not passed through. got='$foo_val'
env_file:
$(cat "$env_file")"
    teardown_case; return
  fi
  record_pass "$name"
  teardown_case
}

# -----------------------------------------------------------------------------
# Case 3: unallowed .envrc → nothing written (fail-safe)
# -----------------------------------------------------------------------------
case_unallowed_envrc() {
  local name="unallowed .envrc writes nothing (fail-safe)"
  setup_case
  cat > "$work/.envrc" <<EOF
PATH_add "$devshell_bin"
export FOO=bar
EOF
  # Note: NOT calling allow_envrc.

  local base="$direnv_dir:/usr/bin:/bin:$plugin_bin"
  run_loader "$base"

  if [ -s "$env_file" ]; then
    record_fail "$name" "env_file not empty:
$(cat "$env_file")"
    teardown_case; return
  fi
  record_pass "$name"
  teardown_case
}

# -----------------------------------------------------------------------------
# Case 4: flake/devshell tool takes precedence over same-named plugin tool
# -----------------------------------------------------------------------------
case_flake_precedence() {
  local name="devshell copy of same-named tool wins over plugin copy"
  setup_case
  cat > "$work/.envrc" <<EOF
PATH_add "$devshell_bin"
EOF

  cat > "$plugin_bin/sentinel-bin" <<'EOF'
#!/bin/sh
echo plugin
EOF
  chmod +x "$plugin_bin/sentinel-bin"
  cat > "$devshell_bin/sentinel-bin" <<'EOF'
#!/bin/sh
echo devshell
EOF
  chmod +x "$devshell_bin/sentinel-bin"

  allow_envrc

  local base="$direnv_dir:/usr/bin:/bin:$plugin_bin"
  run_loader "$base"

  local applied resolved
  applied=$(apply_env "$base")
  resolved=$(resolves "$applied" sentinel-bin)

  case "$resolved" in
    "$devshell_bin"/sentinel-bin) record_pass "$name" ;;
    *) record_fail "$name" "expected devshell copy, got '$resolved'. PATH=$applied" ;;
  esac
  teardown_case
}

case_plugin_bin_survives
case_noop_envrc
case_unallowed_envrc
case_flake_precedence

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
