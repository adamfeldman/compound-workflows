# Red Team Critique — GPT-5.2

## CRITICAL

### 1. Agent Resolution is "Unpredictable" — Asserted, Not Demonstrated
> "Agent resolution with duplicates would be unpredictable."

This is stated as a blocker but not proven. If resolution is deterministic (plugin load order, full path), the premise collapses and "don't install both" is a product choice, not a technical necessity.

### 2. Version 1.1.0 is Wrong — This is Breaking
> "Version — 1.1.0 (MINOR — adding agents/skills)"

Renaming agents, removing compound-engineering dependency, replacing setup command content — these break external references, saved workflows, user scripts. This is 2.0.0.

### 3. Licensing / Attribution Risk
> "A complete fork of compound-engineering's agents and skills"

No mention of license compatibility, required notices, or contributor attribution. Renaming contributor-named agents could violate attribution requirements.

### 4. Fork Drift — No Sync Strategy
> "A complete fork... fully self-contained."

Upstream improvements won't reach you automatically. No backport process or provenance tracking mentioned.

## SERIOUS

### 5. Examples Anchor LLM Outputs
> "Examples kept as-is — Company-specific examples ... are illustrative"

No evidence users will understand examples as illustrative. In prompt UX, examples regularly get misinterpreted as required structures.

### 6. "Eliminates Confusion Entirely" Contradicts "Don't Install Both"
> "Forking ... eliminates this confusion entirely." / "Document 'don't install both'"

If confusion is eliminated, why the warning? Confusion is reduced only if users comply.

### 7. Dropping Figma Agents While Porting agent-browser
> "Dropped ... 3 design/Figma agents (require Figma MCP + agent-browser)"

But agent-browser IS being ported as a skill. The real blocker is Figma MCP, not agent-browser. As written, it's inconsistent.

### 8. "One Plugin, Full Power" Overstates Reality
> "One plugin, full power"

Some skills require GEMINI_API_KEY, browser automation requires additional setup. "Full power" is conditional on external dependencies.

### 9. Namespace Alternatives Dismissed Too Quickly
> "Fork over dependency"

Missing alternatives: command aliasing, proxy commands, vendoring with automated sync scripts.

### 10. No Migration Path for Renamed Agents
> "Renamed to descriptive names"

No aliases, deprecated stubs, or migration timeline for the 3 renamed agents.

## MINOR

### 11. Shipping Unreferenced Agents Contradicts "Clean" Goal
> "Ship clean, no dead references" / "not referenced, useful for..."

Tension between cleanliness and shipping things current commands don't use.
