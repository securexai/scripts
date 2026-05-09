# bash/

One-off bash hook scripts. No shared infrastructure: each script is
independent and intended for direct invocation.

Currently this directory holds a single Claude Code hook installer. New
hooks land here without ceremony — there is no library to extend, no
common preamble to share.

## skill-forced-eval-hook.sh

Installs a Claude Code [`UserPromptSubmit`
hook](https://docs.claude.com/en/docs/claude-code/hooks) that nudges the
agent to evaluate available skills against every prompt before responding.
Skills auto-trigger unreliably; this hook forces an explicit check.

What it does, in order:

1. Verifies `jq` is on `PATH` (used to edit `~/.claude/settings.json`).
2. Creates `~/.claude/hooks/` if missing.
3. Writes the hook script at `~/.claude/hooks/skill-forced-eval.sh`
   (chmod +x). The hook prints a fixed system reminder to stdout; Claude
   Code appends the stdout of `UserPromptSubmit` hooks to the prompt
   context.
4. Initializes `~/.claude/settings.json` to `{}` if missing.
5. Registers the hook under `.hooks.UserPromptSubmit[]` using `jq`. The
   registration is idempotent — re-running the installer filters out any
   prior entry pointing at the same script path before appending the new
   one.
6. Prints a verification summary (hook script path, dry-run output of the
   hook, and the current `UserPromptSubmit` registration list).

### Install

```bash
./bash/skill-forced-eval-hook.sh
```

Prerequisite: `jq`. On Fedora hosts, `sudo dnf install jq` (or run it
inside the toolbox where `jq` is already present).

The script is idempotent — safe to re-run after editing the hook content.

After install, restart Claude Code and verify with `/hooks` in the
session.

### Uninstall

There's no automatic uninstall. To remove the hook:

```bash
# Remove the hook script
rm ~/.claude/hooks/skill-forced-eval.sh

# Drop the matching entry from settings.json. The jq filter below removes
# any UserPromptSubmit registration whose nested .hooks[].command points
# at the now-deleted script.
jq 'del(
  .hooks.UserPromptSubmit[]
  | select((.hooks // []) | map(.command) | any(. == "'"$HOME"'/.claude/hooks/skill-forced-eval.sh"))
)' ~/.claude/settings.json > ~/.claude/settings.json.new \
  && mv ~/.claude/settings.json.new ~/.claude/settings.json
```

Restart Claude Code afterwards.

## See also

- [`../README.md`](../README.md) — repo overview
- [Claude Code hooks documentation](https://docs.claude.com/en/docs/claude-code/hooks)
