# Fix: Compact-prep Sonnet savings ratio (q55q)

**Bead:** q55q
**Status:** Ready to implement
**Estimated:** 18m
**File:** `plugins/compound-workflows/skills/do-compact-prep/SKILL.md`

---

## Problem

Line 159 calculates Sonnet savings as `sonnet_cost * 4`, assuming a 5x Opus:Sonnet price ratio. The actual Opus 4.6 ratio is 1.67x (cache read $0.50 vs $0.30). The formula overstates savings by ~6x.

## Fix

Change line 159 from:

```
sonnet_cost * 4 (what those tokens would have cost on Opus minus what they actually cost on Sonnet — Sonnet is ~5x cheaper, so savings = sonnet_cost * 4)
```

To:

```
sonnet_cost * 0.67 (what those tokens would have cost on Opus minus what they actually cost on Sonnet — Opus 4.6 cache read is 1.67x Sonnet, so savings = sonnet_cost * 0.67)
```

The percentage formula on the same line is correct and unchanged: `savings / (total_cost + savings) * 100`.

## Scope

- Line 159 of `SKILL.md` — the savings formula text
- No other files reference this ratio

## Version bump

Change is in `plugins/compound-workflows/`, so:

1. Bump patch version in `plugins/compound-workflows/.claude-plugin/plugin.json`
2. Bump patch version in `.claude-plugin/marketplace.json`
3. Add CHANGELOG entry in `plugins/compound-workflows/CHANGELOG.md`
4. Verify README component counts (no change expected)

## QA

Run `/compound-workflows:plugin-changes-qa` (Tier 1 + Tier 2) after changes.
