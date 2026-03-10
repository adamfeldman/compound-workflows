---
title: "PAL MCP Server: Adding Missing Models via Config Override + Red-Teaming Strategy"
type: solution
category: plugin-infrastructure
date: 2026-03-09
tags: [pal-mcp, model-config, openai, gemini, mcp-servers, red-teaming, model-selection]
related_beads: []
---

# PAL MCP Server: Adding Missing Models via Config Override + Red-Teaming Strategy

## Problem

PAL MCP server (BeehiveInnovations/pal-mcp-server) ships a static model roster in `conf/openai_models.json` and `conf/gemini_models.json`. The maintainers hadn't added several models that are already available in their respective APIs:

- **`gpt-5.2-codex`** (OpenAI) — released after gpt-5.1-codex, available via Responses API
- **`gemini-3.1-pro-preview`** (Google) — released Feb 19, 2026, replaces `gemini-3-pro-preview` which was deprecated and shut down March 9, 2026

Additionally, PAL runs via `uvx --from git+https://...` so its config files live in the uv cache at `~/.cache/uv/git-v0/checkouts/...` and get wiped on re-fetch. Editing them directly is not durable.

## Solution

### Architecture

PAL supports config overrides via environment variables:
- `OPENAI_MODELS_CONFIG_PATH` — absolute path to a custom `openai_models.json`
- `GEMINI_MODELS_CONFIG_PATH` — absolute path to a custom `gemini_models.json`

These env vars are injected through the PAL server's `env` block in `~/.claude.json` (Claude Code's global MCP server configuration).

### Why Not `custom_models.json`?

The initial instinct was to use PAL's `conf/custom_models.json` — it seems designed for user additions. But PAL's provider routing reveals the problem:

> **Provider Priority Order:**
> 1. Native APIs (Google, OpenAI) — if API keys are available
> 2. **Custom endpoints — for models declared in `conf/custom_models.json`** (requires `CUSTOM_API_URL`)
> 3. OpenRouter — catch-all for cloud models

`custom_models.json` entries get routed through `CUSTOM_API_URL` (Ollama, vLLM, etc.), NOT through OpenAI's native API. Putting `gpt-5.2-codex` there would try to hit `localhost:11434`, not `api.openai.com`. Models must live in the provider-specific config file to hit the correct API endpoint.

### Files Created

**`~/.config/pal/openai_models.json`**
- Copied all 13 original models from PAL's upstream `conf/openai_models.json`
- Added `gpt-5.2-codex` (intelligence_score: 20, use_openai_response_api: true, default_reasoning_effort: high, allow_code_generation: true)
- Moved `codex` alias from old `gpt-5-codex` to `gpt-5.2-codex` so `codex` always means the latest
- User later also added `gpt-5.4` and `gpt-5.4-pro` entries

**`~/.config/pal/gemini_models.json`**
- Copied all 5 original models from PAL's upstream `conf/gemini_models.json`
- Added `gemini-3.1-pro-preview` (intelligence_score: 19, allow_code_generation: true)
- Moved `pro` and `gemini-pro` aliases from deprecated `gemini-3-pro-preview` to `gemini-3.1-pro-preview`
- Retained `gemini3` alias on old 3.0 model for backward compatibility

### Files Modified

**`~/.claude.json`** — Added two env vars to the `mcpServers.pal.env` block:
```json
"OPENAI_MODELS_CONFIG_PATH": "/Users/adamf/.config/pal/openai_models.json",
"GEMINI_MODELS_CONFIG_PATH": "/Users/adamf/.config/pal/gemini_models.json"
```

### Key Design Decisions

1. **`~/.config/pal/` as the config home** — Outside the uv cache, survives `uvx` re-fetches. Standard XDG config location.
2. **Full copy, not patch** — Each custom JSON contains ALL models (not just additions). PAL loads the override as a complete replacement, not a merge.
3. **Alias management** — `codex` and `pro` aliases point to the newest models. Version-specific aliases (`codex-5.1`, `gemini3`) still work for explicit selection.

## Verification

After restarting Claude Code, `listmodels` confirmed:
- `gpt-5.2-codex` appears with aliases `codex`, `codex-5.2`, `gpt5.2-codex`
- `gemini-3.1-pro-preview` appears with aliases `pro`, `gemini-pro`, `gemini-3.1`, `gemini3.1`
- Total available models increased from 59 to 65+

## Quick Alias Reference

Shortest aliases for the top-tier models after all changes:

| Alias | Resolves To | Use Case |
|-------|-------------|----------|
| `codex` | `gpt-5.2-codex` | Best coding model (OpenAI) |
| `codex-5.1` | `gpt-5.1-codex` | Coding, ~30% cheaper |
| `gpt5.2` | `gpt-5.2` | OpenAI flagship general |
| `gpt5-pro` | `gpt-5.2-pro` | Max OpenAI capability (272K output) |
| `pro` | `gemini-3.1-pro-preview` | Best Gemini model |
| `flash` | `gemini-2.5-flash` | Fast/cheap Gemini |

---

## Red-Teaming: Model Comparison Research

### gpt-5.1-codex vs gpt-5.2 (General Comparison)

GPT-5.2 is the successor to the GPT-5.1 generation. Key improvements:
- **Long-horizon work** — better context compaction, doesn't lose track during large refactors/migrations
- **Vision** — more accurately interprets screenshots, diagrams, UI mockups
- **Tool calling** — more reliable for agentic workflows
- **Factuality** — fewer hallucinations
- **Cybersecurity** — significantly stronger
- **SWE-Bench Pro & Terminal-Bench 2.0** — state-of-the-art scores
- **Cost** — ~30% more expensive than 5.1-Codex

GPT-5.2-Codex specifically combines 5.2's improvements with the Codex coding specialization (Responses API, agentic focus).

### Benchmarks: gpt5.2 vs gpt5-pro vs o3pro

| Benchmark | `gpt5.2` ($1.75/$14) | `gpt5-pro` ($21/$168) | `o3pro` ($20/$80) |
|-----------|----------------------|----------------------|-------------------|
| **GPQA Diamond** (science) | ~90.3% | 93.2% | ~88%* |
| **AIME 2025** (math) | High | 100% | ~96%* |
| **FrontierMath** (hard math) | — | 40.3% | ~25%* |
| **ARC-AGI-1** (reasoning) | — | 90%+ | 87% |
| **ARC-AGI-2** (harder) | ~52.9% | 54.2% | — |
| **SWE-Bench** (coding) | 80.0% | 55.6%** | — |
| **Context window** | 400K | 400K | 200K |
| **Max output** | 128K | 272K | 65K |

*o3-pro benchmarks are from mid-2025; direct comparisons are approximate.
**SWE-Bench Pro (harder subset), not standard SWE-Bench.

### Cost Per Query (est. ~5K input, ~10K output tokens)

| Model | Cost/Query | Relative |
|-------|-----------|----------|
| `gpt5.2` | ~$0.15 | 1x (baseline) |
| `o3pro` | ~$0.90 | 6x |
| `gpt5-pro` | ~$1.78 | 12x |

### Model Selection by Red-Team Category

**Code/Security Red-Teaming** (finding vulns in code):

| Alias | Why |
|-------|-----|
| `codex` (`gpt-5.2-codex`) | Purpose-built for code, best at tracing execution paths and spotting exploitable patterns |
| `gpt5-pro` | 272K output — can produce exhaustive attack chains and detailed exploit writeups |

**Reasoning/Logic Red-Teaming** (stress-testing arguments, theses, business assumptions):

| Alias | Why |
|-------|-----|
| `o3pro` | Strongest pure reasoning — good at finding logical flaws and edge cases |
| `gpt5-pro` | Deep thinking + massive output for comprehensive adversarial analysis |
| `pro` (Gemini 3.1) | 1M context — can hold an entire thesis/document and poke holes across it |

**Adversarial/Creative Red-Teaming** (finding weird failure modes, unexpected attack surfaces):

| Alias | Why |
|-------|-----|
| `pro` (Gemini 3.1) | Different training data/perspective than OpenAI models — finds things they miss |
| `gpt5.2` | Good balance of creativity and reasoning |

**Overall recommendation:** Use `gpt5.2` as the primary workhorse (90%+ reasoning benchmarks at 1/12th the cost of pro). Reserve `gpt5-pro` for final-pass sweeps. `o3pro` is hard to justify now — benchmarks below gpt5.2 on most tasks, half the context window, and more expensive. Its one edge: architecturally different reasoning style (chain-of-thought specialist) may catch things the GPT-5.x family misses.

The real power move is cross-family diversity: `gpt5.2` vs `pro` (Gemini 3.1) catches more blind spots than any single model family.

---

## Red-Teaming: Temperature Strategy

### Temperature by Use Case

| Use Case | Temp | Why |
|----------|------|-----|
| Finding logical flaws in a thesis | 0.3–0.5 | Rigorous, focused reasoning — not creative hallucinations |
| Generating diverse attack angles | 0.7–0.9 | Higher diversity surfaces unexpected vectors |
| Brainstorming failure modes | 0.9–1.1 | Maximize creative coverage, filter junk after |
| Final validation pass | 0.0–0.2 | Deterministic — model's highest-confidence critique |

Research finding: optimal temperature of ~1.3 maximizes creativity for medium/large models, but coherence degrades above that. For red-teaming, the sweet spot is 0.7–0.9 for exploration (creative but still coherent) and 0.0–0.2 for validation.

### Model-Specific Temperature Constraints

Not all models accept temperature:

| Model | Temp Supported? | Notes |
|-------|----------------|-------|
| `gpt5.2` | Yes (fixed constraint) | Accepts temp but reasoning effort matters more |
| `gpt5-pro` | Yes (fixed constraint) | Same — reasoning effort is the real lever |
| `o3pro` | **No** | Doesn't accept temperature at all |
| `pro` (Gemini 3.1) | Yes | Standard temp range works |

### Key Insight: Reasoning Effort > Temperature

For GPT-5.x models, `reasoning_effort` (low/medium/high/xhigh) is a bigger lever than temperature for critique quality. Temperature affects surface-level token sampling (which words get picked). Reasoning effort controls how deeply the model thinks before answering — the length and depth of its internal chain-of-thought.

**Temperature controls breadth. Reasoning effort controls depth.** For red-teaming you want both — wide exploration followed by deep validation.

---

## Red-Teaming: PAL Built-In Tools vs Raw Chat Calls

### PAL's Relevant Tools

| Tool | What It Does | Default Temp | Default Thinking |
|------|-------------|-------------|-----------------|
| **`consensus`** | Multi-model debate with stance assignment (for/against/neutral), automatic synthesis | 0.2 | medium (8,192 tokens) |
| **`challenge`** | Wraps statement with system-level instructions forcing critical thinking instead of agreement | — | — |
| **`thinkdeep`** | Two-stage: external model reasons deeply, then Claude critically evaluates that reasoning | 0.7 | high (16,384 tokens) |
| **`secaudit`** | Structured security audit (OWASP Top 10) | — | — |

### Where PAL's Tools Win

**`consensus`** handles multi-model adversarial debate with real structure:
- Stance assignment is formalized (not just "please argue against this" in a prompt)
- Sequential processing avoids MCP protocol issues
- Automatic synthesis step that weighs perspectives
- Continuation support — build on a previous debate round

**`challenge`** solves the sycophancy problem. When you red-team via raw chat, the model still softens its punches. `challenge` injects system-level framing that overrides the tendency to agree. There's no way to replicate this with a plain chat call.

**`thinkdeep`'s two-stage evaluation** is genuinely clever. External model reasons deeply, then Claude critically evaluates *that* reasoning — identifying practical risks, trade-offs, and context the first model missed. This adversarial chain is something you'd have to manually orchestrate with raw chat.

### Where Raw Chat Wins

- **Temperature control** — consensus locks you at 0.2, thinkdeep at 0.7. For a high-temp divergent brainstorm pass (0.8–1.0), you need raw chat.
- **Reasoning effort tuning** — PAL's tools expose `thinking_mode` (Gemini's equivalent) but OpenAI reasoning effort is less prominent. Raw chat lets you explicitly set `reasoning_effort: "xhigh"`.
- **Cost management** — PAL's tools don't surface cost. You could accidentally burn through gpt5-pro tokens on exploratory passes where gpt5.2 would've been fine.
- **Single-model deep dives** — if you just want one model's unfiltered take without synthesis overhead.

### Honest Self-Assessment: Initial Manual Approach vs PAL's Tools

| What I Initially Recommended | What PAL Already Does Better |
|------------------------------|------------------------------|
| "Run 3-4 passes at different angles" | `consensus` does this systematically with stance steering instead of hoping prompt variation gives diversity |
| "Cross-pollinate with Gemini" (mentioned as step 3, buried) | `consensus` makes cross-family debate a first-class pattern |
| Multi-pass manual orchestration | `thinkdeep` chains passes with built-in adversarial review |
| No anti-sycophancy strategy | `challenge` solves it at the system level |

Things I flagged that PAL's tools don't address:
- Temperature as a deliberate exploration lever (PAL uses conservative defaults)
- Reasoning effort as the primary quality lever for GPT-5.x
- Cost-per-query awareness

---

## Red-Teaming: Recommended Workflow

### Should You Adjust PAL's Defaults?

**No. Override per-call, not globally.**

PAL's conservative defaults (consensus at temp 0.2, thinkdeep at 0.7, medium reasoning) are correct for 90% of usage — code review, analysis, debugging. Red-teaming is the exception. Shifting global defaults to serve the exception would hurt the common case.

Instead:
- Pass `temperature: 0.7` explicitly to consensus when red-teaming
- Specify the model and thinking mode explicitly: `"Think deeper about X with gpt5-pro using max thinking mode"`
- The model configs (`default_reasoning_effort: "high"` for gpt-5.2-codex, `"medium"` for gpt-5.2) are reasonable defaults — push to xhigh per-call when needed

### Three-Step Red-Team Protocol

**Step 1: Divergent exploration** (consensus)
```
Use consensus with gpt5.2 taking a "for" stance and pro taking an
"against" stance with temperature 0.7 to evaluate:

[Your thesis statement]

Focus on: assumptions that could be wrong in 3-5 years,
market dynamics that could invalidate the thesis, and
scenarios where I lose >50% of deployed capital.
```

**Step 2: Deep validation** (thinkdeep)
```
Think deeper about the strongest counterargument from the
consensus above with gpt5-pro using max thinking mode
```

**Step 3: Conviction test** (challenge)
```
challenge [State your remaining conviction after steps 1-2]
```

This uses PAL's orchestration instead of manually managing models, temperatures, and prompt engineering. The tools handle adversarial framing. Your job is asking the right questions.

---

## Maintenance Notes

- When PAL upstream adds these models, this override becomes redundant. Check periodically with `gh api repos/BeehiveInnovations/pal-mcp-server/contents/conf/openai_models.json` to see if they've caught up.
- GPT-5.3-Codex is NOT yet available via the OpenAI API (only ChatGPT-authenticated Codex sessions). Add it to the config when API access opens.
- `gemini-3.1-pro-preview-customtools` variant exists (better at prioritizing custom tools with a mix of bash and tools). Can be added later if needed.
- The custom configs need manual updates when new models release. This is the tradeoff of overriding vs using upstream defaults.

## Sources

- [Introducing GPT-5.2-Codex | OpenAI](https://openai.com/index/introducing-gpt-5-2-codex/)
- [GPT-5.2 Launch Analysis | LLM Stats](https://llm-stats.com/blog/research/gpt-5-2-launch)
- [GPT-5.2 Pro Pricing | PricePerToken](https://pricepertoken.com/pricing-page/model/openai-gpt-5.2-pro)
- [OpenAI API Pricing](https://developers.openai.com/api/docs/pricing)
- [Gemini API Changelog](https://ai.google.dev/gemini-api/docs/changelog)
- [LLM Temperature Guide | Promptfoo](https://www.promptfoo.dev/docs/guides/evaluate-llm-temperature/)
- [Temperature Impact on LLMs | arXiv](https://arxiv.org/html/2506.07295v1)
- [PAL Consensus Tool Docs](https://github.com/BeehiveInnovations/pal-mcp-server/blob/main/docs/tools/consensus.md)
- [PAL Challenge Tool Docs](https://github.com/BeehiveInnovations/pal-mcp-server/blob/main/docs/tools/challenge.md)
- [PAL ThinkDeep Tool Docs](https://github.com/BeehiveInnovations/pal-mcp-server/blob/main/docs/tools/thinkdeep.md)
- [PAL Custom Models Docs](https://github.com/BeehiveInnovations/pal-mcp-server/blob/main/docs/custom_models.md)
- [Claude Code MCP Docs](https://code.claude.com/docs/en/mcp)
