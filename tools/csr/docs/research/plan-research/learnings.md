# Institutional Learnings for Claude Session Resume Feature

## Search Context
- **Feature/Task**: Claude Code session management tool with tmux/shell integration, worktree support, hook configuration, and CLI tooling
- **Keywords Used**: session, tool, workflow, hook, integration, CLI, tmux, shell
- **Files Scanned**: docs/solutions/ across 10 categories
- **Relevant Matches**: 4 files in workflow-design and process categories

## Critical Patterns
No critical-patterns.md file exists yet in the solutions directory, but the workflow-design category contains core architectural patterns.

## Relevant Learnings

### 1. Upstream Fork Management Pattern for Workflow Skills
**File**: /Users/adamf/Work/Strategy/docs/solutions/workflow-design/upstream-fork-management-pattern.md
- **Category**: workflow-design
- **Relevance**: This session involves a tool (claude-session-resume) that may fork/diverge from an upstream pattern. The fork management pattern shows how to selectively port improvements, categorize deltas, and discuss each change rather than batch-implementing.
- **Key Insight**: Don't blindly copy upstream changes. Discuss each delta with context, adapt ideas rather than copying code, and be prepared for cross-cutting enhancements that emerge from discussion. Use a beads issue to track ideas across sessions.
- **Actionable Takeaway**: When claude-session-resume integrates with other tools (PAL agents, beads, worktrees), document local adaptations vs. upstream patterns. Track integration ideas in a beads issue to avoid silent feature creep.

### 2. Origin Traceability Chain and Phase-Boundary Gate Principle
**File**: /Users/adamf/Work/Strategy/docs/solutions/workflow-design/origin-traceability-and-phase-boundary-gates.md
- **Category**: workflow-design
- **Relevance**: Session resume needs to track context across phases (session suspend → resume → continue work). The origin traceability pattern shows how to maintain provenance chains without central registries.
- **Key Insight**: Use `origin:` fields to link artifacts back to their parent (e.g., session state points to the plan/work that created it). Apply phase-boundary gates at critical handoff points to prevent unresolved items from leaking silently between phases. Three options at every gate: resolve now, defer with rationale, or remove.
- **Actionable Takeaway**: Session resume must explicitly surface deferred work items, unresolved decisions, and context from the suspended session. Don't silently resume with incomplete state. Add a gate when resuming to ask: "Are these deferred items still valid? Do you want to change direction?"

### 3. Red Team Challenge Pattern via PAL MCP
**File**: /Users/adamf/Work/Strategy/docs/solutions/workflow-design/red-team-challenge-via-pal-mcp.md
- **Category**: workflow-design
- **Relevance**: Session resume will integrate with PAL agents and multi-model workflows. Red-teaming pattern shows how to avoid self-agreement and introduce adversarial pressure.
- **Key Insight**: Invoking the same model twice to review itself produces false confidence. Use different models (Gemini vs. Claude) as red team challengers, rate findings as CRITICAL/SERIOUS/MINOR, and escalate disputes to consensus for deadlock-breaking.
- **Actionable Takeaway**: If session resume surfaces conflicting advice from PAL agents, use PAL `consensus` to arbitrate rather than defaulting to the first response. Severity ratings help distinguish "nice to have" from "blocks resumption."

### 4. Adapting Code-Centric Tools for Analytical/Strategic Work
**File**: /Users/adamf/Work/Strategy/docs/solutions/workflow-design/adapting-code-tools-for-analytical-work.md
- **Category**: workflow-design
- **Relevance**: Session resume is a hybrid tool (code-focused shell integration + analytical/strategic session context). Pattern shows how to serve both modes with one structure instead of forking.
- **Key Insight**: Use dual-column mode detection tables instead of two separate checklists. Same workflow phases, different context-specific prompts. The pattern applies to: artifacts (code changes vs. documents), verification (tests pass vs. evidence checked), and value ("next time this breaks" vs. "next time this question comes up").
- **Actionable Takeaway**: Session resume should support both code-execution context (shell commands, test runs) and analytical context (research notes, decision documents). Use a single mode-detection table in the manifest, not separate tooling for each mode.

### 5. DevOps Handoff Risk: Accountability Doesn't Transfer With Ownership
**File**: /Users/adamf/Work/Strategy/docs/solutions/process/devops-handoff-risk-pattern.md
- **Category**: process
- **Relevance**: If session resume will be handed off to another team (DevOps, platform, tooling team) or integrated into shared infrastructure, this pattern shows accountability risk.
- **Key Insight**: Operational ownership transfers but accountability stays with the product owner. Mitigate by: (1) writing deployment specs, not requests; (2) defining acceptance criteria before hand-off; (3) keeping a fallback implementation you fully control; (4) instrumenting from day one.
- **Actionable Takeaway**: If claudeMd or session-resume becomes infrastructure-dependent (tmux sessions on shared servers, hook execution in CI/CD, state stored in shared services), maintain an internal fallback (e.g., sqlite-backed state in .claude directory) that doesn't depend on external teams. Document acceptance criteria (session state persists correctly, hooks fire when expected, resume works after network interruption).

## Additional Context from Solutions

### Workflow-Design Category Observations
The workflow-design solutions all address **multi-phase AI-assisted work** with emphasis on:
1. **Traceability** — Always know where decisions came from
2. **Explicit gates** — No silent transitions between phases
3. **Model diversity** — Different models catch different things
4. **Dual-mode support** — Same tool structure, context-specific adaptations
5. **Fork management** — How to evolve tools without losing local improvements

These patterns apply directly to session resume because it's fundamentally about resuming multi-phase work (session suspend → context extraction → resume → continue).

## Recommendations

1. **Document session state as origin-traceable artifacts** — Session manifest should include `origin:` field pointing to the plan/work that the session is resuming. When you suspend, capture which phase you're in.

2. **Implement a phase-boundary gate at resume time** — When resuming, explicitly ask the user: "These deferred items were pending... still valid?" Don't silently resume with incomplete context.

3. **Support both shell-execution and analytical modes** — Session resume will handle both code work (running commands) and strategy work (resuming research, meeting notes, document drafting). Use the dual-column mode-detection table pattern, not separate tools.

4. **Integrate with PAL for session context conflicts** — If resume detects conflicting interpretations of interrupted work (e.g., "should I continue with approach A or switch to B?"), use PAL `consensus` rather than defaulting to first response.

5. **Plan for infrastructure hand-off risks** — If tmux/shell integration becomes infrastructure-dependent, maintain a fallback state mechanism (local sqlite/JSON in .claude/sessions/) that doesn't require external team approval.

6. **Track fork divergence with beads** — If claude-session-resume takes ideas from other session management tools or upstream patterns, document the deltas and track adaptations in a beads issue. Discuss each delta before implementing, don't batch-port.

---

**Files sourced from**: /Users/adamf/Work/Strategy/docs/solutions/workflow-design/ and /Users/adamf/Work/Strategy/docs/solutions/process/
