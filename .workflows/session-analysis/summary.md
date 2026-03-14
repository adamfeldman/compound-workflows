# Session Analysis Summary

Generated from 98 sessions, 152 phase observations, 867 agent observations, 190 segment observations.

## 1. Session Health Metrics

| Metric | N | Min | Median | Mean | Max | P90 |
|--------|---|-----|--------|------|-----|-----|
| Session wall-clock (min) | 39 | 0.15 | 46.36 | 1114.47 | 21362.84 | 2131.68 |
| Session active time (min) | 39 | 0.15 | 21.74 | 159.65 | 2149.02 | 508.41 |
| Session idle time (min) | 21 | 7.47 | 185.18 | 1773.24 | 20366.82 | 3607.6 |
| JSONL entries per session | 98 | 1 | 8.0 | 858.76 | 26785 | 1651 |
| User messages per session | 38 | 1 | 17.0 | 114.58 | 1452 | 344 |
| Corrections per session | 98 | 0 | 0.0 | 12.69 | 471 | 22 |
| Git commits per session | 98 | 0 | 0.0 | 3.63 | 127 | 8 |

**Compaction rate:** 13/98 sessions (13.3%)

**Sessions using workflow skills:** 25/98 (25.5%)

## 2. Phase Timing Statistics

Wall-clock = skill invocation to next skill invocation (or end of session). Active = wall-clock minus idle gaps (>= 5 min). Idle threshold: 300s (99.6% of inter-entry gaps fall below this).

| Phase | N | Wall-clock Median | Active Median | Active Mean | Active P90 | Idle Median |
|-------|---|-------------------|---------------|-------------|------------|-------------|
| compact-prep | 66 | 5.14 | 4.94 | 9.26 | 15.31 | 0.0 |
| plan | 23 | 30.72 | 22.93 | 25.54 | 45.69 | 0.0 |
| work | 23 | 102.5 | 54.28 | 59.25 | 91.36 | 29.48 |
| brainstorm | 17 | 88.77 | 42.78 | 59.08 | 137.68 | 15.04 |
| compound | 10 | 13.74 | 9.59 | 16.42 | 56.28 | 0.0 |
| deepen-plan | 7 | 49.48 | 48.89 | 44.67 | - | 5.38 |
| qa | 2 | 20.46 | 13.06 | 13.06 | - | 7.4 |
| gemini-imagegen | 1 | 116.85 | 77.31 | 77.31 | - | 39.54 |
| classify-stats | 1 | 24.01 | 12.98 | 12.98 | - | 11.04 |
| version | 1 | 0.41 | 0.41 | 0.41 | - | 0.0 |

**Phase invocation counts:**

- compact-prep: 66
- plan: 23
- work: 23
- brainstorm: 18
- compound: 10
- deepen-plan: 7
- qa: 2
- gemini-imagegen: 1
- classify-stats: 1
- version: 1

## 2a. Active vs Wall-Clock Comparison

How much idle time inflates each phase. Active ratio = active median / wall-clock median.

| Phase | N | Wall-clock Median | Active Median | Idle Median | Active Ratio |
|-------|---|-------------------|---------------|-------------|--------------|
| compact-prep | 66 | 5.14 | 4.94 | 0.0 | 96.1% |
| plan | 23 | 30.72 | 22.93 | 0.0 | 74.6% |
| work | 23 | 102.5 | 54.28 | 29.48 | 53.0% |
| brainstorm | 17 | 88.77 | 42.78 | 15.04 | 48.2% |
| compound | 10 | 13.74 | 9.59 | 0.0 | 69.8% |
| deepen-plan | 7 | 49.48 | 48.89 | 5.38 | 98.8% |
| qa | 2 | 20.46 | 13.06 | 7.4 | 63.8% |
| gemini-imagegen | 1 | 116.85 | 77.31 | 39.54 | 66.2% |
| classify-stats | 1 | 24.01 | 12.98 | 11.04 | 54.1% |
| version | 1 | 0.41 | 0.41 | 0.0 | 100.0% |

## 3. Agent/Task Duration Statistics

### By subagent_type (usage-reported duration, seconds)

| Subagent Type | N | Min (s) | Median | Mean | Max | P90 |
|---------------|---|---------|--------|------|-----|-----|
| unknown | 102 | 5.1 | 108.57 | 235.96 | 2469.79 | 492.52 |
| general-purpose | 45 | 1.59 | 100.85 | 200.22 | 1376.04 | 403.82 |
| Explore | 20 | 13.4 | 57.29 | 61.63 | 148.89 | 145.27 |
| compound-workflows:workflow:plan-readiness-reviewer | 19 | 34.7 | 67.06 | 175.28 | 1681.72 | 473.9 |
| claude-code-guide | 11 | 9.37 | 22.42 | 24.04 | 58.38 | 39.11 |
| compound-workflows:workflow:plan-consolidator | 10 | 62.13 | 125.58 | 280.87 | 1523.38 | 1523.38 |
| compound-workflows:workflow:red-team-relay | 3 | 93.59 | 246.78 | 207.45 | 281.98 | - |
| compound-workflows:workflow:plan-checks:semantic-checks | 3 | 166.21 | 319.32 | 363.89 | 606.15 | - |
| compound-workflows:research:repo-research-analyst | 2 | 8.12 | 64.46 | 64.46 | 120.79 | - |
| compound-workflows:workflow:spec-flow-analyzer | 2 | 199.4 | 311.92 | 311.92 | 424.43 | - |
| statusline-setup | 1 | 20.98 | 20.98 | 20.98 | 20.98 | - |
| compound-workflows:research:context-researcher | 1 | 4.95 | 4.95 | 4.95 | 4.95 | - |

### By subagent_type (wall-clock duration, seconds)

| Subagent Type | N | Min (s) | Median | Mean | Max | P90 |
|---------------|---|---------|--------|------|-----|-----|
| unknown | 323 | 0.0 | 0.04 | 79.09 | 2469.79 | 230.25 |
| general-purpose | 143 | 0.0 | 0.03 | 67.1 | 1376.07 | 242.64 |
| compound-workflows:research:repo-research-analyst | 65 | 0.0 | 0.01 | 3.21 | 120.84 | 0.06 |
| compound-workflows:workflow:red-team-relay | 63 | 0.0 | 0.03 | 9.91 | 282.01 | 0.08 |
| compound-workflows:workflow:plan-checks:semantic-checks | 41 | 0.0 | 0.05 | 27.81 | 606.15 | 6.93 |
| compound-workflows:research:learnings-researcher | 31 | 0.0 | 0.01 | 0.04 | 0.63 | 0.04 |
| Explore | 27 | 0.0 | 38.01 | 46.13 | 148.93 | 96.09 |
| compound-workflows:workflow:spec-flow-analyzer | 27 | 0.0 | 0.01 | 23.13 | 424.46 | 0.09 |
| compound-workflows:research:context-researcher | 27 | 0.0 | 0.0 | 0.2 | 4.95 | 0.04 |
| compound-workflows:workflow:plan-readiness-reviewer | 19 | 34.73 | 67.1 | 175.31 | 1681.75 | 473.9 |
| compound-workflows:review:code-simplicity-reviewer | 13 | 0.0 | 0.0 | 0.02 | 0.08 | 0.04 |
| context-researcher | 11 | 0.0 | 0.0 | 6.54 | 71.77 | 0.05 |
| claude-code-guide | 11 | 9.41 | 22.42 | 24.05 | 58.39 | 39.11 |
| compound-workflows:workflow:plan-consolidator | 10 | 62.17 | 125.64 | 280.9 | 1523.38 | 1523.38 |
| compound-workflows:review:architecture-strategist | 10 | 0.0 | 0.0 | 0.02 | 0.09 | 0.09 |
| compound-workflows:review:security-sentinel | 8 | 0.0 | 0.0 | 0.02 | 0.05 | - |
| compound-workflows:review:pattern-recognition-specialist | 7 | 0.0 | 0.0 | 0.01 | 0.04 | - |
| compound-workflows:review:agent-native-reviewer | 4 | 0.0 | 0.02 | 0.02 | 0.04 | - |
| compound-workflows:review:performance-oracle | 4 | 0.0 | 0.03 | 0.04 | 0.1 | - |
| compound-workflows:research:git-history-analyzer | 3 | 0.0 | 0.03 | 0.02 | 0.04 | - |
| compound-workflows:review:deployment-verification-agent | 3 | 0.04 | 0.05 | 0.04 | 0.05 | - |
| compound-workflows:research:best-practices-researcher | 3 | 0.0 | 0.0 | 0.01 | 0.03 | - |
| compound-workflows:research:framework-docs-researcher | 2 | 0.0 | 0.02 | 0.02 | 0.03 | - |
| statusline-setup | 1 | 21.02 | 21.02 | 21.02 | 21.02 | - |
| compound-workflows:review:typescript-reviewer | 1 | 0.04 | 0.04 | 0.04 | 0.04 | - |
| compound-workflows:review:python-reviewer | 1 | 0.03 | 0.03 | 0.03 | 0.03 | - |
| compound-workflows:review:frontend-races-reviewer | 1 | 0.03 | 0.03 | 0.03 | 0.03 | - |
| compound-workflows:review:data-integrity-guardian | 1 | 0.03 | 0.03 | 0.03 | 0.03 | - |
| compound-workflows:review:data-migration-expert | 1 | 0.07 | 0.07 | 0.07 | 0.07 | - |
| compound-workflows:review:schema-drift-detector | 1 | 0.03 | 0.03 | 0.03 | 0.03 | - |
| compound-workflows:workflow:model-test | 1 | 0.04 | 0.04 | 0.04 | 0.04 | - |
| compound-workflows:review:plan-readiness-reviewer | 1 | 0.08 | 0.08 | 0.08 | 0.08 | - |
| compound-workflows:research:test-sonnet-model | 1 | 0.02 | 0.02 | 0.02 | 0.02 | - |

### Token usage by subagent_type

| Subagent Type | N | Min | Median | Mean | Max | P90 |
|---------------|---|-----|--------|------|-----|-----|
| unknown | 102 | 12421 | 40337.5 | 45034.65 | 125070 | 71892 |
| general-purpose | 45 | 11097 | 37040 | 46269.67 | 132671 | 89874 |
| Explore | 20 | 36896 | 68762.5 | 66497.75 | 112887 | 91597 |
| compound-workflows:workflow:plan-readiness-reviewer | 19 | 22860 | 30441 | 29740.37 | 34132 | 33317 |
| claude-code-guide | 11 | 21017 | 36094 | 36032.09 | 51229 | 47210 |
| compound-workflows:workflow:plan-consolidator | 10 | 26873 | 36071.0 | 35283.4 | 45585 | 45585 |
| compound-workflows:workflow:red-team-relay | 3 | 22513 | 23573 | 23500.33 | 24415 | - |
| compound-workflows:workflow:plan-checks:semantic-checks | 3 | 44779 | 45231 | 49933.67 | 59791 | - |
| compound-workflows:research:repo-research-analyst | 2 | 15104 | 40456.5 | 40456.5 | 65809 | - |
| compound-workflows:workflow:spec-flow-analyzer | 2 | 65377 | 76369.0 | 76369 | 87361 | - |
| statusline-setup | 1 | 19865 | 19865 | 19865 | 19865 | - |
| compound-workflows:research:context-researcher | 1 | 34845 | 34845 | 34845 | 34845 | - |

## 4. Tool Call Distribution

**Total tool calls across all sessions:** 14345

| Tool | Count | % of Total |
|------|-------|------------|
| Bash | 6762 | 47.1% |
| Edit | 2223 | 15.5% |
| Read | 2211 | 15.4% |
| AskUserQuestion | 896 | 6.2% |
| Agent | 837 | 5.8% |
| Grep | 460 | 3.2% |
| Write | 366 | 2.6% |
| ToolSearch | 174 | 1.2% |
| Skill | 152 | 1.1% |
| Glob | 149 | 1.0% |
| Task | 31 | 0.2% |
| WebSearch | 28 | 0.2% |
| mcp__pal__clink | 16 | 0.1% |
| WebFetch | 12 | 0.1% |
| TaskOutput | 7 | 0.0% |
| mcp__pal__chat | 5 | 0.0% |
| TaskCreate | 5 | 0.0% |
| TaskUpdate | 5 | 0.0% |
| mcp__pal__listmodels | 2 | 0.0% |
| EnterWorktree | 2 | 0.0% |
| ExitWorktree | 2 | 0.0% |

### Tool calls per phase

| Phase | Agent | AskUserQuestion | Bash | Edit | EnterWorktree | Glob | Grep | Read | Skill | Task | TaskCreate | TaskOutput | TaskUpdate | ToolSearch | WebFetch | WebSearch | Write | mcp__pal__clink | mcp__pal__listmodels | Total |
|-------|------|------|------|------|------|------|------|------|------|------|------|------|------|------|------|------|------|------|------|-------|
| work | 222 | 116 | 1893 | 449 | 0 | 23 | 108 | 409 | 43 | 0 | 0 | 3 | 0 | 29 | 1 | 5 | 69 | 2 | 0 | 3372 |
| brainstorm | 131 | 259 | 716 | 300 | 0 | 25 | 46 | 293 | 36 | 0 | 5 | 0 | 5 | 27 | 1 | 10 | 47 | 2 | 1 | 1904 |
| plan | 110 | 89 | 755 | 298 | 0 | 18 | 36 | 322 | 45 | 4 | 0 | 0 | 0 | 15 | 0 | 0 | 36 | 0 | 0 | 1728 |
| compact-prep | 25 | 71 | 883 | 210 | 1 | 19 | 44 | 218 | 78 | 0 | 0 | 0 | 0 | 28 | 2 | 1 | 41 | 0 | 0 | 1621 |
| deepen-plan | 84 | 76 | 301 | 110 | 0 | 3 | 19 | 69 | 13 | 0 | 0 | 0 | 0 | 8 | 0 | 0 | 14 | 2 | 0 | 699 |
| compound | 62 | 6 | 174 | 27 | 0 | 0 | 12 | 74 | 20 | 0 | 0 | 0 | 0 | 2 | 0 | 0 | 15 | 0 | 0 | 392 |
| gemini-imagegen | 5 | 0 | 66 | 46 | 0 | 1 | 5 | 36 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 8 | 0 | 0 | 169 |
| qa | 6 | 0 | 33 | 1 | 0 | 2 | 4 | 7 | 3 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 57 |
| classify-stats | 3 | 0 | 4 | 0 | 0 | 0 | 1 | 1 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 11 |
| version | 0 | 0 | 2 | 0 | 0 | 0 | 0 | 0 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 |

## 5. Most Common Agent Descriptions

| Description | Count |
|-------------|-------|
| Red team via Claude Opus | 17 |
| Red team via Gemini | 9 |
| Red team via OpenAI | 9 |
| Semantic checks on plan | 8 |
| MINOR triage categorization | 8 |
| Plan readiness reviewer | 7 |
| Semantic readiness checks | 6 |
| Red team — Claude Opus | 6 |
| Categorize MINOR red team findings | 6 |
| Red team: Gemini via clink | 5 |
| Red team: OpenAI via clink | 5 |
| Red team via Gemini CLI | 5 |
| Semantic plan readiness checks | 5 |
| Triage MINOR red team findings | 4 |
| Red team: Claude Opus | 4 |
| Red team — Gemini via clink | 4 |
| Red team — OpenAI via clink | 4 |
| Tier 2: context-lean reviewer | 4 |
| Plan readiness review aggregation | 3 |
| Compound: context analyzer | 3 |
| Compound: solution extractor | 3 |
| Compound: related docs finder | 3 |
| Compound: category classifier | 3 |
| Resume QA: pattern recognition | 3 |
| Resume QA: code simplicity | 3 |

## 6. Phase Sequence Patterns

Most common phase sequences observed within sessions (consecutive skill invocations).

### Consecutive phase transitions

| Transition | Count |
|------------|-------|
| compact-prep -> compact-prep | 20 |
| compact-prep -> work | 11 |
| plan -> compact-prep | 11 |
| work -> compact-prep | 9 |
| brainstorm -> compact-prep | 7 |
| compact-prep -> plan | 6 |
| plan -> work | 6 |
| brainstorm -> brainstorm | 4 |
| compact-prep -> deepen-plan | 4 |
| compact-prep -> brainstorm | 4 |
| brainstorm -> plan | 4 |
| compact-prep -> compound | 3 |
| deepen-plan -> compact-prep | 3 |
| compound -> compact-prep | 3 |
| plan -> plan | 3 |
| compound -> plan | 3 |
| work -> brainstorm | 3 |
| compound -> compound | 2 |
| deepen-plan -> work | 2 |
| plan -> deepen-plan | 2 |

### Full session phase sequences (top 15)

| Sequence | Count |
|----------|-------|
| compact-prep -> compact-prep | 2 |
| compact-prep -> work -> compact-prep | 1 |
| brainstorm -> brainstorm -> compact-prep -> compact-prep -> compound -> compound -> deepen-plan -> compact-prep -> deepen-plan | 1 |
| compound -> compound -> compact-prep | 1 |
| compact-prep -> plan -> work -> compact-prep -> brainstorm -> brainstorm -> plan -> work -> compact-prep -> compact-prep -> brainstorm -> compact-prep -> compact-prep | 1 |
| brainstorm -> compact-prep -> plan -> plan -> compact-prep | 1 |
| brainstorm -> compound -> plan -> compact-prep -> deepen-plan -> compact-prep -> compact-prep -> work -> compact-prep -> work | 1 |
| compound -> plan -> compact-prep -> deepen-plan -> work -> compact-prep -> gemini-imagegen -> brainstorm -> plan -> work -> compact-prep -> work -> brainstorm | 1 |
| compound -> compact-prep | 1 |
| compact-prep -> compact-prep -> compact-prep -> compound -> compact-prep -> work -> classify-stats -> compact-prep -> compact-prep -> compact-prep | 1 |
| plan -> deepen-plan -> work -> work -> plan -> work -> qa -> brainstorm -> plan -> work -> compact-prep -> plan -> deepen-plan -> compact-prep -> work -> compound -> brainstorm -> plan -> compact-prep -> deepen-plan -> plan -> compact-prep -> compact-prep -> work -> version -> brainstorm -> compact-prep -> plan -> compact-prep -> work -> compact-prep -> plan -> plan -> compact-prep -> work -> brainstorm -> compact-prep -> plan -> compact-prep -> compact-prep -> compact-prep -> brainstorm -> compact-prep -> compound -> plan -> compact-prep -> compact-prep -> work -> brainstorm -> brainstorm -> brainstorm | 1 |
| plan -> compact-prep | 1 |
| plan -> work -> compact-prep -> compact-prep -> compact-prep -> compact-prep | 1 |
| compact-prep -> brainstorm -> compact-prep | 1 |
| work -> work -> plan -> plan -> compact-prep -> compact-prep -> compact-prep -> compact-prep | 1 |

## 7. Session Duration Distribution

| Duration Bucket | Sessions | % |
|----------------|----------|---|
| 0-5 min | 11 | 28.2% ############## |
| 5-15 min | 6 | 15.4% ####### |
| 15-30 min | 0 | 0.0%  |
| 30-60 min | 4 | 10.3% ##### |
| 1-2 hours | 1 | 2.6% # |
| 2-4 hours | 5 | 12.8% ###### |
| 4-8 hours | 4 | 10.3% ##### |
| 8+ hours | 8 | 20.5% ########## |

## 8. Raw Data Reference

- **Raw observations file:** `raw-observations.jsonl`
- **Total sessions:** 98
- **Total phase observations:** 152
- **Total agent observations:** 867
- **Total segment observations:** 190
- **Near-empty sessions (<=2 entries):** 30
- **Idle threshold:** 300s (5 minutes)

## 9. Non-Workflow Activity Categories

Every session segment classified by dominant activity. Categories: coding (Edit+Write >= 30%), light-coding (Edit+Write >= 15%, subcats: orch-coding, interactive-dev, iterating, plain), exploration (Read+Grep+Glob >= 25%, merged from old research+exploration), configuration (config file patterns >= 30%), bead-management (bd cmds >= 30%), discussion (user msgs >= tools or > 2x tools), mixed (subcats: orchestration, interactive, agent-heavy, transition, still-mixed).

| Category | N Segments | Active Median | Active Mean | Active P90 | Wall-clock Median |
|----------|------------|---------------|-------------|------------|-------------------|
| mixed | 68 | 12.07 | 25.12 | 73.01 | 15.23 |
| light-coding | 56 | 35.16 | 48.01 | 102.56 | 47.63 |
| exploration | 18 | 12.28 | 15.05 | 35.69 | 20.77 |
| coding | 18 | 35.0 | 54.89 | 77.31 | 47.29 |
| bead-management | 17 | 21.68 | 28.72 | 80.19 | 69.47 |
| discussion | 8 | 0.53 | 1.16 | - | 0.53 |
| configuration | 5 | 6.0 | 14.6 | - | 6.0 |

### Subcategory Timing Breakdown

Median, P90, and total active time for light-coding and mixed subcategories.

| Subcategory | N | Active Median | Active P90 | Total Active Min |
|-------------|---|---------------|------------|------------------|
| light-coding:orch-coding | 50 | 40.34 | 135.67 | 2560.3 |
| mixed:still-mixed | 45 | 27.99 | 73.01 | 1477.7 |
| mixed:interactive | 9 | 12.69 | - | 224.7 |
| light-coding:iterating | 1 | 73.84 | - | 73.8 |
| light-coding:plain | 1 | 31.21 | - | 31.2 |
| light-coding:interactive-dev | 4 | 5.87 | - | 23.0 |
| mixed:transition | 14 | 0.12 | 1.11 | 6.0 |

**Segment type breakdown:**

- workflow-phase: 151
- pre-workflow: 25
- full-session: 14

### Bead-Management Sub-Categories

BD subcommand distribution within bead-management segments. Creation = bd create. Triage = bd show/ready/list/search/blocked/sql. Updating = bd update/close/label.

| BD Sub-Category | Command Count | Attributed Active Min |
|-----------------|---------------|----------------------|
| triage | 155 | 199.3 |
| updating | 137 | 181.9 |
| creation | 56 | 75.3 |
| other | 26 | 31.8 |

**Raw bd subcommand counts:**

- `bd update`: 100
- `bd show`: 67
- `bd create`: 56
- `bd search`: 40
- `bd close`: 31
- `bd sql`: 22
- `bd list`: 21
- `bd dep`: 12
- `bd worktree`: 9
- `bd label`: 6
- `bd version`: 4
- `bd ready`: 4
- `bd blocked`: 1
- `bd help`: 1

## 10. Concurrent Session Detection

Sessions with overlapping [first_timestamp, last_timestamp] ranges. Concurrent sessions may double-count wall-clock time in aggregations.

**Overlapping session pairs:** 110
**Unique sessions involved:** 38
**Total overlapping time:** 34977.0 min (582.9 hrs)

### Top 10 overlaps by duration

| Session A | Session B | Overlap Min |
|-----------|-----------|-------------|
| 3b01ea81-37f... | 59b5ae34-2de... | 5806.69 |
| 3b01ea81-37f... | 77508108-376... | 5756.62 |
| 59b5ae34-2de... | 77508108-376... | 5756.62 |
| 3b01ea81-37f... | 8b90255a-206... | 2131.68 |
| 59b5ae34-2de... | 8b90255a-206... | 2131.68 |
| 8b90255a-206... | 77508108-376... | 2114.68 |
| 59b5ae34-2de... | 551deff1-065... | 1471.77 |
| 3b01ea81-37f... | 551deff1-065... | 1470.15 |
| 77508108-376... | 551deff1-065... | 1469.24 |
| 7629c6aa-170... | 2232c062-22e... | 1445.32 |

## 11. Per-Bead Time Attribution (Windowed vs Session-Level)

**Session-level (old):** Full session time attributed to each bead mentioned. Overcounts 30-500x for multi-bead sessions.

**Windowed (new):** Time window = 2 min before first bead reference to 2 min after last reference. Falls back to proportional splitting (session time / N beads) when only indirect references exist.

### Top 20 beads by windowed active time

| Bead ID | Sessions | Windowed Min | Old Session Min | Reduction | Methods | Ref Types |
|---------|----------|-------------|-----------------|-----------|---------|-----------|
| h0g | 5 | 2718.4 | 4312.8 | 37.0% | windowed(5) | bd_cmd(5), commit_ref(4), user_msg(3) |
| ybm | 4 | 1835.4 | 4209.1 | 56.4% | windowed(3), proportional(1) | commit_ref(4), bd_cmd(3), user_msg(1) |
| aig | 4 | 1576.8 | 4209.1 | 62.5% | windowed(4) | bd_cmd(4), commit_ref(3), user_msg(3) |
| 884 | 3 | 1496.1 | 3649.2 | 59.0% | windowed(3) | bd_cmd(3), commit_ref(2), user_msg(1) |
| xu2 | 3 | 1438.2 | 3649.2 | 60.6% | windowed(3) | bd_cmd(3), commit_ref(1), user_msg(1) |
| 22l | 2 | 1399.5 | 2708.9 | 48.3% | windowed(2) | bd_cmd(2), user_msg(2), commit_ref(1) |
| czu | 3 | 1207.6 | 3649.2 | 66.9% | windowed(3) | bd_cmd(3), commit_ref(2), user_msg(2) |
| 3zr | 4 | 1179.3 | 4002.2 | 70.5% | windowed(4) | user_msg(3), bd_cmd(3), commit_ref(2) |
| srf | 1 | 1084.3 | 2149.0 | 49.5% | windowed(1) | bd_cmd(1) |
| a6t | 4 | 955.4 | 3747.1 | 74.5% | windowed(4) | bd_cmd(4), commit_ref(2), user_msg(1) |
| 5b6 | 3 | 920.2 | 3653.4 | 74.8% | windowed(3) | bd_cmd(3), user_msg(2) |
| wgl | 1 | 866.3 | 2149.0 | 59.7% | windowed(1) | bd_cmd(1), commit_ref(1), user_msg(1) |
| voo | 2 | 842.3 | 3145.0 | 73.2% | windowed(2) | bd_cmd(2), user_msg(1) |
| 3k3 | 3 | 665.7 | 3157.9 | 78.9% | windowed(3) | bd_cmd(3), user_msg(2) |
| ou4 | 2 | 594.1 | 3145.0 | 81.1% | windowed(2) | bd_cmd(2) |
| 8vk | 3 | 582.6 | 3649.2 | 84.0% | windowed(2), proportional(1) | bd_cmd(2), commit_ref(1) |
| 4v2 | 4 | 559.6 | 3747.1 | 85.1% | windowed(4) | bd_cmd(4), commit_ref(2), user_msg(1) |
| rhl | 3 | 519.4 | 3649.2 | 85.8% | windowed(2), proportional(1) | bd_cmd(2), commit_ref(1), user_msg(1) |
| eec | 6 | 510.1 | 4215.7 | 87.9% | windowed(6) | bd_cmd(6), user_msg(1) |
| 42s | 3 | 462.2 | 3649.2 | 87.3% | windowed(3) | bd_cmd(3), user_msg(2), commit_ref(2) |

**Total beads with attribution:** 301
**Beads spanning multiple sessions:** 91
**Total old session-level attributed time:** 440156.6 min
**Total windowed attributed time:** 37839.7 min
**Overall reduction:** 91.4%
**Beads using windowed method:** 301
**Beads using proportional-only method:** 0

### Old session-level top 10 (for comparison)

| Bead ID | Sessions | Old Active Min | Old Wall Min | Phases |
|---------|----------|----------------|--------------|--------|
| h0g | 5 | 4312.8 | 34707.7 | compact-prep(5), work(4), plan(4), brainstorm(4), compound(3) |
| eec | 6 | 4215.7 | 30429.9 | compact-prep(6), work(4), plan(3), brainstorm(3), compound(3) |
| ybm | 4 | 4209.1 | 34556.1 | compact-prep(4), work(4), plan(3), brainstorm(3), compound(3) |
| aig | 4 | 4209.1 | 34556.1 | compact-prep(4), work(4), plan(3), brainstorm(3), compound(3) |
| wtn | 4 | 4157.6 | 30220.0 | compact-prep(4), work(4), plan(3), brainstorm(3), compound(3) |
| 3zr | 4 | 4002.2 | 30193.1 | compact-prep(4), compound(3), brainstorm(3), work(3), deepen-plan(2) |
| 4v2 | 4 | 3747.1 | 28922.0 | compact-prep(4), work(4), plan(2), brainstorm(2), compound(2) |
| a6t | 4 | 3747.1 | 28922.0 | compact-prep(4), work(4), plan(2), brainstorm(2), compound(2) |
| 0ob | 3 | 3704.9 | 32927.8 | compact-prep(3), work(3), plan(3), brainstorm(3), deepen-plan(2) |
| jed | 4 | 3694.4 | 28944.8 | compact-prep(4), work(3), plan(2), brainstorm(2), compound(2) |

## 12. Token-per-Phase Aggregation

Agent/Task token usage grouped by the workflow phase they executed within. Determined by matching agent dispatch timestamps to phase time ranges.

| Phase | Agents | Total Tokens | % of Tokens | Total Duration (s) | Tokens/Agent |
|-------|--------|-------------|-------------|--------------------|--------------| 
| work | 79 | 3,476,639 | 35.4% | 18804.5 | 44,008 |
| non-workflow | 48 | 2,305,412 | 23.5% | 7182.7 | 48,029 |
| compact-prep | 38 | 1,593,754 | 16.2% | 6914.0 | 41,941 |
| brainstorm | 21 | 809,466 | 8.2% | 3621.3 | 38,546 |
| plan | 18 | 630,761 | 6.4% | 3694.3 | 35,042 |
| deepen-plan | 8 | 588,545 | 6.0% | 1974.4 | 73,568 |
| compound | 3 | 232,146 | 2.4% | 715.8 | 77,382 |
| gemini-imagegen | 3 | 139,309 | 1.4% | 56.7 | 46,436 |
| classify-stats | 1 | 52,509 | 0.5% | 243.2 | 52,509 |

**Total agent tokens across all phases:** 9,828,541

## 13. Estimate vs Actual (Windowed Attribution)

Comparing `estimated_minutes` from the beads database with windowed `total_active_minutes` (not session-level). Ratio = actual / estimated (>1 means took longer than estimated).

| Bead ID | Title | Est | Windowed Actual | Old Session Actual | W-Ratio | O-Ratio |
|---------|-------|-----|-----------------|--------------------|---------|---------| 
| 5b6 | Audit plugin for cheaper-model dispatch ... | 45 | 920.2 | 3653.4 | 20.45 | 81.19 |
| 3zr | Mine session logs for empirical workflow... | 100 | 1179.3 | 4002.2 | 11.79 | 40.02 |
| p14 | capture-stats.sh: handle Agent tool usag... | 30 | 351.8 | 3145.0 | 11.73 | 104.83 |
| jg6 | Fix capture-stats.sh usage format parser... | 20 | 179.0 | 1504.4 | 8.95 | 75.22 |
| ywug | compact-prep heredoc permission prompt f... | 5 | 40.3 | 2657.4 | 8.06 | 531.49 |
| zwjg | capture-stats.sh: read usage line from s... | 20 | 118.3 | 302.0 | 5.91 | 15.1 |
| voo | Per-agent token instrumentation | 150 | 842.3 | 3145.0 | 5.62 | 20.97 |
| jak | Audit plugin commands for heuristic-trig... | 90 | 415.7 | 3157.9 | 4.62 | 35.09 |
| ka3w | Auto-prompt memory/compound capture befo... | 30 | 133.9 | 313.8 | 4.46 | 10.46 |
| xzn | Config toggles for optional compact-prep... | 60 | 257.8 | 3250.3 | 4.3 | 54.17 |
| nn3 | Evaluate red team step in /compound:plan | 90 | 383.9 | 3145.0 | 4.27 | 34.94 |
| 4qc9 | [bug] capture-stats.sh conflates missing... | 30 | 121.7 | 172.4 | 4.06 | 5.75 |
| ry5o | do:work skill should remind orchestrator... | 15 | 57.9 | 137.0 | 3.86 | 9.13 |
| 3k3 | Setup: ship .workflows permissions in se... | 180 | 665.7 | 3157.9 | 3.7 | 17.54 |
| 8one | Fix usage-pipe race + work-in-progress s... | 60 | 221.9 | 748.4 | 3.7 | 12.47 |
| dj65 | Replace heredoc/echo/unspecified commit ... | 45 | 162.9 | 282.4 | 3.62 | 6.28 |
| pj6k | Fix unslugged .workflows/ paths across 4... | 30 | 87.5 | 2149.0 | 2.92 | 71.63 |
| 3l7 | Heuristic audit scope expansion — skills... | 120 | 331.1 | 3666.3 | 2.76 | 30.55 |
| j6ui | Stats capture fails in worktrees — STATS... | 10 | 23.6 | 180.9 | 2.36 | 18.09 |
| icn | Plan skill: MINOR triage gate before has... | 15 | 33.5 | 3145.0 | 2.23 | 209.67 |
| 8sd | Try out classify-stats skill on collecte... | 30 | 52.6 | 2149.0 | 1.75 | 71.63 |
| dndn | Prompt instructions for permissionless b... | 60 | 96.7 | 3653.4 | 1.61 | 60.89 |
| 71sr | Update stats-capture-schema.md for stdin... | 5 | 7.9 | 48.2 | 1.58 | 9.63 |
| 5kxt | Version bump to 3.0.3 and changelog | 10 | 13.3 | 56.6 | 1.33 | 5.66 |
| ml1 | Step 4: Update CLAUDE.md agent registry | 5 | 6.5 | 2149.0 | 1.3 | 429.8 |
| kte5 | P5-S7: Permission prompt cost estimation | 8 | 10.2 | 504.2 | 1.28 | 63.02 |
| sg5b | Update file counts 7→8 in CLAUDE.md, AGE... | 10 | 11.8 | 56.6 | 1.18 | 5.66 |
| xnep | Remove .tmp→mv atomic write pattern from... | 60 | 69.5 | 702.0 | 1.16 | 11.7 |
| i2tn | Step 5: Verify zero findings + version b... | 20 | 20.5 | 508.4 | 1.03 | 25.42 |
| pdue | Run QA: no-shell-atomicity.sh + full plu... | 15 | 15.4 | 56.6 | 1.03 | 3.77 |
| ort2 | P5-S1: Per-request cost from JSONL | 15 | 14.9 | 504.2 | 0.99 | 33.61 |
| u1fd | Expand permissive profile with 11 missin... | 30 | 28.4 | 282.4 | 0.95 | 9.41 |
| 0nvy | P5-S4: Estimation accuracy segmentation | 12 | 11.2 | 504.2 | 0.93 | 42.02 |
| 9lw6 | P5-S6: Velocity trend | 10 | 9.1 | 504.2 | 0.91 | 50.42 |
| bw9v | Defer compact-prep run directory creatio... | 10 | 9.1 | 126.5 | 0.91 | 12.65 |
| w2hf | Update 5 skill files for stdin capture-s... | 15 | 13.6 | 48.2 | 0.91 | 3.21 |
| ojry | P5-S5: Compaction cost measurement | 12 | 10.5 | 504.2 | 0.88 | 42.02 |
| yai0 | P5-S9: Tighten estimation heuristics | 15 | 13.1 | 504.2 | 0.88 | 33.61 |
| n3s5 | P5-S3: Per-workflow confirmation prompt ... | 12 | 9.8 | 504.2 | 0.82 | 42.02 |
| yeqy | Step 5: Update plugin infrastructure | 20 | 16.3 | 145.5 | 0.82 | 7.27 |
| vm7m | P5-S8: QA retry cost | 10 | 7.9 | 504.2 | 0.79 | 50.42 |
| df8x | P5-S2: Stats YAML mining | 15 | 11.1 | 504.2 | 0.74 | 33.61 |
| rdij | fix: compact-prep perf — direct memory w... | 20 | 14.0 | 126.5 | 0.7 | 6.33 |
| a433 | Fix semantic-checks.md: remove .tmp→mv | 10 | 6.9 | 56.6 | 0.69 | 5.66 |
| qlfx | Step 4: Expand scan scope in Tier 1 QA s... | 30 | 20.2 | 145.5 | 0.67 | 4.85 |
| v99 | Step 1: Settings infrastructure (stats_c... | 15 | 9.7 | 2149.0 | 0.64 | 143.27 |
| je54 | Compact-prep commit message uses shared ... | 10 | 6.2 | 45.2 | 0.62 | 4.52 |
| gym5 | capture-stats.sh: read usage from stdin ... | 10 | 5.9 | 48.2 | 0.59 | 4.82 |
| 9c0 | Step 3: work.md instrumentation | 20 | 11.5 | 2149.0 | 0.58 | 107.45 |
| dm5g | Step 1: Create migrate-stats-keys.sh | 15 | 8.6 | 145.5 | 0.58 | 9.7 |
| 1de | Step 10: Version bump + QA | 20 | 10.9 | 2149.0 | 0.55 | 107.45 |
| 9l0o | Add no-shell-atomicity.sh QA script | 15 | 8.2 | 56.6 | 0.55 | 3.77 |
| 8zy | Write auto-approve.sh hook template | 45 | 24.4 | 2149.0 | 0.54 | 47.76 |
| a7t | Install hook + update settings.json (orc... | 10 | 5.3 | 2149.0 | 0.53 | 214.9 |
| 3ysa | 3zr-S3: Update estimation-heuristics.md ... | 20 | 10.3 | 504.2 | 0.52 | 25.21 |
| h7j | [investigate] Transient background Agent... | 30 | 15.2 | 2149.0 | 0.51 | 71.63 |
| pck2 | Fix heredoc hard heuristic — revert ywug... | 30 | 14.9 | 2149.0 | 0.5 | 71.63 |
| 88gl | Step 3: Create write-tool-discipline.sh ... | 30 | 14.8 | 145.5 | 0.49 | 4.85 |
| zvux | Remove rm:* from permissive profile in d... | 10 | 4.9 | 137.0 | 0.49 | 13.7 |
| 924 | Step 7: Version bump + CHANGELOG + QA | 15 | 7.1 | 2149.0 | 0.48 | 143.27 |
| 9vy | Step 8: compact-prep ccusage snapshot pe... | 15 | 7.3 | 2149.0 | 0.48 | 143.27 |
| e5wg | Fix classify-stats/SKILL.md: remove .tmp... | 15 | 7.3 | 56.6 | 0.48 | 3.77 |
| 3m1 | QA + adversarial testing | 30 | 13.7 | 2149.0 | 0.46 | 71.63 |
| bz96 | CLAUDE.md + init-values.sh header commen... | 10 | 4.0 | 97.8 | 0.4 | 9.78 |
| o428 | P0b: Add tool_use_id and session_id to h... | 15 | 5.7 | 504.2 | 0.38 | 33.61 |
| igp | Plugin metadata: version bump, CHANGELOG... | 15 | 5.4 | 2149.0 | 0.36 | 143.27 |
| z5lj | Setup: offer to configure Claude statusl... | 20 | 6.9 | 2149.0 | 0.35 | 107.45 |
| j3wo | Steps 3a+3b+3c: Migrate brainstorm, plan... | 30 | 10.3 | 508.4 | 0.34 | 16.95 |
| u3jn | Steps 1+2: Create init-values.sh, check-... | 45 | 13.5 | 508.4 | 0.3 | 11.3 |
| v3du | init-values.sh: add mkdir + CACHED_MODEL... | 20 | 6.0 | 97.8 | 0.3 | 4.89 |
| wg5 | Step 3: Update Phase 7 decision tree in ... | 20 | 5.8 | 2149.0 | 0.29 | 107.45 |
| bpv3 | S4: Classification-enriched dispatch ana... | 30 | 8.4 | 504.2 | 0.28 | 16.81 |
| pud5 | Skill files: remove mkdir/env caching, u... | 25 | 6.9 | 97.8 | 0.28 | 3.91 |
| 5849 | Step 2: Fix all 10 violations | 45 | 12.0 | 145.5 | 0.27 | 3.23 |
| cew | Step 6: review.md instrumentation | 15 | 4.0 | 2149.0 | 0.27 | 143.27 |
| gfl5 | S2: Hook audit log cross-reference | 60 | 15.9 | 504.2 | 0.27 | 8.4 |
| szc2 | S1: Compaction reorientation fix — activ... | 30 | 8.0 | 504.2 | 0.27 | 16.81 |
| tvc | Step 6: Update brainstorm.md — Add probl... | 15 | 4.0 | 2149.0 | 0.27 | 143.27 |
| 7uof | S3: Cache vs non-cache cost split | 45 | 11.6 | 504.2 | 0.26 | 11.2 |
| m441 | P0a: Fix MODEL_PRICING for all Claude mo... | 45 | 10.6 | 504.2 | 0.24 | 11.2 |
| vxi0 | 3zr-S1: Classification & phase boundarie... | 45 | 10.5 | 504.2 | 0.23 | 11.2 |
| vzo | Step 2: Add Phase 6.9 to plan.md — Condi... | 25 | 5.5 | 2149.0 | 0.22 | 85.96 |
| 50s | Step 5: Update deepen-plan.md — Add 7th ... | 20 | 4.0 | 2149.0 | 0.2 | 107.45 |
| 5a2 | Step 4: brainstorm.md instrumentation | 20 | 4.0 | 2149.0 | 0.2 | 107.45 |
| tiv | Step 1: Add Phase 6.8 to plan.md — Red T... | 45 | 8.2 | 2149.0 | 0.18 | 47.76 |
| 4rw | Step 7: deepen-plan.md instrumentation | 25 | 4.0 | 2149.0 | 0.16 | 85.96 |
| bdl | Step 9: classify-stats skill | 25 | 4.0 | 2149.0 | 0.16 | 85.96 |
| h056 | Steps 4a-4g: Migrate all skill files | 25 | 4.0 | 508.4 | 0.16 | 20.34 |
| kfq | Step 2: capture-stats.sh + stats-capture... | 25 | 4.0 | 2149.0 | 0.16 | 85.96 |
| c5ec | 3zr-S2: Proportional analysis, dedup, an... | 45 | 6.5 | 504.2 | 0.15 | 11.2 |
| gjvi | Setup re-asks permission profile, ignore... | 30 | 4.0 | 35.4 | 0.13 | 1.18 |
| xj9 | Step 5: plan.md instrumentation | 30 | 4.0 | 2149.0 | 0.13 | 71.63 |
| k752 | Steps 3d+3e+3f+3g: Migrate work, deepen-... | 45 | 4.0 | 508.4 | 0.09 | 11.3 |
| qnu | Update setup.md with permission configur... | 45 | 4.0 | 2149.0 | 0.09 | 47.76 |
| nrpu | Compact-prep: make cost summary step opt... | 20 | 1.6 | 1.6 | 0.08 | 0.08 |
| x15f | Consolidate mkdir and env caching into i... | 60 | 4.0 | 97.8 | 0.07 | 1.63 |
| 254 | Zero-findings QA baseline with context-l... | 0 | 4.0 | 996.0 | - | - |

**Beads with both estimate and actual:** 97
**Windowed — Mean ratio:** 1.69 | **Median ratio:** 0.58
**Old session — Mean ratio:** 54.34 | **Median ratio:** 27.98
**Windowed: Under-estimated (>1):** 30 | **Over-estimated (<1):** 66 | **Exact:** 0

## 14. Time Allocation Summary

How total active time is distributed across workflow phases and non-workflow activity categories.

**Total active time across all sessions:** 6226.2 min (103.8 hrs)
**Total wall-clock time across all sessions:** 43464.2 min (724.4 hrs)

### By Activity Category (from segments)

**Workflow phase active time:** 5159.6 min (86.0 hrs)
**Non-workflow active time:** 1066.7 min (17.8 hrs)

| Activity | Active Min | Wall-clock Min | % of Total Active |
|----------|------------|----------------|-------------------|
| light-coding (workflow-phase) | 2324.7 | 13419.0 | 37.3% |
| mixed (workflow-phase) | 1649.1 | 4796.6 | 26.5% |
| coding (workflow-phase) | 602.0 | 803.3 | 9.7% |
| bead-management (workflow-phase) | 418.7 | 4219.0 | 6.7% |
| light-coding (pre-workflow) | 363.6 | 619.2 | 5.8% |
| coding (pre-workflow) | 361.8 | 14987.6 | 5.8% |
| exploration (workflow-phase) | 156.3 | 250.8 | 2.5% |
| exploration (pre-workflow) | 109.9 | 158.6 | 1.8% |
| bead-management (pre-workflow) | 67.5 | 561.2 | 1.1% |
| configuration (pre-workflow) | 64.3 | 75.5 | 1.0% |
| mixed (pre-workflow) | 59.0 | 1399.8 | 0.9% |
| coding | 24.3 | 2141.1 | 0.4% |
| configuration (workflow-phase) | 8.7 | 8.7 | 0.1% |
| discussion | 7.2 | 7.2 | 0.1% |
| exploration | 4.7 | 12.3 | 0.1% |
| discussion (pre-workflow) | 2.1 | 2.1 | 0.0% |
| bead-management | 2.0 | 2.0 | 0.0% |
| mixed | 0.1 | 0.1 | 0.0% |

**Total bead-management active time:** 488.3 min (8.1 hrs)
**Total bead-management wall-clock time:** 4782.2 min (79.7 hrs)

### Simplified Category Rollup

Categories collapsed across all segment types.

| Category | Active Min | Active Hrs | % of Total |
|----------|------------|------------|------------|
| light-coding | 2688.4 | 44.8 | 43.2% |
| mixed | 1708.3 | 28.5 | 27.4% |
| coding | 988.1 | 16.5 | 15.9% |
| bead-management | 488.3 | 8.1 | 7.8% |
| exploration | 270.9 | 4.5 | 4.4% |
| configuration | 73.0 | 1.2 | 1.2% |
| discussion | 9.3 | 0.2 | 0.1% |

## 15. Headline Metrics

Key aggregate metrics computed with minute-level deduplication across concurrent sessions.

| Metric | Value |
|--------|-------|
| Deduplicated active hours | 74.57 |
| True wall-clock hours (merged intervals) | 405.89 |
| Total cost (JSONL-computed) | $1955.38 |
| Total cost (ccusage, for comparison) | $310.46 |
| Cost per active hour | $26.22 |
| Overhead ratio (bd min / active min) | 16.74% |
| Automation ratio (Agent+Task / total tools) | 6.05% |
| Closed beads | 222 |
| Active days | 8 |
| Beads per day | 27.8 |
| Active minutes per bead | 20.2 |
| Estimation accuracy (median actual/estimated) | 0.58 |
| Phase skip rate (work without brainstorm/deepen) | 73.8% (155/210) |

## 16. Proportional Tool-Call Allocation

For each activity bucket, tool calls are classified as: bd (bead-management), editing (Edit/Write), reading (Read/Grep/Glob), agent-dispatch (Agent/Task), user-dialogue (AskUserQuestion), other. Active time is allocated proportionally to each tool-call type.

| Activity Bucket | Segments | Active Min | agent-dispatch % | bd % | editing % | other % | reading % | user-dialogue % |
|-----------------|----------|------------|--------|--------|--------|--------|--------|--------|
| orchestration | 50 | 2560.33 | 5.8% | 11.4% | 19.8% | 35.8% | 20.1% | 7.0% |
| work | 23 | 1362.86 | 6.6% | 19.2% | 15.4% | 39.4% | 16.0% | 3.4% |
| brainstorm | 17 | 1004.33 | 6.9% | 13.0% | 18.2% | 29.1% | 19.1% | 13.6% |
| coding | 18 | 988.07 | 6.5% | 4.1% | 32.9% | 28.5% | 25.0% | 3.0% |
| plan | 30 | 900.15 | 8.2% | 2.5% | 18.9% | 44.5% | 19.2% | 6.8% |
| interactive-dev | 4 | 22.98 | 3.2% | 0.0% | 17.7% | 54.8% | 24.2% | - |

### Allocated minutes by tool-call type

| Activity Bucket | agent-dispatch min | bd min | editing min | other min | reading min | user-dialogue min |
|-----------------|----------|----------|----------|----------|----------|----------|
| orchestration | 147.57 | 292.63 | 507.29 | 917.73 | 515.25 | 179.86 |
| work | 89.73 | 262.31 | 209.36 | 536.33 | 218.25 | 46.88 |
| brainstorm | 69.17 | 130.95 | 183.23 | 292.01 | 192.21 | 136.76 |
| coding | 63.82 | 40.79 | 324.88 | 281.69 | 247.14 | 29.75 |
| plan | 73.44 | 22.25 | 169.87 | 400.19 | 173.21 | 61.2 |
| interactive-dev | 0.74 | 0.0 | 4.08 | 12.6 | 5.56 | - |

## 17. AskUserQuestion Categorization

AskUserQuestion tool calls categorized by question content. Wait time = gap from AskUserQuestion to next assistant message.

**Total AskUserQuestion events:** 896

| Category | Count | Total Wait Min | Avg Wait Min |
|----------|-------|----------------|--------------|
| confirmation | 278 | 1311.31 | 4.72 |
| triage | 210 | 1383.21 | 6.59 |
| scope | 185 | 174.11 | 0.94 |
| design-decision | 106 | 125.83 | 1.19 |
| other | 105 | 88.03 | 0.84 |
| diagnosis | 12 | 13.76 | 1.15 |

## 18. Orchestration Overhead Analysis

For segments classified as orchestration or orch-coding: proportional split between bd commands (overhead) and productive tool calls (Edit, Write, Read, Grep, Glob, Agent, Task, non-bd Bash).

| Metric | Value |
|--------|-------|
| Total orchestration active time | 2560.33 min |
| BD commands | 698 (12.8%) |
| Productive tool calls | 4775 (87.2%) |
| BD allocated time | 326.53 min |
| Productive allocated time | 2233.8 min |

## 19. Project Cost

Per-request cost computed from JSONL `message.usage` fields with model-specific rates. Covers all assistant responses across all sessions.

### Total

**JSONL-computed cost: $1955.38**

ccusage total (for comparison): $310.46 (delta: $+1644.92, +529.8%)

### Token Totals

| Token Type | Count | Cost | % of Total |
|-----------|-------|------|-----------|
| Input | 115,650 | $0.58 | 0.0% |
| Cache creation | 73,853,960 | $460.77 | 23.6% |
| Cache read | 2,755,353,504 | $1375.79 | 70.4% |
| Output | 4,748,244 | $118.24 | 6.0% |

### Cache vs Non-Cache Cost

| Category | Cost | % of Total |
|----------|------|-----------|
| Cache (creation + read) | $1836.56 | 93.9% |
| Non-cache (input + output) | $118.82 | 6.1% |

### Cost by Model

| Model | Total | Cache | Non-Cache | Cache % |
|-------|-------|-------|-----------|---------|
| claude-opus-4-6 | $1950.63 | $1832.50 | $118.13 | 93.9% |
| claude-sonnet-4-6 | $4.75 | $4.06 | $0.69 | 85.4% |

### Cost by Phase

| Phase | Total | Cache | Non-Cache | Cache % |
|-------|-------|-------|-----------|---------|
| compact-prep | $596.29 | $565.72 | $30.57 | 94.9% |
| work | $408.26 | $382.73 | $25.53 | 93.7% |
| non-workflow | $265.13 | $248.22 | $16.91 | 93.6% |
| brainstorm | $257.90 | $239.43 | $18.47 | 92.8% |
| plan | $226.80 | $210.63 | $16.18 | 92.9% |
| deepen-plan | $101.49 | $95.63 | $5.86 | 94.2% |
| compound | $68.35 | $65.13 | $3.22 | 95.3% |
| gemini-imagegen | $18.42 | $16.98 | $1.44 | 92.2% |
| qa | $10.02 | $9.59 | $0.44 | 95.6% |
| classify-stats | $2.63 | $2.44 | $0.19 | 92.6% |
| version | $0.08 | $0.07 | $0.02 | 81.5% |

### Per-Session Cost Distribution

| Metric | Total | Cache | Non-Cache |
|--------|-------|-------|-----------|
| Sessions with cost > $0 | 34 | | |
| Min | $0.14 | | |
| Median | $14.18 | | |
| Mean | $57.51 | | |
| Max | $673.12 | | |
| P90 | $178.93 | | |

### Per-Session Cache vs Non-Cache

| Metric | Cache $ | Non-Cache $ | Cache % |
|--------|---------|-------------|---------|
| Median | $13.67 | $0.53 | 94.2% |
| Mean | $54.02 | $3.49 | 94.2% |
| Min | $0.13 | $0.00 | 88.5% |
| Max | $626.94 | $46.18 | 99.7% |

## 20. Step Timing from Stats YAML

Per-agent-dispatch duration data mined from `.workflows/stats/*.yaml`. Each entry represents one subagent dispatch with wall-clock duration. Durations shown in minutes.

**Total dispatch entries:** 210

*Cost is approximate — stats YAML captures total I/O tokens only, not cache breakdown. Uses computed cache-inclusive effective rate ($0.69/M tokens) from corrected MODEL_PRICING.*

### Duration by Workflow Command

| Command | N | Median | Mean | P90 | Min | Max | Total Min | Approx Cost |
|---------|---|--------|------|-----|-----|-----|-----------|-------------|
| work | 55 | 2.99 | 4.35 | 9.87 | 0.68 | 18.46 | 239.33 | $2.14 |
| plan | 61 | 2.38 | 2.51 | 4.01 | 0.86 | 5.62 | 153.31 | $1.85 |
| brainstorm | 45 | 1.85 | 1.99 | 2.82 | 0.61 | 5.69 | 89.56 | $1.14 |
| deepen-plan | 12 | 2.77 | 3.12 | 4.74 | 1.74 | 6.06 | 37.4 | $0.46 |

### Duration by Agent Type

| Agent | N | Median | Mean | P90 | Min | Max | Approx Cost |
|-------|---|--------|------|-----|-----|-----|-------------|
| general-purpose | 80 | 2.28 | 3.66 | 7.2 | 0.61 | 18.46 | $2.86 |
| red-team-relay | 24 | 2.02 | 2.2 | 3.8 | 1.07 | 3.8 | $0.32 |
| semantic-checks | 16 | 2.38 | 2.41 | 3.15 | 1.03 | 3.94 | $0.44 |
| repo-research-analyst | 15 | 3.24 | 3.23 | 4.93 | 1.41 | 5.62 | $0.79 |
| learnings-researcher | 9 | 1.79 | 1.83 | - | 1.01 | 2.66 | $0.25 |
| plan-readiness-reviewer | 8 | 1.07 | 1.17 | - | 0.86 | 1.84 | $0.15 |
| context-researcher | 7 | 2.47 | 2.55 | - | 1.82 | 3.19 | $0.28 |
| spec-flow-analyzer | 7 | 4.01 | 3.99 | - | 2.74 | 4.79 | $0.30 |
| plan-consolidator | 4 | 1.9 | 1.79 | - | 1.21 | 2.13 | $0.09 |

### Estimate vs Actual (Stats Dispatch Time)

Compares bead estimated_minutes with total subagent dispatch duration. Note: dispatch time is agent wall-clock only — excludes orchestrator time, user wait, and inter-step gaps.

| Bead | Est Min | Actual Dispatch Min | Ratio | Dispatches | Commands |
|------|---------|---------------------|-------|------------|----------|
| yai0 | 15 | 15.9 | 1.06x | 1 | work |
| vm7m | 10 | 8.96 | 0.9x | 1 | work |
| ort2 | 15 | 10.21 | 0.68x | 1 | work |
| 0nvy | 12 | 6.83 | 0.57x | 1 | work |
| ojry | 12 | 6.21 | 0.52x | 1 | work |
| 9lw6 | 10 | 4.6 | 0.46x | 1 | work |
| n3s5 | 12 | 5.5 | 0.46x | 1 | work |
| df8x | 15 | 6.69 | 0.45x | 1 | work |
| dm5g | 15 | 3.78 | 0.25x | 1 | work |
| qlfx | 30 | 7.17 | 0.24x | 1 | work |
| 3zr | 100 | 20.8 | 0.21x | 3 | work |
| gfl5 | 60 | 11.32 | 0.19x | 1 | work |
| 7uof | 45 | 7.2 | 0.16x | 1 | work |
| yeqy | 20 | 3.05 | 0.15x | 1 | work |
| bpv3 | 30 | 4.11 | 0.14x | 1 | work |
| m441 | 45 | 5.94 | 0.13x | 1 | work |
| igp | 15 | 1.85 | 0.12x | 2 | work |
| szc2 | 30 | 3.65 | 0.12x | 1 | work |
| 8zy | 45 | 4.76 | 0.11x | 1 | work |
| o428 | 15 | 1.32 | 0.09x | 1 | work |
| pud5 | 25 | 2.23 | 0.09x | 1 | work |
| 88gl | 30 | 2.04 | 0.07x | 1 | work |
| bz96 | 10 | 0.68 | 0.07x | 1 | work |
| jak | 90 | 6.49 | 0.07x | 2 | work |
| v3du | 20 | 1.5 | 0.07x | 1 | work |
| 4qc9 | 30 | 1.4 | 0.05x | 1 | work |
| 5849 | 45 | 2.44 | 0.05x | 1 | work |
| qnu | 45 | 2.44 | 0.05x | 1 | work |

**Dispatch-to-estimate ratio:** median 0.15x, mean 0.27x (N=28)

*Ratios < 1.0 mean dispatch time was less than estimated (expected, since estimates cover full workflow including orchestration and user interaction).*

## 21. AskUserQuestion by Workflow

AskUserQuestion events attributed to workflow phases by matching event timestamps against phase windows. Events outside any phase window are classified as non-workflow.

**Total events:** 896
**Total confirmation events:** 278

### All AskUserQuestion Events by Workflow

| Workflow | Count | % of Total | Total Wait Min | Avg Wait Min |
|----------|-------|-----------|----------------|--------------|
| non-workflow | 279 | 31.1% | 768.69 | 2.76 |
| brainstorm | 259 | 28.9% | 271.87 | 1.05 |
| work | 116 | 12.9% | 626.59 | 5.4 |
| plan | 89 | 9.9% | 615.75 | 6.92 |
| deepen-plan | 76 | 8.5% | 89.93 | 1.18 |
| compact-prep | 71 | 7.9% | 710.51 | 10.01 |
| compound | 6 | 0.7% | 12.91 | 2.15 |

### Confirmation Prompts by Workflow

| Workflow | Count | % of Confirmations | Total Wait Min | Avg Wait Min |
|----------|-------|-------------------|----------------|--------------|
| non-workflow | 80 | 28.8% | 569.98 | 7.12 |
| brainstorm | 71 | 25.5% | 77.89 | 1.1 |
| work | 46 | 16.5% | 562.31 | 12.22 |
| plan | 36 | 12.9% | 53.14 | 1.48 |
| compact-prep | 31 | 11.2% | 25.22 | 0.81 |
| deepen-plan | 11 | 4.0% | 17.16 | 1.56 |
| compound | 3 | 1.1% | 5.61 | 1.87 |

### Category Breakdown per Workflow

| Workflow | confirmation | design-decision | diagnosis | other | scope | triage | Total |
|----------|------|------|------|------|------|------|-------|
| non-workflow | 80 | 39 | 0 | 38 | 65 | 57 | 279 |
| brainstorm | 71 | 27 | 6 | 35 | 54 | 66 | 259 |
| work | 46 | 21 | 2 | 17 | 17 | 13 | 116 |
| plan | 36 | 6 | 1 | 4 | 25 | 17 | 89 |
| deepen-plan | 11 | 13 | 3 | 9 | 18 | 22 | 76 |
| compact-prep | 31 | 0 | 0 | 1 | 6 | 33 | 71 |
| compound | 3 | 0 | 0 | 1 | 0 | 2 | 6 |

## 22. Estimation Accuracy by Segment

Estimation accuracy (actual/estimated ratio) segmented by bead type, priority, session count, and estimate size. Ratio < 1 means faster than estimated; > 1 means slower.

**Beads analyzed:** 96 (overall median ratio: 0.58x, mean: 1.69x)

### By Issue Type

| Type | N | Median | Mean | Min | Max | Under-est | Over-est |
|---------|---|--------|------|-----|-----|-----------|----------|
| bug | 19 | 2.36x | 3.24x | 0.07x | 11.73x | 12 | 7 |
| feature | 5 | 0.95x | 2.29x | 0.08x | 5.62x | 2 | 3 |
| task | 72 | 0.54x | 1.24x | 0.09x | 20.45x | 16 | 56 |

### By Priority

| Priority | N | Median | Mean | Min | Max | Under-est | Over-est |
|---------|---|--------|------|-----|-----|-----------|----------|
| P0 | 3 | 0.38x | 0.44x | 0.24x | 0.7x | 0 | 3 |
| P1 | 49 | 0.54x | 1.32x | 0.07x | 20.45x | 10 | 39 |
| P2 | 28 | 1.46x | 2.85x | 0.13x | 11.79x | 17 | 11 |
| P3 | 13 | 0.62x | 1.11x | 0.08x | 4.46x | 3 | 10 |
| P4 | 3 | 0.55x | 0.66x | 0.51x | 0.91x | 0 | 3 |

### By Session Count

| Sessions | N | Median | Mean | Min | Max | Under-est | Over-est |
|---------|---|--------|------|-----|-----|-----------|----------|
| multi-session | 21 | 4.27x | 5.54x | 0.95x | 20.45x | 20 | 1 |
| single-session | 75 | 0.49x | 0.61x | 0.07x | 3.86x | 10 | 65 |

### By Estimate Size

| Bucket | N | Median | Mean | Min | Max | Under-est | Over-est |
|---------|---|--------|------|-----|-----|-----------|----------|
| <15min | 19 | 0.91x | 1.35x | 0.4x | 8.06x | 7 | 12 |
| 15-60min | 71 | 0.48x | 1.46x | 0.07x | 20.45x | 17 | 54 |
| 60-120min | 4 | 4.45x | 5.86x | 2.76x | 11.79x | 4 | 0 |
| >120min | 2 | 4.66x | 4.66x | 3.7x | 5.62x | 2 | 0 |

### Per-Bead Detail

| Bead | Type | Pri | Est | Actual | Ratio | Sessions | Bucket |
|------|------|-----|-----|--------|-------|----------|--------|
| 5b6 | task | P1 | 45 | 920.2 | 20.45x | 3 | 15-60min |
| 3zr | task | P2 | 100 | 1179.3 | 11.79x | 4 | 60-120min |
| p14 | bug | P2 | 30 | 351.8 | 11.73x | 2 | 15-60min |
| jg6 | bug | P2 | 20 | 179.0 | 8.95x | 2 | 15-60min |
| ywug | bug | P2 | 5 | 40.3 | 8.06x | 2 | <15min |
| zwjg | bug | P2 | 20 | 118.3 | 5.91x | 3 | 15-60min |
| voo | feature | P1 | 150 | 842.3 | 5.62x | 2 | >120min |
| jak | task | P1 | 90 | 415.7 | 4.62x | 3 | 60-120min |
| ka3w | feature | P3 | 30 | 133.9 | 4.46x | 4 | 15-60min |
| xzn | task | P2 | 60 | 257.8 | 4.3x | 4 | 15-60min |
| nn3 | task | P1 | 90 | 383.9 | 4.27x | 2 | 60-120min |
| 4qc9 | bug | P2 | 30 | 121.7 | 4.06x | 2 | 15-60min |
| ry5o | bug | P3 | 15 | 57.9 | 3.86x | 1 | 15-60min |
| 3k3 | task | P1 | 180 | 665.7 | 3.7x | 3 | >120min |
| 8one | bug | P2 | 60 | 221.9 | 3.7x | 6 | 15-60min |
| dj65 | bug | P2 | 45 | 162.9 | 3.62x | 2 | 15-60min |
| pj6k | bug | P2 | 30 | 87.5 | 2.92x | 1 | 15-60min |
| 3l7 | task | P1 | 120 | 331.1 | 2.76x | 4 | 60-120min |
| j6ui | bug | P2 | 10 | 23.6 | 2.36x | 2 | <15min |
| icn | bug | P2 | 15 | 33.5 | 2.23x | 2 | 15-60min |
| 8sd | task | P2 | 30 | 52.6 | 1.75x | 1 | 15-60min |
| dndn | task | P1 | 60 | 96.7 | 1.61x | 3 | 15-60min |
| 71sr | task | P2 | 5 | 7.9 | 1.58x | 1 | <15min |
| 5kxt | task | P2 | 10 | 13.3 | 1.33x | 1 | <15min |
| ml1 | task | P1 | 5 | 6.5 | 1.3x | 1 | <15min |
| kte5 | task | P1 | 8 | 10.2 | 1.28x | 1 | <15min |
| sg5b | task | P2 | 10 | 11.8 | 1.18x | 1 | <15min |
| xnep | bug | P2 | 60 | 69.5 | 1.16x | 3 | 15-60min |
| i2tn | task | P1 | 20 | 20.5 | 1.03x | 1 | 15-60min |
| pdue | task | P3 | 15 | 15.4 | 1.03x | 1 | 15-60min |
| ort2 | task | P1 | 15 | 14.9 | 0.99x | 1 | 15-60min |
| u1fd | feature | P1 | 30 | 28.4 | 0.95x | 2 | 15-60min |
| 0nvy | task | P1 | 12 | 11.2 | 0.93x | 1 | <15min |
| 9lw6 | task | P1 | 10 | 9.1 | 0.91x | 1 | <15min |
| bw9v | task | P4 | 10 | 9.1 | 0.91x | 1 | <15min |
| w2hf | task | P3 | 15 | 13.6 | 0.91x | 1 | 15-60min |
| ojry | task | P1 | 12 | 10.5 | 0.88x | 1 | <15min |
| yai0 | task | P1 | 15 | 13.1 | 0.88x | 1 | 15-60min |
| n3s5 | task | P1 | 12 | 9.8 | 0.82x | 1 | <15min |
| yeqy | task | P3 | 20 | 16.3 | 0.82x | 1 | 15-60min |
| vm7m | task | P1 | 10 | 7.9 | 0.79x | 1 | <15min |
| df8x | task | P1 | 15 | 11.1 | 0.74x | 1 | 15-60min |
| rdij | bug | P0 | 20 | 14.0 | 0.7x | 1 | 15-60min |
| a433 | task | P1 | 10 | 6.9 | 0.69x | 1 | <15min |
| qlfx | task | P3 | 30 | 20.2 | 0.67x | 1 | 15-60min |
| v99 | task | P1 | 15 | 9.7 | 0.64x | 1 | 15-60min |
| je54 | bug | P3 | 10 | 6.2 | 0.62x | 1 | <15min |
| gym5 | task | P1 | 10 | 5.9 | 0.59x | 1 | <15min |
| 9c0 | task | P2 | 20 | 11.5 | 0.58x | 1 | 15-60min |
| dm5g | task | P1 | 15 | 8.6 | 0.58x | 1 | 15-60min |
| 1de | task | P4 | 20 | 10.9 | 0.55x | 1 | 15-60min |
| 9l0o | task | P1 | 15 | 8.2 | 0.55x | 1 | 15-60min |
| 8zy | task | P1 | 45 | 24.4 | 0.54x | 1 | 15-60min |
| a7t | task | P1 | 10 | 5.3 | 0.53x | 1 | <15min |
| 3ysa | task | P3 | 20 | 10.3 | 0.52x | 1 | 15-60min |
| h7j | bug | P4 | 30 | 15.2 | 0.51x | 1 | 15-60min |
| pck2 | bug | P1 | 30 | 14.9 | 0.5x | 1 | 15-60min |
| 88gl | task | P3 | 30 | 14.8 | 0.49x | 1 | 15-60min |
| zvux | bug | P2 | 10 | 4.9 | 0.49x | 1 | <15min |
| 924 | task | P1 | 15 | 7.1 | 0.48x | 1 | 15-60min |
| 9vy | task | P3 | 15 | 7.3 | 0.48x | 1 | 15-60min |
| e5wg | task | P1 | 15 | 7.3 | 0.48x | 1 | 15-60min |
| 3m1 | task | P2 | 30 | 13.7 | 0.46x | 1 | 15-60min |
| bz96 | task | P1 | 10 | 4.0 | 0.4x | 1 | <15min |
| o428 | task | P0 | 15 | 5.7 | 0.38x | 1 | 15-60min |
| igp | task | P2 | 15 | 5.4 | 0.36x | 1 | 15-60min |
| z5lj | feature | P3 | 20 | 6.9 | 0.35x | 1 | 15-60min |
| j3wo | task | P1 | 30 | 10.3 | 0.34x | 1 | 15-60min |
| u3jn | task | P1 | 45 | 13.5 | 0.3x | 1 | 15-60min |
| v3du | task | P1 | 20 | 6.0 | 0.3x | 1 | 15-60min |
| wg5 | task | P1 | 20 | 5.8 | 0.29x | 1 | 15-60min |
| bpv3 | task | P1 | 30 | 8.4 | 0.28x | 1 | 15-60min |
| pud5 | task | P1 | 25 | 6.9 | 0.28x | 1 | 15-60min |
| 5849 | task | P2 | 45 | 12.0 | 0.27x | 1 | 15-60min |
| cew | task | P2 | 15 | 4.0 | 0.27x | 1 | 15-60min |
| gfl5 | task | P1 | 60 | 15.9 | 0.27x | 1 | 15-60min |
| szc2 | task | P1 | 30 | 8.0 | 0.27x | 1 | 15-60min |
| tvc | task | P1 | 15 | 4.0 | 0.27x | 1 | 15-60min |
| 7uof | task | P1 | 45 | 11.6 | 0.26x | 1 | 15-60min |
| m441 | task | P0 | 45 | 10.6 | 0.24x | 1 | 15-60min |
| vxi0 | task | P1 | 45 | 10.5 | 0.23x | 1 | 15-60min |
| vzo | task | P1 | 25 | 5.5 | 0.22x | 1 | 15-60min |
| 50s | task | P1 | 20 | 4.0 | 0.2x | 1 | 15-60min |
| 5a2 | task | P2 | 20 | 4.0 | 0.2x | 1 | 15-60min |
| tiv | task | P1 | 45 | 8.2 | 0.18x | 1 | 15-60min |
| 4rw | task | P2 | 25 | 4.0 | 0.16x | 1 | 15-60min |
| bdl | task | P3 | 25 | 4.0 | 0.16x | 1 | 15-60min |
| h056 | task | P1 | 25 | 4.0 | 0.16x | 1 | 15-60min |
| kfq | task | P1 | 25 | 4.0 | 0.16x | 1 | 15-60min |
| c5ec | task | P2 | 45 | 6.5 | 0.15x | 1 | 15-60min |
| gjvi | bug | P2 | 30 | 4.0 | 0.13x | 1 | 15-60min |
| xj9 | task | P2 | 30 | 4.0 | 0.13x | 1 | 15-60min |
| k752 | task | P1 | 45 | 4.0 | 0.09x | 1 | 15-60min |
| qnu | task | P1 | 45 | 4.0 | 0.09x | 1 | 15-60min |
| nrpu | feature | P3 | 20 | 1.6 | 0.08x | 1 | 15-60min |
| x15f | bug | P1 | 60 | 4.0 | 0.07x | 1 | 15-60min |

## 23. Compaction Cost

Cost per compaction event (token cost of the compaction request) and reorientation time (gap from compaction to first productive tool call — Edit/Write/Agent/Task, excluding Read/Grep/Glob).

**Compaction events:** 97 across 13 sessions

### Token Cost per Compaction

| Metric | Value |
|--------|-------|
| Total | $8.26 |
| Median | $0.0850 |
| Mean | $0.0851 |
| Min | $0.0385 |
| Max | $0.2326 |

### Reorientation Time

Time from compaction to first productive tool call (Edit/Write/Agent/Task). **Raw** = wall-clock gap. **Active** = idle gaps >5 min subtracted (filters overnight/AFK gaps from reorientation window).

| Metric | Raw | Active |
|--------|-----|--------|
| Events with productive follow-up | 97/97 | 97/97 |
| Median | 5.72 min | 4.17 min |
| Mean | 24.83 min | 5.01 min |
| Max | 829.15 min | 24.69 min |
| Total | 2408.67 min | 485.55 min |

### Compaction Cache vs Non-Cache

| Category | Cost | % |
|----------|------|---|
| Cache (creation + read) | $7.85 | 95.1% |
| Non-cache (input + output) | $0.41 | 4.9% |
| Total | $8.26 | 100% |

### Per-Event Detail

| Session | Timestamp | Cost | Cache | Non-Cache | Cache % | Reorientation (Raw) | Reorientation (Active) | Model |
|---------|-----------|------|-------|-----------|---------|---------------------|------------------------|-------|
| ...177e090c | 2026-02-25T19:36:03 | $0.0942 | $0.0942 | $0.0000 | 100% | 2.92 min | 2.92 min | 6 |
| ...177e090c | 2026-02-25T19:51:11 | $0.0516 | $0.0515 | $0.0001 | 100% | 4.62 min | 4.62 min | 6 |
| ...177e090c | 2026-02-25T21:14:09 | $0.0679 | $0.0679 | $0.0000 | 100% | 6.37 min | 6.37 min | 6 |
| ...177e090c | 2026-03-08T01:36:47 | $0.0850 | $0.0832 | $0.0019 | 98% | 11.93 min | 5.49 min | 6 |
| ...177e090c | 2026-03-08T02:05:11 | $0.0494 | $0.0471 | $0.0024 | 95% | 1.66 min | 1.66 min | 6 |
| ...177e090c | 2026-03-08T02:47:52 | $0.0961 | $0.0915 | $0.0046 | 95% | 5.23 min | 5.23 min | 6 |
| ...177e090c | 2026-03-08T04:43:56 | $0.0882 | $0.0851 | $0.0030 | 97% | 12.59 min | 12.59 min | 6 |
| ...177e090c | 2026-03-08T13:35:08 | $0.0714 | $0.0638 | $0.0076 | 89% | 23.8 min | 4.3 min | 6 |
| ...177e090c | 2026-03-08T15:23:13 | $0.1055 | $0.0975 | $0.0080 | 92% | 1.36 min | 1.36 min | 6 |
| ...2b61e5b6 | 2026-03-08T15:32:30 | $0.0866 | $0.0826 | $0.0040 | 95% | 2.3 min | 2.3 min | 6 |
| ...67a375ed | 2026-03-08T15:56:55 | $0.0841 | $0.0739 | $0.0102 | 88% | 472.85 min | 7.01 min | 6 |
| ...177e090c | 2026-03-08T15:58:03 | $0.0644 | $0.0576 | $0.0068 | 89% | 41.95 min | 1.79 min | 6 |
| ...2b61e5b6 | 2026-03-08T16:08:14 | $0.1005 | $0.0937 | $0.0069 | 93% | 2.4 min | 2.4 min | 6 |
| ...2b61e5b6 | 2026-03-08T16:56:45 | $0.0689 | $0.0647 | $0.0043 | 94% | 5.03 min | 5.03 min | 6 |
| ...2b61e5b6 | 2026-03-08T18:03:18 | $0.0749 | $0.0680 | $0.0068 | 91% | 12.31 min | 5.34 min | 6 |
| ...2b61e5b6 | 2026-03-08T23:45:41 | $0.0910 | $0.0830 | $0.0080 | 91% | 38.25 min | 7.91 min | 6 |
| ...67a375ed | 2026-03-09T00:44:03 | $0.0607 | $0.0544 | $0.0063 | 90% | 10.24 min | 0.67 min | 6 |
| ...2b61e5b6 | 2026-03-09T01:34:24 | $0.0648 | $0.0579 | $0.0068 | 89% | 14.66 min | 3.33 min | 6 |
| ...67a375ed | 2026-03-09T01:41:18 | $0.0820 | $0.0759 | $0.0062 | 92% | 6.08 min | 6.08 min | 6 |
| ...2b61e5b6 | 2026-03-09T03:01:46 | $0.0837 | $0.0807 | $0.0030 | 96% | 5.02 min | 5.02 min | 6 |
| ...67a375ed | 2026-03-09T03:01:49 | $0.0876 | $0.0851 | $0.0026 | 97% | 1.79 min | 1.79 min | 6 |
| ...67a375ed | 2026-03-09T04:16:25 | $0.0925 | $0.0888 | $0.0036 | 96% | 5.84 min | 5.84 min | 6 |
| ...2b61e5b6 | 2026-03-09T04:45:16 | $0.0760 | $0.0707 | $0.0054 | 93% | 11.2 min | 11.2 min | 6 |
| ...67a375ed | 2026-03-09T05:00:50 | $0.0586 | $0.0555 | $0.0031 | 95% | 0.3 min | 0.3 min | 6 |
| ...67a375ed | 2026-03-09T05:48:05 | $0.0702 | $0.0694 | $0.0008 | 99% | 6.33 min | 6.33 min | 6 |
| ...67a375ed | 2026-03-09T11:13:10 | $0.0487 | $0.0426 | $0.0062 | 87% | 1.62 min | 1.62 min | 6 |
| ...67a375ed | 2026-03-09T11:46:27 | $0.0802 | $0.0766 | $0.0036 | 96% | 9.61 min | 9.61 min | 6 |
| ...67a375ed | 2026-03-09T12:38:50 | $0.0729 | $0.0692 | $0.0037 | 95% | 5.6 min | 5.6 min | 6 |
| ...67a375ed | 2026-03-09T13:20:12 | $0.0679 | $0.0646 | $0.0033 | 95% | 1.16 min | 1.16 min | 6 |
| ...177e090c | 2026-03-09T13:28:33 | $0.0870 | $0.0836 | $0.0034 | 96% | 1.1 min | 1.1 min | 6 |
| ...67a375ed | 2026-03-09T13:31:01 | $0.0615 | $0.0609 | $0.0006 | 99% | 13.14 min | 13.14 min | 6 |
| ...177e090c | 2026-03-09T14:10:34 | $0.0738 | $0.0705 | $0.0033 | 96% | 6.12 min | 6.12 min | 6 |
| ...2b61e5b6 | 2026-03-09T14:52:31 | $0.0940 | $0.0914 | $0.0025 | 97% | 62.25 min | 4.43 min | 6 |
| ...67a375ed | 2026-03-09T15:18:52 | $0.0864 | $0.0818 | $0.0046 | 95% | 2.23 min | 2.23 min | 6 |
| ...67a375ed | 2026-03-09T16:12:10 | $0.0770 | $0.0765 | $0.0004 | 99% | 5.53 min | 5.53 min | 6 |
| ...67a375ed | 2026-03-09T16:31:35 | $0.0385 | $0.0333 | $0.0051 | 87% | 1.62 min | 1.62 min | 6 |
| ...67a375ed | 2026-03-09T17:02:54 | $0.0769 | $0.0737 | $0.0032 | 96% | 7.49 min | 7.49 min | 6 |
| ...177e090c | 2026-03-09T17:21:19 | $0.0887 | $0.0879 | $0.0009 | 99% | 0.43 min | 0.43 min | 6 |
| ...67a375ed | 2026-03-09T18:26:45 | $0.0953 | $0.0903 | $0.0050 | 95% | 12.42 min | 4.88 min | 6 |
| ...67a375ed | 2026-03-09T18:49:59 | $0.0582 | $0.0531 | $0.0051 | 91% | 4.05 min | 4.05 min | 6 |
| ...67a375ed | 2026-03-09T22:42:36 | $0.0765 | $0.0725 | $0.0040 | 95% | 2.28 min | 2.28 min | 6 |
| ...67a375ed | 2026-03-10T00:44:59 | $0.0658 | $0.0619 | $0.0039 | 94% | 1.18 min | 1.18 min | 6 |
| ...67a375ed | 2026-03-10T01:28:17 | $0.0782 | $0.0770 | $0.0011 | 99% | 1.88 min | 1.88 min | 6 |
| ...67a375ed | 2026-03-10T02:44:48 | $0.0783 | $0.0762 | $0.0021 | 97% | 0.9 min | 0.9 min | 6 |
| ...67a375ed | 2026-03-10T03:10:55 | $0.0965 | $0.0891 | $0.0073 | 92% | 0.55 min | 0.55 min | 6 |
| ...67a375ed | 2026-03-10T03:44:04 | $0.0692 | $0.0621 | $0.0071 | 90% | 5.72 min | 5.72 min | 6 |
| ...67a375ed | 2026-03-10T11:52:25 | $0.0721 | $0.0667 | $0.0054 | 93% | 5.61 min | 5.61 min | 6 |
| ...67a375ed | 2026-03-10T13:33:44 | $0.1019 | $0.0973 | $0.0046 | 95% | 4.05 min | 4.05 min | 6 |
| ...67a375ed | 2026-03-10T14:04:17 | $0.1033 | $0.1033 | $0.0000 | 100% | 12.21 min | 12.21 min | 6 |
| ...67a375ed | 2026-03-10T15:09:08 | $0.0459 | $0.0459 | $0.0000 | 100% | 2.05 min | 2.05 min | 6 |
| ...67a375ed | 2026-03-10T16:48:03 | $0.1062 | $0.0985 | $0.0077 | 93% | 0.42 min | 0.42 min | 6 |
| ...67a375ed | 2026-03-10T17:12:56 | $0.0537 | $0.0486 | $0.0051 | 90% | 19.49 min | 19.49 min | 6 |
| ...177e090c | 2026-03-10T17:47:51 | $0.0798 | $0.0723 | $0.0076 | 91% | 50.72 min | 15.25 min | 6 |
| ...67a375ed | 2026-03-10T18:24:10 | $0.0815 | $0.0813 | $0.0002 | 100% | 159.13 min | 4.05 min | 6 |
| ...67a375ed | 2026-03-10T18:24:10 | $0.0748 | $0.0745 | $0.0002 | 100% | 159.13 min | 4.05 min | 6 |
| ...177e090c | 2026-03-10T21:41:57 | $0.0594 | $0.0589 | $0.0005 | 99% | 829.15 min | 24.69 min | 6 |
| ...67a375ed | 2026-03-10T21:47:41 | $0.0699 | $0.0662 | $0.0036 | 95% | 4.78 min | 4.78 min | 6 |
| ...67a375ed | 2026-03-10T22:17:41 | $0.1059 | $0.0962 | $0.0097 | 91% | 8.09 min | 8.09 min | 6 |
| ...67a375ed | 2026-03-10T23:11:48 | $0.0937 | $0.0877 | $0.0060 | 94% | 10.73 min | 10.73 min | 6 |
| ...67a375ed | 2026-03-10T23:41:57 | $0.0764 | $0.0696 | $0.0068 | 91% | 0.77 min | 0.77 min | 6 |
| ...67a375ed | 2026-03-11T01:07:06 | $0.0416 | $0.0386 | $0.0030 | 93% | 14.02 min | 0.94 min | 6 |
| ...67a375ed | 2026-03-11T02:58:14 | $0.1035 | $0.0987 | $0.0048 | 95% | 7.73 min | 7.73 min | 6 |
| ...67a375ed | 2026-03-11T03:32:14 | $0.0942 | $0.0879 | $0.0063 | 93% | 5.92 min | 0.6 min | 6 |
| ...67a375ed | 2026-03-11T11:51:32 | $0.1034 | $0.0972 | $0.0061 | 94% | 11.68 min | 11.68 min | 6 |
| ...67a375ed | 2026-03-11T13:57:55 | $0.1037 | $0.0976 | $0.0061 | 94% | 232.09 min | 16.85 min | 6 |
| ...177e090c | 2026-03-11T14:27:04 | $0.0899 | $0.0864 | $0.0035 | 96% | 4.1 min | 4.1 min | 6 |
| ...9629ff45 | 2026-03-11T15:15:10 | $0.0904 | $0.0827 | $0.0077 | 92% | 7.14 min | 7.14 min | 6 |
| ...9629ff45 | 2026-03-11T16:00:08 | $0.1146 | $0.1062 | $0.0084 | 93% | 2.9 min | 2.9 min | 6 |
| ...9629ff45 | 2026-03-11T16:57:14 | $0.0925 | $0.0878 | $0.0047 | 95% | 2.74 min | 2.74 min | 6 |
| ...9629ff45 | 2026-03-11T17:52:35 | $0.0754 | $0.0688 | $0.0066 | 91% | 5.39 min | 5.39 min | 6 |
| ...9629ff45 | 2026-03-11T18:42:08 | $0.0639 | $0.0587 | $0.0052 | 92% | 88.03 min | 7.52 min | 6 |
| ...67a375ed | 2026-03-11T20:31:36 | $0.0968 | $0.0926 | $0.0042 | 96% | 28.09 min | 10.82 min | 6 |
| ...9629ff45 | 2026-03-11T20:54:18 | $0.0930 | $0.0925 | $0.0006 | 99% | 5.33 min | 5.33 min | 6 |
| ...9629ff45 | 2026-03-11T21:30:48 | $0.0904 | $0.0855 | $0.0049 | 95% | 19.09 min | 2.19 min | 6 |
| ...67a375ed | 2026-03-11T21:31:19 | $0.0843 | $0.0789 | $0.0054 | 94% | 1.8 min | 1.8 min | 6 |
| ...67a375ed | 2026-03-11T21:31:19 | $0.0929 | $0.0921 | $0.0008 | 99% | 1.8 min | 1.8 min | 6 |
| ...67a375ed | 2026-03-12T01:13:00 | $0.0851 | $0.0846 | $0.0005 | 99% | 5.79 min | 5.79 min | 6 |
| ...9629ff45 | 2026-03-12T02:05:33 | $0.0990 | $0.0927 | $0.0063 | 94% | 5.0 min | 5.0 min | 6 |
| ...9629ff45 | 2026-03-12T02:41:48 | $0.0854 | $0.0786 | $0.0068 | 92% | 505.62 min | 3.14 min | 6 |
| ...9629ff45 | 2026-03-12T12:39:25 | $0.0910 | $0.0856 | $0.0054 | 94% | 15.99 min | 2.49 min | 6 |
| ...67a375ed | 2026-03-12T12:45:05 | $0.0929 | $0.0921 | $0.0008 | 99% | -911.98 min | 0 min | 6 |
| ...13d97ef3 | 2026-03-12T14:53:25 | $0.0655 | $0.0651 | $0.0004 | 99% | 4.17 min | 4.17 min | 6 |
| ...1d1c3e06 | 2026-03-12T15:47:07 | $0.1029 | $0.0971 | $0.0058 | 94% | 23.16 min | 1.92 min | 6 |
| ...1d1c3e06 | 2026-03-12T16:59:57 | $0.1009 | $0.0941 | $0.0069 | 93% | 2.28 min | 2.28 min | 6 |
| ...28b4b1f6 | 2026-03-12T18:17:09 | $0.0710 | $0.0658 | $0.0052 | 93% | 1.41 min | 1.41 min | 6 |
| ...c3998c5f | 2026-03-12T19:27:12 | $0.0892 | $0.0830 | $0.0062 | 93% | 5.59 min | 5.59 min | 6 |
| ...90b13287 | 2026-03-12T19:52:41 | $0.0998 | $0.0952 | $0.0046 | 95% | 116.17 min | 1.97 min | 6 |
| ...1480f8b2 | 2026-03-12T19:53:53 | $0.0796 | $0.0739 | $0.0057 | 93% | 22.16 min | 10.95 min | 6 |
| ...1480f8b2 | 2026-03-12T21:15:05 | $0.0850 | $0.0842 | $0.0008 | 99% | 0.68 min | 0.68 min | 6 |
| ...bc70fb15 | 2026-03-13T14:24:01 | $0.0892 | $0.0883 | $0.0009 | 99% | 2.77 min | 2.77 min | 6 |
| ...bc70fb15 | 2026-03-13T15:11:56 | $0.1075 | $0.1030 | $0.0044 | 96% | 5.97 min | 5.97 min | 6 |
| ...bc70fb15 | 2026-03-13T16:23:16 | $0.1010 | $0.0962 | $0.0048 | 95% | 9.4 min | 4.28 min | 6 |
| ...5393bf9e | 2026-03-13T16:32:13 | $0.0779 | $0.0738 | $0.0041 | 95% | 10.71 min | 10.71 min | 6 |
| ...3380bdcd | 2026-03-13T17:30:22 | $0.0949 | $0.0946 | $0.0003 | 100% | 1.32 min | 1.32 min | 6 |
| ...3380bdcd | 2026-03-14T13:13:33 | $0.1184 | $0.1170 | $0.0014 | 99% | 1.14 min | 1.14 min | 6 |
| ...bc70fb15 | 2026-03-14T15:05:26 | $0.2326 | $0.2320 | $0.0006 | 100% | 12.08 min | 5.65 min | 6 |
| ...3380bdcd | 2026-03-14T15:07:58 | $0.2072 | $0.1975 | $0.0098 | 95% | 11.15 min | 4.15 min | 6 |

## 24. Velocity Trend by Date

Daily velocity: bead closures and active hours per date. Active time is computed from session timestamps (sum of session active minutes bucketed by session start date). Bead closures come from the beads database `closed_at` field. Note: beads/hour can be skewed on individual dates because long sessions bucket to their start date while bead closures bucket to their close date.

**Date range:** 9 dates, 222 beads closed, 103.76 active hours

### Velocity Summary

| Metric | Value |
|--------|-------|
| Overall beads/hour | 2.14 |
| Median beads/day | 20.5 |
| Mean beads/day | 27.8 |
| Median active hours/day | 14.94 |
| Mean active hours/day | 14.82 |

### Daily Trend

| Date | Beads Closed | Active Hours | Beads/Hour |
|------|-------------|-------------|------------|
| 2026-02-25 | 10 | 17.37 | 0.58 |
| 2026-03-07 | 0 | 0.0 | - |
| 2026-03-08 | 13 | 45.4 | 0.29 |
| 2026-03-09 | 67 | 0.06 | 1116.67 |
| 2026-03-10 | 29 | 0.0 | - |
| 2026-03-11 | 19 | 8.47 | 2.24 |
| 2026-03-12 | 56 | 14.94 | 3.75 |
| 2026-03-13 | 22 | 17.15 | 1.28 |
| 2026-03-14 | 6 | 0.37 | 16.22 |

## 25. Permission Prompt Estimate

**Methodology caveat:** There is no JSONL signal for OS-level permission prompts. This section uses a proxy: count Bash tool calls in `permissionMode="default"` sessions that match known heuristic-triggering patterns (`$()`, `<<`, `{"`) from the AGENTS.md Bash Generation Rules. The estimate multiplies the triggering-pattern count by the median user response time for confirmation AskUserQuestion events as an upper bound. True cost is likely 30-50% of this estimate because: (a) not every pattern-matching Bash call triggers a permission prompt (static rules suppress some heuristics), and (b) permission prompts are simpler yes/no confirmations that resolve faster than full AskUserQuestion interactions.

### Session Permission Modes

| Mode | Sessions |
|------|----------|
| `default` | 33 |
| `acceptEdits` | 19 |
| No mode field | 64 |
| **Total** | **116** |

### Triggering Patterns

**Total triggering Bash commands:** 121 across 20 sessions

| Pattern | Count |
|---------|-------|
| `$()` | 74 |
| `{"` | 33 |
| `<<` | 14 |

### Cost Estimate

| Metric | Value |
|--------|-------|
| Median confirmation wait (proxy) | 0.63 min |
| Estimated total wait (upper bound) | 76.2 min (1.27 hours) |
| Likely range (30-50% of upper bound) | 22.9-38.1 min (0.38-0.64 hours) |

## 26. QA Retry Cost

QA retry sequences occur when a QA invocation (plugin-changes-qa) fails, requiring fix phases (typically work) followed by another QA run. Each additional QA invocation after the first in such a chain counts as a retry.

*No QA retry sequences detected.* 2 session(s) had QA skill invocations, but none contained qa->fix->qa retry chains. This means either QA passed on first attempt or fixes were done outside the skill-tracked workflow.

## 27. Permission Prompt Analysis (Hook Audit)

Cross-references the hook audit log (`.workflows/.hook-audit.log`) with JSONL session data to classify every Bash tool call into one of four categories: **auto-approved** (matched in hook audit log by exact tool_use_id), **hook-suppressed** (occurred within a `/do:work` phase window where the hook was disabled via sentinel file), **ambiguous** (work session with no identifiable phase windows from skill invocations), or **user-prompted** (not auto-approved and not in a work-phase window — includes both genuinely user-prompted calls and calls from sessions where the hook was running but entries are legacy 3-field format without tool_use_id for matching).

**Note:** The hook audit log only covers entries since hook installation (Mar 10, 2026). All current entries are legacy 3-field format (no tool_use_id). The auto-approved category will populate once 5-field entries accumulate (after P0b lands). Until then, the user-prompted count is an upper bound — many of those calls were likely auto-approved by the hook but cannot be matched without tool_use_id.

### Aggregate Classification

| Category | Count | % of Total |
|----------|-------|------------|
| auto-approved | 0 | 0.0% |
| hook-suppressed | 1947 | 28.8% |
| ambiguous | 738 | 10.9% |
| user-prompted | 4077 | 60.3% |
| **Total Bash calls** | **6762** | **100%** |

### Hook Audit Log Statistics

| Metric | Value |
|--------|-------|
| Hook coverage start | 2026-03-10T23:43:07+00:00 |
| Legacy (3-field) entries (all tools) | 3455 |
| Legacy (3-field) Bash entries | 2911 |
| New (5-field) Bash entries in log | 0 |
| Work sessions (total) | 16 |
| Pure work sessions | 1 |
| Mixed work sessions | 15 |

### Comparison with Section 25 Proxy Estimate

| Metric | Section 25 (Proxy) | Section 27 (Hook Audit) |
|--------|-------------------|------------------------|
| User-prompted Bash calls | 121 (pattern-based upper bound) | 4077 (unmatched in audit log) |
| Ratio (S27/S25) | — | 33.69x |

The section 25 proxy counts Bash calls matching heuristic-triggering patterns (`$()`, `<<`, `{"`) as an upper bound. The section 27 hook audit classifies calls that were NOT auto-approved and NOT in work-phase sessions. The difference reflects: (a) static rules that suppress heuristics for known-safe commands, (b) commands that match patterns but don't actually trigger prompts, and (c) different classification methodology (pattern-based vs audit-based).

### Per-Session Breakdown (Top 15 by User-Prompted)

| Session | Total | Auto-Approved | Suppressed | Ambiguous | User-Prompted |
|---------|-------|--------------|------------|-----------|---------------|
| 77508108-376... | 2320 | 0 | 840 | 0 | 1480 |
| 3b01ea81-37f... | 869 | 0 | 155 | 0 | 714 |
| 7629c6aa-170... | 620 | 0 | 124 | 0 | 496 |
| 551deff1-065... | 560 | 0 | 237 | 0 | 323 |
| 59b5ae34-2de... | 399 | 0 | 159 | 0 | 240 |
| c2fb05c7-7fa... | 226 | 0 | 71 | 0 | 155 |
| 880d09ad-32b... | 190 | 0 | 73 | 0 | 117 |
| 82a9c285-d53... | 116 | 0 | 0 | 0 | 116 |
| a7c3f119-904... | 110 | 0 | 0 | 0 | 110 |
| beb9a949-4eb... | 86 | 0 | 0 | 0 | 86 |
| 0d63af28-01d... | 148 | 0 | 81 | 0 | 67 |
| d78d7c5b-e66... | 111 | 0 | 54 | 0 | 57 |
| d9750748-248... | 28 | 0 | 0 | 0 | 28 |
| 2ea0781f-eb6... | 26 | 0 | 0 | 0 | 26 |
| 27df18e9-af1... | 20 | 0 | 0 | 0 | 20 |

## 28. Dispatch Analysis by Classification

Groups stats YAML dispatch entries by classification dimensions: **complexity** (rote/mechanical/analytical/judgment) and **output_type** (code-edit/research/review/relay/synthesis). Entries without classification are grouped as 'unclassified'. Durations in minutes, tokens are raw I/O totals.

### Duration by Complexity Tier

| Complexity | N | Median | Mean | P90 | Min | Max | Total Min |
|------------|---|--------|------|-----|-----|-----|-----------|
| analytical | 95 | 2.17 | 3.19 | 6.21 | 0.61 | 18.46 | 303.09 |
| mechanical | 36 | 2.02 | 2.16 | 3.44 | 0.81 | 3.8 | 77.63 |
| unclassified | 28 | 2.93 | 3.62 | 6.06 | 1.29 | 11.32 | 101.29 |
| judgment | 14 | 2.32 | 2.69 | 4.73 | 1.03 | 5.69 | 37.6 |
| **Total** | **173** | | | | | | **519.61** |

### Duration by Output Type

| Output Type | N | Median | Mean | P90 | Min | Max | Total Min |
|-------------|---|--------|------|-----|-----|-----|-----------|
| code-edit | 38 | 2.09 | 3.16 | 5.77 | 0.68 | 18.46 | 120.08 |
| research | 37 | 3.14 | 4.17 | 8.96 | 1.01 | 15.9 | 154.17 |
| review | 36 | 2.25 | 2.26 | 4.01 | 0.86 | 4.79 | 81.23 |
| unclassified | 28 | 2.93 | 3.62 | 6.06 | 1.29 | 11.32 | 101.29 |
| relay | 22 | 2.02 | 2.21 | 3.8 | 1.07 | 3.8 | 48.55 |
| synthesis | 12 | 1.12 | 1.19 | 1.75 | 0.61 | 2.06 | 14.29 |
| **Total** | **173** | | | | | | **519.61** |

### Token Usage by Complexity Tier

| Complexity | N (with tokens) | Median Tokens | Mean Tokens | Total Tokens |
|------------|-----------------|---------------|-------------|--------------|
| analytical | 95 | 48,396 | 50,428 | 4,790,711 |
| mechanical | 36 | 20,630 | 25,530 | 919,109 |
| unclassified | 28 | 59,862 | 59,460 | 1,664,893 |
| judgment | 14 | 38,701 | 51,360 | 719,046 |
| **Total** | | | | **8,093,759** |

### Cross-Tabulation: Complexity x Output Type (Count)

| Complexity | code-edit | relay | research | review | synthesis | unclassified | **Row Total** |
|------------|-----------|-------|----------|--------|-----------|--------------|---------------|
| mechanical | 1 | 22 | - | 10 | 3 | - | **36** |
| analytical | 35 | - | 36 | 15 | 9 | - | **95** |
| judgment | 2 | - | 1 | 11 | - | - | **14** |
| unclassified | - | - | - | - | - | 28 | **28** |
| **Col Total** | **38** | **22** | **37** | **36** | **12** | **28** | **173** |
