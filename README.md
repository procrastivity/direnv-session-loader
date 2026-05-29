# direnv Session Loader — Claude Code plugin

A minimal Claude Code plugin that loads your project's direnv `.envrc` **once at
session start** and exposes the resulting variables to every Bash tool command
Claude runs during the session.

Claude Code runs each Bash command in a fresh, non-interactive shell that does
not source your `~/.bashrc`/`~/.zshrc`, so the normal direnv shell hook never
fires. This plugin closes that gap with a `SessionStart` hook. It is also
worktree-aware: if no `.envrc` is found by walking up from the project
directory, it falls back to the main git repo root.

The bundled script is from eshaham:
<https://gist.github.com/eshaham/8e3b63fb077530dffc2964b648145ec9>

## What's inside

```
direnv-session-loader/
├── .claude-plugin/
│   └── plugin.json          # manifest (only `name` is strictly required)
├── hooks/
│   └── hooks.json           # wires scripts/setup-direnv.sh to SessionStart
└── scripts/
    └── setup-direnv.sh      # eshaham's worktree-aware loader (must be +x)
```

`hooks/hooks.json` is the default auto-discovered hook location, so it does not
need to be referenced from `plugin.json`. The hook command uses
`${CLAUDE_PLUGIN_ROOT}` so it resolves to wherever the plugin is installed.

## Scope: SessionStart only (by design)

This intentionally ships **only** a `SessionStart` hook, not `CwdChanged`. The
script resolves the `.envrc` relative to `$CLAUDE_PROJECT_DIR` (fixed for the
session) and appends to `$CLAUDE_ENV_FILE` (it never unloads). That makes it a
load-once design: ideal for the one-worktree-per-session workflow, but it will
**not** reload if Claude `cd`s into a different project with a different
`.envrc` mid-session. If you need that, see "Extending" below.

## Try it locally

From the directory that contains this plugin folder:

```bash
claude --plugin-dir ./direnv-session-loader
```

Then, inside the session, confirm a variable from your `.envrc` is present:

```bash
echo "$SOME_VAR_FROM_ENVRC"
```

Run `claude --debug` to see the plugin load and the hook register. Validate the
manifest and hook config with:

```bash
claude plugin validate ./direnv-session-loader --strict
```

## Test the script in isolation

Simulate a session with the env cleared (mirrors eshaham's test):

```bash
env -u SOME_VAR \
  CLAUDE_PROJECT_DIR=/path/to/your/repo \
  CLAUDE_ENV_FILE=/tmp/test-env \
  ./direnv-session-loader/scripts/setup-direnv.sh

cat /tmp/test-env
```

## Distribute via a marketplace

To share it, add a `marketplace.json` to a marketplace repo that points at this
plugin, then install with `claude plugin install direnv-session-loader@<marketplace>`.
See the Claude Code docs on plugin marketplaces.

## Notes & caveats

- The script **sources `.envrc` directly** and diffs the environment, so it does
  not require the `direnv` binary to be installed. If you instead want true
  direnv semantics, replace the body with `direnv export bash`.
- The `PATH` line at the top of the script is macOS/Homebrew-flavored; it also
  includes `/usr/bin:/bin` so Linux `git` resolves. Adjust if needed.
- Make sure the script keeps its executable bit: `chmod +x scripts/setup-direnv.sh`.
- Env vars populated this way reach the **Bash tool only** — not the PowerShell
  tool, MCP servers, or subagents.

## Extending: add CwdChanged

To also reload on directory changes, switch the script from append (`>>`) to
overwrite (single `>` of `$CLAUDE_ENV_FILE`) or add snapshot-based unload logic,
then add a `CwdChanged` block to `hooks/hooks.json` mirroring the `SessionStart`
one. Without that change, firing the current append-only script on every `cd`
would accumulate stale variables from directories you've left.

## License

MIT (placeholder — update `plugin.json` and add a LICENSE file as you prefer).
The bundled `setup-direnv.sh` is credited to eshaham via the gist linked above.
