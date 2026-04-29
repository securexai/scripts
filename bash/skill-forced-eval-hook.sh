#!/usr/bin/env bash
# bootstrap-claude-skill-hook.sh
# Sets up the UserPromptSubmit hook that forces skill evaluation on every prompt.
# Idempotent — safe to re-run.

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
HOOKS_DIR="$CLAUDE_DIR/hooks"
HOOK_SCRIPT="$HOOKS_DIR/skill-forced-eval.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

# -----------------------------------------------------------------------------
# 1. Prerequisites
# -----------------------------------------------------------------------------
command -v jq >/dev/null || {
    echo "ERROR: jq required. Install: sudo dnf install jq"
    exit 1
}

# -----------------------------------------------------------------------------
# 2. Create directories
# -----------------------------------------------------------------------------
mkdir -p "$HOOKS_DIR"

# -----------------------------------------------------------------------------
# 3. Write the hook script
# -----------------------------------------------------------------------------
cat > "$HOOK_SCRIPT" <<'EOF'
#!/usr/bin/env bash
# UserPromptSubmit hook: force Claude Code to evaluate available skills
# against every prompt before responding.
#
# Skills auto-trigger unreliably (~50% hit rate in the wild). This hook
# injects a system reminder on every turn that makes Claude explicitly
# evaluate relevant skills and invoke them via the Skill() tool. stdout
# from UserPromptSubmit is appended to Claude's context — this is the
# documented behavior.

cat <<'REMINDER'
INSTRUCTION: MANDATORY SKILL EVALUATION

Before responding, check <available_skills> for any skill relevant to
the user's request.

IF one or more skills are relevant:
  1. State which skills apply and why (one line each).
  2. Invoke each relevant skill via the Skill() tool.
  3. Then respond using the skill's guidance.

IF no skills are relevant:
  Proceed directly without comment.

Mentioning a skill without invoking it via Skill() is insufficient —
the full skill content only loads into context when Skill() is called.
REMINDER
EOF

chmod +x "$HOOK_SCRIPT"

# -----------------------------------------------------------------------------
# 4. Ensure settings.json exists
# -----------------------------------------------------------------------------
if [[ ! -f "$SETTINGS" ]]; then
    echo '{}' > "$SETTINGS"
fi

# Validate existing JSON before we touch it
jq empty "$SETTINGS" || {
    echo "ERROR: $SETTINGS is not valid JSON. Fix or remove it and re-run."
    exit 1
}

# -----------------------------------------------------------------------------
# 5. Register the hook (idempotent — overwrites any existing entry for this
#    exact script path, preserves other UserPromptSubmit hooks)
# -----------------------------------------------------------------------------
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

jq --arg cmd "$HOOK_SCRIPT" '
  # Preserve all existing UserPromptSubmit entries that do NOT point at our script,
  # then append ours. This way re-running the bootstrap is a no-op.
  .hooks.UserPromptSubmit = (
    (.hooks.UserPromptSubmit // [])
    | map(select(
        (.hooks // []) | map(.command != $cmd) | all
      ))
    | . + [{
        "hooks": [{
          "type": "command",
          "command": $cmd
        }]
      }]
  )
' "$SETTINGS" > "$TMPFILE"

mv "$TMPFILE" "$SETTINGS"

# -----------------------------------------------------------------------------
# 6. Verify
# -----------------------------------------------------------------------------
echo "=== Hook script ==="
ls -la "$HOOK_SCRIPT"

echo
echo "=== Hook script output (dry run) ==="
"$HOOK_SCRIPT" | head -3

echo
echo "=== Registered UserPromptSubmit hooks ==="
jq '.hooks.UserPromptSubmit' "$SETTINGS"

echo
echo "Done. Restart Claude Code and verify with /hooks inside the session."