#!/usr/bin/env python3
# wrap-bash.py — Codex PreToolUse hook that wraps shell commands with
# `direnv exec <envrc_dir> bash -c <cmd>` so the running shell inherits
# the project's direnv-exported environment on every call.
#
# Codex's SessionStart hook cannot export env vars into later tool calls,
# so the SessionStart half (setup-direnv.sh) only locates the .envrc and
# caches its directory in $PLUGIN_DATA/envrc_dir. This script reads that
# cache and rewrites tool_input.command per shell invocation.
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


def main() -> None:
    plugin_data = os.environ.get("PLUGIN_DATA")
    if not plugin_data:
        passthrough()

    cache = pathlib.Path(plugin_data) / "envrc_dir"
    if not cache.is_file():
        passthrough()

    try:
        envrc_dir = cache.read_text().strip()
    except OSError:
        passthrough()
    if not envrc_dir:
        passthrough()

    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        passthrough()

    tool_input = payload.get("tool_input") or {}
    cmd = tool_input.get("command")
    if not isinstance(cmd, str) or not cmd:
        passthrough()

    wrapped = "direnv exec {} bash -c {}".format(
        shlex.quote(envrc_dir),
        shlex.quote(cmd),
    )

    updated = dict(tool_input)
    updated["command"] = wrapped
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


if __name__ == "__main__":
    main()
