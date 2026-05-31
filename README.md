# direnv Session Loader — Claude Code plugin

A minimal Claude Code plugin that loads your project's direnv `.envrc` **once at
session start** and exposes the resulting variables to every Bash tool command
Claude runs during the session.

Claude Code runs each Bash command in a fresh, non-interactive shell that does
not source your `~/.bashrc`/`~/.zshrc`, so the normal direnv shell hook never
fires. This plugin closes that gap with a `SessionStart` hook. It is also
worktree-aware: if no `.envrc` is found by walking up from the project
directory, it falls back to the main git repo root.

## Install

This plugin is distributed through the
[procrastivity](https://github.com/procrastivity/claude-plugins) marketplace.

**First, add the marketplace.**

From within Claude Code:

```
/plugin marketplace add procrastivity/claude-plugins
```

Or from the command line:

```
claude plugin marketplace add procrastivity/claude-plugins
```

**Second, install the plugin.**

From within Claude Code:

```
/plugin install direnv-session-loader@procrastivity
```

Or from the command line:

```
claude plugin install direnv-session-loader@procrastivity
```

## Update

Refresh the marketplace to pull in the latest version.

From within Claude Code:

```
/plugin marketplace update procrastivity
```

Or from the command line:

```
claude plugin marketplace update procrastivity
```

## Scope: SessionStart only (by design)

This intentionally ships **only** a `SessionStart` hook, not `CwdChanged`. The
script resolves the `.envrc` relative to `$CLAUDE_PROJECT_DIR` (fixed for the
session) and appends to `$CLAUDE_ENV_FILE` (it never unloads). That makes it a
load-once design: ideal for the one-worktree-per-session workflow, but it will
**not** reload if Claude `cd`s into a different project with a different
`.envrc` mid-session.

## Notes & caveats

- The script **sources `.envrc` directly** and diffs the environment, so it does
  not require the `direnv` binary to be installed. If you instead want true
  direnv semantics, replace the body with `direnv export bash`.
- The `PATH` line at the top of the script is macOS/Homebrew-flavored; it also
  includes `/usr/bin:/bin` so Linux `git` resolves. Adjust if needed.
- Env vars populated this way reach the **Bash tool only** — not the PowerShell
  tool, MCP servers, or subagents.

## Credits & license

The bundled `setup-direnv.sh` loader is from eshaham:
<https://gist.github.com/eshaham/8e3b63fb077530dffc2964b648145ec9>

MIT. See [LICENSE](LICENSE).
