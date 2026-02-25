# Compound Workflows Plugin Development

## Versioning

Every change MUST update all three files:

1. **`.claude-plugin/plugin.json`** — Bump version (semver)
2. **`CHANGELOG.md`** — Document changes
3. **`README.md`** — Verify component counts and tables

### Version Rules

- **MAJOR** (2.0.0): Breaking changes to command interfaces or directory conventions
- **MINOR** (1.1.0): New commands, agents, or skills
- **PATCH** (1.0.1): Bug fixes, doc updates, prompt improvements

Also update the marketplace.json version at the repo root.

## Directory Structure

```
agents/
└── research/           # Research and knowledge agents

commands/
└── compound-workflows/ # All slash commands (namespaced)

skills/
└── disk-persist-agents/ # Reusable patterns
```

## Command Conventions

- All commands use `compound-workflows:` prefix in YAML `name:` field
- Commands reference agents by name with inline role descriptions for graceful fallback
- Commands detect beads/PAL at runtime and adapt behavior
- Phase gates enforce resolution of open questions before proceeding
- Research outputs persist to `.workflows/` directories

## Testing Changes

1. Install the plugin in a test project
2. Run `/compound-workflows:setup` to verify detection
3. Test each modified command end-to-end
4. Verify graceful degradation without beads/PAL/compound-engineering
