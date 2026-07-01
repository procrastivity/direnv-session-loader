#!/usr/bin/env python3
# wrap-bash.py — Codex PreToolUse hook that wraps shell commands with
# `<direnv_bin> exec <envrc_dir> bash -c <cmd>` so the running shell
# inherits the project's direnv-exported environment on every call.
#
# Codex's SessionStart hook cannot export env vars into later tool calls,
# so the SessionStart half (setup-direnv.sh) only locates the .envrc and
# caches its directory + the resolved `direnv` binary path under
# $PLUGIN_DATA/<session_id>/. This script reads that cache and rewrites
# tool_input.command per shell invocation.
#
# Output shape: Codex requires PreToolUse rewrites to go inside
# `hookSpecificOutput` alongside `permissionDecision: "allow"`. That
# means wrapping a command also short-circuits the normal approval
# prompt for that call — the trade-off for being able to rewrite it.
# On any unexpected input we emit an empty JSON object so Codex
# proceeds with the original command and normal approval flow.

import json
import os
import pathlib
import shlex
import sys


def passthrough() -> None:
    sys.stdout.write("{}")
    sys.exit(0)


def emit_rewrite(tool_input: dict, new_cmd: str) -> None:
    updated = dict(tool_input)
    updated["command"] = new_cmd
    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "updatedInput": updated,
            }
        },
        sys.stdout,
    )


def main() -> None:
    plugin_data = os.environ.get("PLUGIN_DATA")
    if not plugin_data:
        passthrough()

    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        passthrough()

    # $PLUGIN_DATA is plugin-scoped, not session-scoped. Look up cache
    # under the per-session subdir that SessionStart wrote to.
    session_id = payload.get("session_id") or "default"
    session_dir = pathlib.Path(plugin_data) / session_id
    envrc_cache = session_dir / "envrc_dir"
    direnv_bin_cache = session_dir / "direnv_bin"

    # direnv_bin is the minimum for us to do anything useful. Without
    # it we can't rewrite either wraps or recovery commands.
    if not direnv_bin_cache.is_file():
        passthrough()
    try:
        direnv_bin = direnv_bin_cache.read_text().strip()
    except OSError:
        passthrough()
    if not direnv_bin:
        passthrough()

    # envrc_dir is optional: SessionStart may have cached direnv_bin
    # but failed the .envrc probe (blocked/stale). In that case we're
    # in recovery-only mode — we can still rewrite `direnv ...` calls
    # to use the absolute path so the user can `direnv allow`, but we
    # can't (and shouldn't) wrap other commands in `direnv exec`.
    envrc_dir = ""
    if envrc_cache.is_file():
        try:
            envrc_dir = envrc_cache.read_text().strip()
        except OSError:
            envrc_dir = ""

    tool_input = payload.get("tool_input") or {}
    cmd = tool_input.get("command")
    if not isinstance(cmd, str) or not cmd:
        passthrough()

    tokens = cmd.split(None, 1)
    if not tokens:
        passthrough()

    # Don't wrap `direnv` itself. If the .envrc changes mid-session
    # (agent edits it, or a `git checkout` swaps in a different one),
    # direnv marks it stale/blocked and `direnv exec DIR ...` fails
    # before running its inner command — including a user-issued
    # `direnv allow` to recover. Leaving `direnv` commands out of the
    # `direnv exec` wrap keeps that recovery path open. SessionStart's
    # probe can only catch a stale .envrc that was already stale at
    # session start; mid-session drift needs this second escape hatch.
    #
    # We still substitute the resolved absolute path for `direnv`, so
    # recovery works even if the shell tool's PATH doesn't include the
    # binary's directory.
    if tokens[0] == "direnv":
        remainder = tokens[1] if len(tokens) > 1 else ""
        rewritten = shlex.quote(direnv_bin)
        if remainder:
            rewritten += " " + remainder
        emit_rewrite(tool_input, rewritten)
        return

    # Non-direnv commands need envrc_dir to wrap; without it we're in
    # recovery-only mode and just let the command through.
    if not envrc_dir:
        passthrough()

    wrapped = "{} exec {} bash -c {}".format(
        shlex.quote(direnv_bin),
        shlex.quote(envrc_dir),
        shlex.quote(cmd),
    )
    emit_rewrite(tool_input, wrapped)


if __name__ == "__main__":
    main()
