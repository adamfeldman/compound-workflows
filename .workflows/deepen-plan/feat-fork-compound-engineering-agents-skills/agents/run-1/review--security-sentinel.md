# Security Sentinel Review: Fork compound-engineering Agents & Skills Plan

**Reviewer:** security-sentinel agent methodology
**Date:** 2026-02-25
**Plan under review:** `docs/plans/2026-02-25-feat-fork-compound-engineering-agents-skills-plan.md`
**Risk Level:** MEDIUM (plugin distribution, code redistribution, script execution)

---

## Executive Summary

The plan to fork 21 agents and 14 skills from compound-engineering into compound-workflows is **generally well-structured from a security perspective**, with thoughtful mitigations already in place (NOTICE file, conflict detection, `cp -p` preservation, comprehensive grep sweeps). However, this review identifies **2 HIGH, 3 MEDIUM, and 3 LOW severity findings** across licensing compliance, script security, credential exposure, and supply chain risks that should be addressed before or during execution.

---

## Finding 1: NOTICE File Attribution Is Insufficient for MIT Compliance

**Severity: HIGH**
**Category: MIT License Compliance**

### Issue

The MIT License requires that "the above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software." The planned NOTICE file content (Phase 6a) contains only:

```
This plugin includes agents and skills originally from compound-engineering.

compound-engineering
Copyright (c) 2025 Kieran Klaassen
Licensed under the MIT License
https://github.com/kieranklaassen/compound-engineering
```

This is a summary attribution, not the full license text. The MIT License's own terms ("this permission notice shall be included") require the **full MIT permission notice text** to be reproduced, not merely a statement that the code is MIT-licensed.

### Assessment

I was unable to read the source plugin's LICENSE file directly (permission denied on the cache directory during this review session), but the plan itself references "MIT" and the brainstorm's red team identified "Licensing/attribution" as CRITICAL. The target plugin's LICENSE (`plugins/compound-workflows/LICENSE`) contains the full MIT text attributed to Adam Feldman (2026). This creates a situation where:

1. The target LICENSE covers Adam Feldman's original code.
2. The NOTICE file summarizes Kieran Klaassen's copyright but does NOT include the full permission notice text.
3. Forked files (91 files copied) constitute "substantial portions" of the Software.

### Recommendation

**Option A (Safest):** Include the full MIT license text from compound-engineering in the NOTICE file, not just a summary. The NOTICE file should contain:

```
This plugin includes agents and skills originally from compound-engineering.

compound-engineering
Copyright (c) 2025 Kieran Klaassen

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, [... full MIT text ...]
```

**Option B (Acceptable):** Keep the summary NOTICE but add a `THIRD-PARTY-LICENSES` file or a `licenses/` directory with the full compound-engineering MIT license text. This is a common pattern in open-source projects that incorporate multiple licenses.

**Option C (Minimum):** Verify the source plugin's actual license file. If it uses a standard MIT with no additional terms, Option A is safest. If the source plugin has no LICENSE file (possible for marketplace plugins), document this gap and use the NOTICE as-is with a comment noting the license source is the plugin.json or marketplace metadata.

---

## Finding 2: Copyright Headers in Individual Files Not Addressed

**Severity: MEDIUM**
**Category: Copyright Preservation**

### Issue

The plan does not mention checking for or preserving copyright headers within individual source files. Agent `.md` files and skill scripts may contain:

- Copyright comments at the top of shell scripts (standard practice for `.sh` files)
- License headers in Python scripts (the `gemini-imagegen` skill has 5 scripts)
- Attribution comments in template files

The plan's Phase 7 verification (7a-7g) checks file counts, content correctness, and cross-references, but has **no step to verify copyright headers were preserved** in copied files.

### Assessment

Since the plan uses `cp -p` (preserves mode, ownership, timestamps), file content is copied byte-identical for zero-change files. This is good -- copyright headers in those 55 files will be preserved automatically. However:

- Phase 2-3 modifies 7 agent files and 7 skill files. These modifications (persona removal, genericization) could inadvertently remove or alter copyright headers if they exist.
- The Canonical Genericization Table does not include any copyright-related entries as "do not modify."

### Recommendation

1. Add a Phase 7 verification step: `grep -r "Copyright\|copyright\|LICENSE\|(c)" plugins/compound-workflows/ --include="*.sh" --include="*.py"` to confirm copyright headers survived modifications.
2. In Phase 2-3 instructions, add an explicit note: "Preserve any copyright, license, or attribution comments at the top of files. Do not modify or remove these during genericization."

---

## Finding 3: Executable Script Security Review Missing

**Severity: HIGH**
**Category: Script Permissions / Executable Security**

### Issue

The plan copies scripts with preserved executable permissions via `cp -p` / `cp -rp`. The following skills contain executable scripts:

| Skill | Scripts | Risk |
|-------|---------|------|
| `git-worktree` | `scripts/worktree-manager.sh` | Git operations, filesystem manipulation |
| `gemini-imagegen` | 5 scripts + `requirements.txt` | API calls, possible network access, Python dependency installation |
| `skill-creator` | 3 scripts | Filesystem operations |
| `resolve-pr-parallel` | 2 scripts (`get-pr-comments` + 1 more) | GitHub API calls, possibly uses `gh` CLI |
| `create-agent-skills` | Undetermined (26 files total including references/templates/workflows) | Unknown |

The plan treats these as "zero-change" copies (Phase 1c) with **no security review of script contents before redistribution**. These scripts will run on end-user machines with the user's full shell permissions.

### Assessment

- **`gemini-imagegen`** is the highest risk: it includes a `requirements.txt` (Python dependencies) and 5 scripts. If any script runs `pip install` from that requirements file, it introduces a supply chain attack vector. The requirements file specifies dependency versions that could be hijacked.
- **`resolve-pr-parallel`** accesses GitHub APIs and the plan already notes it contains a hardcoded repo reference (`EveryInc/cora`) that must be genericized. If this is the only hardcoded value, good -- but the script should be reviewed for other hardcoded org/repo references.
- **`git-worktree`** runs git commands that could modify the user's working tree state.
- **All scripts** execute with the user's shell permissions. Malicious or buggy scripts could read `~/.ssh/`, `~/.aws/`, environment variables with tokens, etc.

### Recommendation

1. **Add a Phase 0 or Phase 1 pre-copy step:** Review the contents of ALL executable scripts (approximately 11 files) before copying. Document what each script does, what system resources it accesses, and what external services it contacts.
2. **For `gemini-imagegen`:** Pin exact dependency versions in `requirements.txt` and verify no unexpected packages. Consider whether this skill should have an explicit "this skill requires a Gemini API key" security notice.
3. **For `resolve-pr-parallel`:** Verify `get-pr-comments` does not leak authentication tokens in logs or error output. The `gh` CLI handles auth, but custom scripts may not.
4. **Add to Phase 7:** `find plugins/compound-workflows/skills -type f -perm +111` (or `-executable` on Linux) to enumerate all executable files and confirm the list matches expectations.

---

## Finding 4: Credential and Secret Exposure Risk

**Severity: MEDIUM**
**Category: Credential/Secret Exposure**

### Issue

The plan copies files from a plugin cache directory (`~/.claude/plugins/cache/every-marketplace/compound-engineering/2.35.2/`). While agent `.md` files are unlikely to contain secrets, the following are risk areas:

1. **`gemini-imagegen` scripts:** May contain example API keys, or placeholder keys that look real.
2. **`resolve-pr-parallel` scripts:** May contain hardcoded GitHub tokens or org-specific URLs beyond just `EveryInc/cora`.
3. **`compound-docs` schema.yaml and references:** May contain URLs to internal services or documentation.
4. **`create-agent-skills` (26 files):** Large file count with templates and workflows -- any could contain example credentials.

### Assessment

The plan's Phase 7b grep sweep checks for company-specific terms (BriefSystem, Xiatech, EveryInc) but does **not scan for credential patterns**. There is no check for:
- `APIKEY`, `api_key`, `API_KEY`
- `Bearer `, `token`, `secret`
- `sk-`, `ghp_`, `gho_`, `github_pat_` (common token prefixes)
- Base64-encoded strings that could be credentials
- URLs containing authentication parameters

### Recommendation

Add the following to Phase 7b verification:

```
grep -rE "(api[_-]?key|api[_-]?secret|bearer |token['\"]?\s*[:=]|sk-[a-zA-Z0-9]{20,}|ghp_|gho_|github_pat_)" plugins/compound-workflows/ --include="*.sh" --include="*.py" --include="*.yaml" --include="*.yml" -i
```

This should return zero results. Any match needs manual review.

---

## Finding 5: Path Traversal and Relative Path Confusion

**Severity: LOW**
**Category: Path Traversal**

### Issue

The plan copies files using relative paths between source (`~/.claude/plugins/cache/every-marketplace/compound-engineering/2.35.2/`) and target (`plugins/compound-workflows/`). Two concerns:

1. **Relative path references inside files:** The `learnings-researcher.md` agent contains `../../skills/compound-docs/references/yaml-schema.md` (Phase 3b). This relative path resolves differently depending on whether the file is in the source or target directory tree. The plan correctly notes this must be updated, but it is the only such reference mentioned -- there may be others.

2. **Script internal paths:** Shell scripts in skills may contain paths like `../references/` or `./scripts/` that assume a specific directory structure. If the target directory structure differs from the source, these break silently.

### Assessment

The plan mirrors compound-engineering's directory structure (`research/`, `review/`, `workflow/` under `agents/`; skill directories under `skills/`), which minimizes this risk. Relative path references within skills should continue to work since the internal structure is preserved. The one explicit case (`learnings-researcher.md`) is already identified.

However, there is **no systematic scan for relative path references** across all 91 copied files.

### Recommendation

Add to Phase 7b:
```
grep -rn "\.\./\.\." plugins/compound-workflows/agents/ plugins/compound-workflows/skills/ --include="*.md" --include="*.sh" --include="*.py"
```
Verify each match resolves correctly in the new directory structure. The plan's existing structure-mirroring strategy handles most cases, but `../../` references (two levels up) are particularly fragile and could traverse outside the plugin directory.

---

## Finding 6: Supply Chain Risk from Upstream Fork

**Severity: MEDIUM**
**Category: Supply Chain**

### Issue

The plan creates a fork of compound-engineering v2.35.2. compound-engineering continues to evolve independently (the brainstorm mentions "LLM-assisted periodic merge" as the sync strategy). This creates several supply chain risks:

1. **Upstream security patches:** If compound-engineering patches a vulnerability in an agent prompt or script, compound-workflows may not receive the fix until the next manual sync. There is no automated notification mechanism.

2. **Upstream version pinning:** The plan copies from v2.35.2 specifically. Future syncs would need to diff against this version. If the sync is done carelessly (e.g., copying from "latest" without reviewing changes), malicious or buggy upstream changes could be introduced.

3. **Divergence increases merge risk:** As compound-workflows makes modifications (genericization, persona removal, path changes), merging upstream changes becomes increasingly difficult. An LLM-assisted merge could miss subtle security-relevant changes.

4. **Dual-installation attack surface:** If a user installs both plugins (despite the warning), Claude Code's agent resolution behavior with duplicate agent names is described as "unpredictable." This could cause the wrong version of an agent to run -- potentially one with a known vulnerability that was patched in the other.

### Assessment

The plan acknowledges fork drift as a risk (Risk Mitigation table) and the brainstorm's red team flagged it as CRITICAL. The planned mitigations (README sync note, LLM-assisted merge) are reasonable for an early-stage project. However, the plan lacks specifics on:

- How often syncs will occur
- Who is responsible for syncs
- How security-relevant upstream changes are identified
- What version of upstream is used as the merge base

### Recommendation

1. **Document the fork base version** in the NOTICE file: "Forked from compound-engineering v2.35.2 (commit hash if available)." This enables precise diffing.
2. **Add a `UPSTREAM_VERSION` marker file** or metadata in plugin.json that records the last synced upstream version. This prevents confusion about what version is current.
3. **Define a sync cadence** (even informal: "quarterly" or "when upstream has 5+ new commits"). LLM-assisted merging is a good tool but needs a trigger.
4. **For dual-installation conflict:** The setup command's `ls ~/.claude/plugins/cache/*/compound-engineering` detection (Phase 5c, Step 2) is good. Consider also checking at plugin load time, not just during setup, since users may install compound-engineering after running setup.

---

## Finding 7: The `resolve-pr-parallel` Script Hardcodes Repository Access

**Severity: LOW**
**Category: Credential/Secret Exposure**

### Issue

The plan identifies that `resolve-pr-parallel/scripts/get-pr-comments` contains a hardcoded `EveryInc/cora` repository reference. The plan's remediation is to replace this with `owner/repo` as a placeholder.

### Assessment

A hardcoded `owner/repo` placeholder is safe. However:

1. The script likely uses `gh api` or similar to fetch PR comments. If the placeholder `owner/repo` is not recognized as needing substitution by users, the script will make API calls to a nonexistent repo, which is noisy but not a security issue.
2. The original `EveryInc/cora` reference may have been accompanied by other org-specific context (branch names, label names, team handles) that the plan does not mention scanning for.

### Recommendation

Verify the `get-pr-comments` script does not contain any other `EveryInc` references beyond the one identified. The plan's Phase 7b grep for "EveryInc" covers this -- ensure it runs against script files too (some greps filter by `--include="*.md"` only).

---

## Finding 8: Phase 7b Grep Sweep Does Not Cover All File Types

**Severity: LOW**
**Category: Verification Completeness**

### Issue

Phase 7b's first grep command specifies `--include="*.md" --include="*.yaml" --include="*.json"`. This misses:

- `.sh` scripts (which may contain compound-engineering references in comments or paths)
- `.py` scripts (same)
- `.txt` files (e.g., `requirements.txt`)
- Files without extensions (e.g., `get-pr-comments` in resolve-pr-parallel has no `.sh` extension based on the plan text)

### Assessment

The remaining grep commands in Phase 7b (for `kieran-`, `julik-`, etc.) do NOT specify `--include` filters, meaning they search all files -- good. But the primary `compound-engineering` reference check is filtered to only `.md`, `.yaml`, and `.json`. An orphaned reference in a shell script would be missed.

### Recommendation

Change the first Phase 7b grep to either:
- Remove the `--include` filters entirely (search all files), or
- Add `--include="*.sh" --include="*.py" --include="*.txt"` to the filter list.

---

## Security Requirements Checklist (Adapted for Fork Plan)

- [x] **No hardcoded secrets or credentials** -- Not verified; no credential scan in plan. **Add scan.**
- [x] **Proper attribution** -- NOTICE file planned but content insufficient. **Needs full MIT text.**
- [ ] **Script security review** -- No review of executable script contents before redistribution. **MISSING.**
- [x] **Copyright preservation** -- `cp -p` handles zero-change files; no check for modified files. **Add verification.**
- [x] **Path integrity** -- Structure mirrors source; one relative path identified and addressed. **Add systematic scan.**
- [x] **Supply chain tracking** -- Fork version not recorded in machine-readable format. **Add UPSTREAM_VERSION.**
- [x] **Conflict detection** -- Setup command detects dual installation. **Good.**
- [x] **Content sanitization** -- Phase 7b grep sweep covers company-specific terms. **Extend to all file types.**

---

## Risk Matrix

| # | Finding | Severity | Exploitability | Remediation Effort |
|---|---------|----------|---------------|-------------------|
| 1 | NOTICE file lacks full MIT license text | HIGH | Low (legal, not runtime) | LOW (copy license text) |
| 3 | No security review of executable scripts before redistribution | HIGH | Medium (scripts run with user perms) | MEDIUM (review ~11 files) |
| 2 | No copyright header preservation check for modified files | MEDIUM | Low (legal) | LOW (add grep check) |
| 4 | No credential pattern scan in verification | MEDIUM | Medium (leaked creds in distributed plugin) | LOW (add grep pattern) |
| 6 | Supply chain risk from ongoing fork divergence | MEDIUM | Low (requires upstream compromise) | LOW (document version, set cadence) |
| 5 | No systematic relative path scan | LOW | Low (broken functionality, not security) | LOW (add grep check) |
| 7 | Hardcoded repo reference may have siblings | LOW | Very low | LOW (already partially covered) |
| 8 | Phase 7b grep misses script file types | LOW | Low (missed reference, not exploitable) | LOW (remove include filter) |

---

## Remediation Roadmap (Priority Order)

### Before Execution (Blockers)

1. **Review all executable scripts** (Finding 3) -- Read every `.sh`, `.py`, and extensionless script in the 6 skills being copied. Document what each does. This is ~11 files and should take 30 minutes.
2. **Fix NOTICE file content** (Finding 1) -- Include the full MIT license text from compound-engineering, not just a summary.

### During Execution (Integrate Into Phases)

3. **Add credential scan to Phase 7b** (Finding 4) -- Add the grep pattern for API keys, tokens, and secrets.
4. **Add copyright header check to Phase 7** (Finding 2) -- Verify headers survived in modified files.
5. **Expand Phase 7b grep to all file types** (Finding 8) -- Remove `--include` filter on the `compound-engineering` reference check.
6. **Add relative path scan** (Finding 5) -- Grep for `../..` patterns and verify each resolves correctly.

### After Execution (Ongoing)

7. **Record fork base version** (Finding 6) -- Add `UPSTREAM_VERSION` to plugin metadata.
8. **Define sync cadence** (Finding 6) -- Document when and how upstream merges happen.

---

## Conclusion

The fork plan demonstrates strong security awareness in several areas: the NOTICE file was proactively planned (before any red team flagged it), conflict detection is technical rather than documentation-only, and the verification phase is comprehensive. The two HIGH findings (incomplete MIT compliance and missing script review) are both straightforward to address and should be resolved before Phase 1 execution begins. The MEDIUM findings are verification gaps that can be integrated into the existing Phase 7 checklist with minimal effort.

Overall assessment: **APPROVE WITH CONDITIONS** -- address the two HIGH findings before starting execution; integrate MEDIUM findings into the Phase 7 checklist.
