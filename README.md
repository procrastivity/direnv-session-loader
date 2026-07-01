# direnv Session Loader — Claude Code & Codex plugin

A minimal plugin (Claude Code and OpenAI Codex CLI) that loads your project's
direnv `.envrc` so every shell command the agent runs sees the right
environment. Both CLIs spawn shell calls in fresh, non-interactive shells that
don't source your `~/.bashrc`/`~/.zshrc`, so the normal direnv shell hook never
fires. This plugin closes that gap.

It is worktree-aware: if no `.envrc` is found by walking up from the project
directory, it falls back to the main git repo root.

## Install (Claude Code)

This plugin is distributed through the
[procrastivity](https://github.com/procrastivity/claude-plugins) marketplace.

### From within Claude Code

Add the marketplace (if not already added).

```
/plugin marketplace add procrastivity/claude-plugins
```

Install the plugin.

```
/plugin install direnv-session-loader@procrastivity
```

### From the command line

Add the marketplace (if not already added).

```
claude plugin marketplace add procrastivity/claude-plugins
```

Install the plugin.

```
claude plugin install direnv-session-loader@procrastivity
```

## Update

Refresh the marketplace to pull in the latest version.

### From within Claude Code

```
/plugin marketplace update procrastivity
```

### From the command line

```
claude plugin marketplace update procrastivity
```

## Install (Codex CLI)

The Codex variant is distributed through the sibling
[procrastivity/codex-plugins](https://github.com/procrastivity/codex-plugins)
marketplace, which mirrors the Codex-relevant slice of this repo. (Codex's
marketplace schema requires plugin files to live inside the marketplace
repo, so this plugin can't be installed by pointing Codex at this repo
directly.)

### From the command line

Add the marketplace (if not already added).

```
codex plugin marketplace add procrastivity/codex-plugins
```

Install the plugin.

```
codex plugin add direnv-session-loader@procrastivity-codex
```

### From within Codex

```
/plugins
```

Browse to `procrastivity (Codex)`, select **direnv-session-loader**,
and install.

The Codex plugin requires `python3` on `PATH` in addition to `direnv`.

## How it differs between Claude Code and Codex

Claude Code's `SessionStart` hook can append `export KEY=VAL` lines to
`$CLAUDE_ENV_FILE`, and the harness merges those into every Bash tool spawn
for the rest of the session. One shot, done.

Codex's `SessionStart` hook *cannot* mutate the env of later tool calls —
its output is added to developer context, not exported. So the Codex
variant runs as two hooks:

- `SessionStart` locates the `.envrc` (same discovery logic) and caches its
  directory in `$PLUGIN_DATA`.
- `PreToolUse` rewrites every shell tool call to
  `direnv exec <envrc_dir> bash -c <cmd>`, so the running shell inherits
  the direnv-exported environment.

`direnv exec` is fast (it caches the export), so the per-call overhead is
small. The trade-off is that the resolved `.envrc` is fixed at session
start — neither variant reloads if the agent `cd`s into a different
project mid-session.

## Scope: SessionStart only (by design)

The Claude variant intentionally ships **only** a `SessionStart` hook, not
`CwdChanged`. The script resolves the `.envrc` relative to
`$CLAUDE_PROJECT_DIR` (fixed for the session) and appends to
`$CLAUDE_ENV_FILE` (it never unloads). That makes it a load-once design:
ideal for the one-worktree-per-session workflow, but it will **not** reload
if Claude `cd`s into a different project with a different `.envrc`
mid-session. The Codex variant inherits the same load-once trade-off via
its cached `envrc_dir`.

## Notes & caveats

- The script shells out to the `direnv` binary, so direnv must be installed and
  the `.envrc` must be `direnv allow`'d. This gives you the full direnv stdlib
  (`use flake`, `source_url`, `has`, layouts, etc.) — including nix-direnv for
  Nix dev shells.
- The `PATH` line at the top of the script is macOS/Homebrew-flavored; it also
  includes `/usr/bin:/bin` so Linux `git` resolves. Adjust if needed.
- Env vars populated this way reach the **shell tool only** — not other tool
  types, MCP servers, or subagents.

## Credits & license

The bundled `setup-direnv.sh` loader is from eshaham:
<https://gist.github.com/eshaham/8e3b63fb077530dffc2964b648145ec9>

MIT. See [LICENSE](LICENSE).
