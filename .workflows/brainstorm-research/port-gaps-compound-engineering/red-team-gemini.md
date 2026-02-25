# Red Team Critique — Gemini 3 Pro

## CRITICAL

### 1. Fork Drift / Maintenance Burden
> "A complete fork... making it fully self-contained."

Severing the dependency guarantees compound-workflows immediately begins to rot relative to upstream. If critical prompt improvements, security fixes, or methodology updates land in compound-engineering, this plugin won't receive them. No sync mechanism or "upstream first" policy is proposed.

## SERIOUS

### 2. Company-Specific Examples Bias LLM Outputs
> "Company-specific examples... are illustrative, not prescriptive."

LLMs are few-shot learners. Examples containing "BriefSystem", "EmailProcessing" will statistically bias model outputs toward similar patterns. "Faster to port" is a weak argument for degrading inference quality.

### 3. "Don't Install Both" is Documentation, Not Design
> "Document that compound-workflows supersedes compound-engineering."

Relying on documentation to prevent technical conflicts is a failure of design. Users rarely read installation fine print and will install both plugins.

### 4. Hardcoded Model Aliases May Not Resolve
> "Model fields — Keep haiku/inherit as-is"

Assumes marketplace consumers have access to the same model aliases. Users on local LLM proxies or Azure OpenAI won't map "haiku" correctly.

## MINOR

### 5. Setup Skill vs Command Technical Mismatch
> "Replace command with skill approach"

Commands run with different context than skills. Can a skill reliably modify config files if it's running inside an agent's execution sandbox?

### 6. Namespace Alternative Dismissed Too Quickly
> "Requiring it means users see both sets in the slash command picker."

Why not alias the commands (e.g., `/cw-brainstorm`) while keeping compound-engineering as a dependency? This would solve drift entirely.
