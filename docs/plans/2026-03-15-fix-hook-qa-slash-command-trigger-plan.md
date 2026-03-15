# Fix: Hook QA suggestion triggers Skill invocation during /do:work

**Bead:** pojj
**Status:** Ready to implement
**Estimated:** 10m

## Problem

The PostToolUse hook (`plugin-qa-check.sh` line 100) outputs:

```
Run `/compound-workflows:plugin-changes-qa` for full QA (includes semantic checks)
```

During `/do:work`, the model reads this hook stderr and interprets the backtick-wrapped slash-command syntax as an instruction to invoke the Skill tool. The invocation fails because `plugin-changes-qa` has `disable-model-invocation: true`.

## Why the sentinel doesn't always prevent this

`/do:work` creates a `.work-in-progress.d` sentinel (Phase 1.2.1) that suppresses the hook entirely. But if the sentinel check fails for any reason (race condition, path mismatch, stale sentinel cleanup), the hook runs and the problematic output reaches the model.

## Fix

Single-line change in `.claude/hooks/plugin-qa-check.sh`, line 100.

**Before:**
```bash
echo "Run \`/compound-workflows:plugin-changes-qa\` for full QA (includes semantic checks)" >&2
```

**After:**
```bash
echo "Tier 1 QA findings detected. Run plugin-changes-qa after work completes for full QA including semantic checks." >&2
```

Plain text "plugin-changes-qa" without slash prefix or backticks won't trigger Skill invocation. The message remains informative for human readers.

## Scope

- **File:** `.claude/hooks/plugin-qa-check.sh`, line 100
- **No other files** reference this message
- **No behavior change** to hook logic — only output text
- **No QA impact** — this file is outside `plugins/compound-workflows/`, so plugin QA scripts won't flag it
