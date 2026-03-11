---
date: 2026-03-11
bead: 3l7
topic: heuristic-audit-scope-expansion
status: active
---

# Brainstorm: Heuristic Audit Scope Expansion

## What We're Building

Comprehensive elimination of `$()` shell substitution patterns that trigger permission prompts across the entire compound-workflows plugin — commands, skills, and QA tooling. Extends the jak v2.4.1 audit (which only covered commands and accepted init-block patterns as exempt) to cover the full plugin scope.

**Three workstreams:**

1. **Fix prompt-causing patterns** — 11 in skill files (unaudited by jak) + 14 non-exempt in commands + 27 exempt command init markers to eliminate. Total scope: ~38 unique `$()` occurrences (some overlap between exempt markers and regex hits — plan phase produces canonical inventory)
2. **Expand QA Check 5** — scan skills + agents, catch all `$()` positions (not just uppercase VAR= assignments), exclude reference/example docs
3. **Fix QA regex blind spots** — lowercase vars, non-assignment `$()`, arithmetic `$(())`

## Why This Approach

**User principle:** Comprehensive fixes, not targeted. The goal is to eliminate prompt-causing patterns, not just document them.

jak v2.4.1's Decision 1 ("accept init-block prompts") was wrong — Principle 9 now requires feasibility assessment before accepting limitations. The research confirms:

- Script delegation already validated in the codebase (validate-stats.sh for P4)
- init-values.sh approach: `$()` stays inside script file, not in Bash tool input → no heuristic fires → universal auto-approve
- Low expected reliability cost: model parses one structured output instead of tracking across multiple calls. Precedent: work.md branch detection pattern (Pattern A)
- Script delegation handles complex patterns (SHA checksums, jq chains, sed extractions)

## Key Decisions

### D1: Scope — Full plugin, all $() positions
Fix all 38 known patterns + QA regex blind spots. Not just the high-frequency ones.
**Rationale:** User principle is comprehensive. Targeted fixes leave debt that accumulates.

### D2: Three elimination techniques by complexity

| Technique | For patterns | Example |
|-----------|-------------|---------|
| **init-values.sh** | Common init values (P1, P2, P3) | `bash init-values.sh brainstorm` → prints PLUGIN_ROOT, DATE, RUN_ID. No `$()` in tool input. |
| **Script delegation** | Complex logic (P5 misc) | New wrapper scripts like validate-stats.sh |
| **QA regex expansion** | Detection gaps | Catch all `$()` and backticks in any line position |

**Rationale:** init-values.sh handles ~80% of patterns (common init values). Script delegation handles the complex remainder without adding model cognitive load. Both techniques keep `$()` inside script files, not in Bash tool input.

### D3: End state — Eliminate prompts, document residuals
- All patterns that cause permission prompts → eliminated via split-call or script delegation
- Patterns covered by static rules (P7 git heredoc, P9 cat heredoc, P12 ccusage) → leave alone, they don't prompt
- Any remaining heuristic-exempt markers → documented rationale in CLAUDE.md
- Goal is to minimize residuals, not necessarily achieve zero markers

**Rationale:** Pragmatic but thorough. The comprehensive goal (D1) targets prompt-causing patterns specifically; residual exempt markers are acceptable only where static rules already prevent prompts. Silent acceptance of prompt-causing patterns is not OK.

### D4: QA Check 5 expansion — All $() and backtick positions
- Regex expands from `[A-Z_]+=.*\$\(` to match any `$()`, `$(())`, or backtick substitution anywhere in a line
- Scan scope: `commands/compound/*.md` + `skills/*/SKILL.md` + `agents/**/*.md`
- Exclude: `skills/*/references/*.md` and other non-instruction files (example/reference docs contain $() that's illustrative, not executable)
- Exempt markers (`# heuristic-exempt`) still suppress findings
- Agents currently have 0 hits but scanning future-proofs against regressions (red team C2)

**Rationale:** Broader net catches all heuristic-triggering positions including backticks (red team S5). Path filter prevents false positives from reference docs.

## Alternatives Comparison

| Approach | Prompts eliminated | Works without setup | New files | Sonnet risk | Notes |
|----------|-------------------|--------------------|-----------|-----------| ------|
| **init-values.sh** (chosen) | All P1/P2/P3 | Yes — no $() in tool input | 1 script | Low — one output to parse | Bootstrap via clean find call |
| Split-calls | All P1/P2/P3 | Yes — no $() in tool input | 0 | Medium — track 3-5 values across calls | More bash calls per init |
| `bash -c` wrapper | All P1/P2/P3 | No — requires `Bash(bash -c:*)` rule | 0 | Low — one call | Unsafe: universal bypass for inline code |
| Hook modification | Depends on scope | Yes — via hook | 0 | N/A | Hooks can't override $() heuristic — dead end |
| Static rule tuning only | None in plugin | Depends on user rules | 0 | N/A | Doesn't eliminate patterns, just suppresses prompts |
| Script delegation (P5) | Complex patterns | Yes — no $() in tool input | 2-3 scripts | Low — scripts handle logic | Validated precedent (validate-stats.sh) |

## Considered and Rejected

### "Accept init-block prompts" (jak v2.4.1 Decision 1)
Rejected. Most init patterns are eliminable with zero reliability cost. Principle 9 requires feasibility assessment — the assessment shows they're fixable.

### "Fix only high-frequency patterns (P1/P2/P3)"
Rejected. User principle: comprehensive fixes. Leaving P5 misc patterns creates debt that would need a follow-up bead.

### "Zero heuristic-exempt markers everywhere"
Rejected (partially). Static-rule-covered patterns don't cause prompts and rewriting them adds complexity for no UX benefit. The goal is zero prompts, not zero markers.

## Resolved Questions

### Q1: Sonnet robustness of split-call pattern — MITIGATED
**Risk:** Split-calls require the model to track multiple values (date, RUN_ID, PLUGIN_ROOT) across bash calls. Sonnet may be less reliable than Opus at this.

**Decision: Shared init script approach (init-values.sh).** A single script that prints all needed init values on labeled lines. The model calls it with one clean bash command and reads the output.

**Why it works universally (validated via red team S2 analysis):**
- The command string `bash /path/to/init-values.sh brainstorm` contains NO `$()` → no heuristic fires → auto-approves everywhere
- `$()` stays inside the `.sh` file, not in the Bash tool input
- No dependency on static rules, hooks, or setup configuration
- Works in source repo AND consumer projects (auto-approve is default for non-heuristic-triggering commands)

**Bootstrap:** One clean split-call to find the script: `find ~/.claude/plugins -name "init-values.sh" -path "*/compound-workflows/*" | head -1` (also no `$()` in tool input). Model reads the path, uses it. Local path tried first (`bash plugins/compound-workflows/scripts/init-values.sh`), find fallback only when local path doesn't exist.

**Sonnet robustness:** Model reads one structured output block instead of tracking values across 3-5 separate calls. Placeholder validation (warning-on-empty) serves as a safety net.

**Alternatives explored and rejected (red team S2):**
- `bash -c` wrappers: work but require `Bash(bash:*)` or `Bash(bash -c:*)` static rule. `bash -c` is a universal bypass (arbitrary inline code) — not safe for the safe profile. Permissive-only at best.
- Split-calls: work universally but require 3-5 separate calls and Sonnet must track values across them. More fragile than single-output parsing.

### Q3: Check 5 regex specifics — RESOLVED
**Decision: Simple `\$\(` regex with path filtering.** Empirical testing against the current file set confirmed:
- Pattern: `\$\(` matching any position on the line (not just VAR= assignments)
- Scan scope: `$cmd_dir/*.md` + `$plugin_root/skills/*/SKILL.md`
- Exclude: `$plugin_root/skills/*/references/*.md` (2 files with illustrative `$()`)
- Suppress: lines containing `heuristic-exempt` or `context-lean-exempt`
- **25 real hits** (14 commands + 11 skills), **zero false positives**
- Even prose lines are valid findings — they instruct the model to generate `$()` in Bash tool input

**Rationale:** No code-block-aware parsing needed. Every `$()` in a command/skill instruction file is potentially model-executed. Path filter handles the only illustrative-code case (reference docs).

## Deferred Questions (to planning phase)

### Q2: New script inventory
Script delegation for P5 creates new files in `scripts/`. How many new scripts are needed? The plan phase should inventory each P5 pattern and determine whether it needs its own script or can share with an existing one (e.g., validate-stats.sh already handles one pattern, init-values.sh handles P1/P2/P3).

**Deferred rationale:** This is an implementation detail that requires pattern-by-pattern analysis. The brainstorm establishes script delegation as the technique; the plan determines the exact script inventory.

## Red Team Resolution Summary

| ID | Finding | Providers | Severity | Resolution |
|----|---------|-----------|----------|------------|
| C1 | init-values.sh bootstrap (chicken-and-egg) | Gemini | CRITICAL | **Valid — resolved:** two-phase path (local first, find fallback). Both calls clean (no $() in tool input). |
| C2 | Agent scope excluded from scan | OpenAI | CRITICAL | **Valid — updated:** agents added to QA scan scope. Currently 0 hits but future-proofs. |
| S1 | "Zero reliability cost" contradiction | All 3 | SERIOUS | **Valid — fixed:** replaced with "low expected cost" + precedent citation. init-values.sh further mitigates (one output parse vs multi-call tracking). |
| S2 | `bash -c` wrapper alternative | Opus | SERIOUS | **Valid — explored extensively:** bash -c works but requires static rule. `bash -c` is unsafe (universal bypass). init-values.sh is superior: no $() in tool input, auto-approves everywhere, no rule needed. |
| S3 | init-values.sh is unvalidated pattern | Opus, OpenAI | SERIOUS | **Valid — acknowledged:** init-values.sh is new. Plan phase must validate. D2 table updated to reflect init-script as primary technique for P1/P2/P3. |
| S4 | Pattern count inconsistency (38 vs 25) | OpenAI, Opus | SERIOUS | **Valid — fixed:** clarified that 38 = total unique occurrences (exempt + non-exempt). 25 = non-exempt regex hits. Plan phase produces canonical inventory. |
| S5 | Backtick substitution blind spot | Gemini | SERIOUS | **Valid — accepted:** QA regex should also catch backtick substitution. Added to D4 scope. |
| S6 | Rewrite risk (touching every command) | Opus | SERIOUS | **Disagree — note why:** init-values.sh centralizes init logic. Commands change only their init block (replace 3-5 VAR=$() lines with one `bash init-values.sh` call + output parsing). This is a smaller, more uniform change than the feared per-command rewrite. Phased rollout is a planning detail. |

**Fixed (batch):** 2 MINOR fixes applied (D2 rationale text, D1/D3 clarification). **Manual review:** #3 (exempt cap) — qualitative rule sufficient, no numeric cap. #4 (alternatives matrix) — added brief comparison table. **Acknowledged (batch):** 2 no-action items (#5 Q2 deferral, #6 regex noise).
