#!/usr/bin/env python3
"""
Extract empirical workflow timing data from Claude Code JSONL session logs.

Reads all .jsonl files from the Claude Code projects directory, extracts:
- Session metadata (duration, entry counts)
- Workflow phase timings (Skill invocations)
- Agent/Task dispatch durations
- Tool call distributions per phase
- User interaction patterns
- Compaction events
- Git commit counts
- Active vs idle time breakdowns (idle = gaps >= 5 minutes)
- Non-workflow segment categorization with subcategories
- Time-windowed per-bead attribution (replaces session-level attribution)
- Phase-to-bead mapping via skill args
- Proportional splitting for multi-bead sessions
- Token-per-phase aggregation
- Concurrent session detection
- Estimate vs actual comparison for closed beads (using windowed attribution)
- Deduplicated active time across concurrent sessions (minute-level)
- Proportional tool-call time allocation per segment/phase
- AskUserQuestion categorization and time-to-response
- Orchestration overhead analysis (bd vs productive tool calls)
- Headline metrics (cost/hour, overhead ratio, automation ratio, etc.)

Outputs:
- raw-observations.jsonl: One JSON object per observation
- summary.md: Human-readable statistics with tables
"""

import json
import os
import sys
import re
import glob
import statistics
import subprocess
from datetime import datetime, timezone, timedelta
from collections import defaultdict, Counter
from pathlib import Path

# --- Configuration ---
JSONL_DIR = os.path.expanduser(
    "~/.claude/projects/-Users-adamf-Dev-compound-workflows-marketplace"
)
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
RAW_OUTPUT = os.path.join(SCRIPT_DIR, "raw-observations.jsonl")
SUMMARY_OUTPUT = os.path.join(SCRIPT_DIR, "summary.md")

# Idle threshold: gaps >= this many seconds are considered idle
# Empirically determined: 99.6% of inter-entry gaps are under 5 minutes.
# The 5-10m bucket has only 80/56405 gaps. Clear bimodal distribution.
IDLE_THRESHOLD_SECONDS = 300

# Bead attribution window: time before first and after last bead reference
# within a session to attribute to that bead (in seconds).
# Tightened from 300s (5min) to 120s (2min) to reduce inflation from
# ambient bead references during routine triage.
BEAD_WINDOW_BEFORE_SECONDS = 120  # 2 minutes
BEAD_WINDOW_AFTER_SECONDS = 120   # 2 minutes

# Skill name -> phase mapping
SKILL_PHASE_MAP = {
    "brainstorm": "brainstorm",
    "plan": "plan",
    "deepen-plan": "deepen-plan",
    "deepen": "deepen-plan",
    "work": "work",
    "do-work": "work",
    "review": "review",
    "compact-prep": "compact-prep",
    "do-compact-prep": "compact-prep",
    "do-brainstorm": "brainstorm",
    "do-plan": "plan",
    "do-deepen-plan": "deepen-plan",
    "do-review": "review",
    "do-compound": "compound",
    "abandon": "abandon",
    "do-abandon": "abandon",
    "setup": "setup",
    "do-setup": "setup",
    "recover": "recover",
    "plugin-changes-qa": "qa",
    "do-plugin-changes-qa": "qa",
    "compound": "compound",
}

# Correction patterns
CORRECTION_PATTERNS = re.compile(
    r"\b(no[,.]?\s|not that|instead\b|don't|dont|do not|wrong|"
    r"that's not|thats not|actually\b|wait\b|stop\b|undo|revert|"
    r"go back|try again|that was wrong)",
    re.IGNORECASE,
)

# Usage tag patterns - two formats
# Format 1: <usage>total_tokens: N\ntool_uses: N\nduration_ms: N</usage>
# Format 2: <usage><total_tokens>N</total_tokens><tool_uses>N</tool_uses><duration_ms>N</duration_ms></usage>
# --- Stats YAML directory ---
# Stats YAML files live in .workflows/stats/ — either in the current repo root
# or in the main worktree (worktrees have separate .workflows/ directories).
def find_stats_yaml_dir():
    """Locate the .workflows/stats/ directory.

    Tries the current repo root first, then the main worktree.
    Returns the directory path, or None if not found.
    """
    repo_root = os.path.dirname(os.path.dirname(SCRIPT_DIR))
    local_stats = os.path.join(repo_root, ".workflows", "stats")
    if os.path.isdir(local_stats):
        return local_stats

    # Try main worktree via git
    try:
        result = subprocess.run(
            ["git", "worktree", "list", "--porcelain"],
            capture_output=True, text=True, timeout=5,
            cwd=repo_root,
        )
        for line in result.stdout.splitlines():
            if line.startswith("worktree "):
                main_root = line[len("worktree "):]
                main_stats = os.path.join(main_root, ".workflows", "stats")
                if os.path.isdir(main_stats):
                    return main_stats
    except Exception:
        pass
    return None


def parse_simple_yaml_docs(filepath):
    """Parse a multi-document YAML file with flat key-value pairs.

    Each document is separated by '---'. Values are auto-typed:
    integers, floats, null/true/false, or strings (with optional quotes stripped).
    Returns a list of dicts, one per document.
    """
    docs = []
    current = {}
    with open(filepath, "r") as f:
        for raw_line in f:
            line = raw_line.strip()
            if line == "---":
                if current:
                    docs.append(current)
                    current = {}
                continue
            if not line or line.startswith("#"):
                continue
            # Split on first ': ' (YAML key-value)
            colon_idx = line.find(": ")
            if colon_idx == -1:
                # Handle 'key:' with empty value
                if line.endswith(":"):
                    current[line[:-1].strip()] = None
                continue
            key = line[:colon_idx].strip()
            val_str = line[colon_idx + 2:].strip()
            # Strip surrounding quotes
            if len(val_str) >= 2 and val_str[0] == val_str[-1] and val_str[0] in ('"', "'"):
                val_str = val_str[1:-1]
                current[key] = val_str
                continue
            # Auto-type
            if val_str == "null":
                current[key] = None
            elif val_str == "true":
                current[key] = True
            elif val_str == "false":
                current[key] = False
            else:
                # Try integer
                try:
                    current[key] = int(val_str)
                    continue
                except ValueError:
                    pass
                # Try float
                try:
                    current[key] = float(val_str)
                    continue
                except ValueError:
                    pass
                current[key] = val_str
    # Last document (no trailing ---)
    if current:
        docs.append(current)
    return docs


def load_stats_yaml_entries():
    """Load all agent dispatch entries from .workflows/stats/*.yaml files.

    Skips ccusage-snapshot documents (identified by type: ccusage-snapshot).
    Returns a list of dicts with fields: command, bead, stem, agent, step,
    model, run_id, tokens, tools, duration_ms, timestamp, status,
    complexity, output_type, source_file.
    """
    stats_dir = find_stats_yaml_dir()
    if not stats_dir:
        print("  WARNING: Could not find .workflows/stats/ directory", file=sys.stderr)
        return []

    yaml_files = sorted(glob.glob(os.path.join(stats_dir, "*.yaml")))
    print(f"  Found {len(yaml_files)} stats YAML files in {stats_dir}", file=sys.stderr)

    entries = []
    skipped_ccusage = 0
    parse_errors = 0

    for filepath in yaml_files:
        basename = os.path.basename(filepath)
        try:
            docs = parse_simple_yaml_docs(filepath)
        except Exception as e:
            print(f"    WARNING: Could not parse {basename}: {e}", file=sys.stderr)
            parse_errors += 1
            continue

        for doc in docs:
            # Skip ccusage-snapshot documents
            if doc.get("type") == "ccusage-snapshot":
                skipped_ccusage += 1
                continue

            # Require at least command and duration_ms for a valid agent dispatch
            if "command" not in doc or "duration_ms" not in doc:
                continue

            doc["source_file"] = basename
            entries.append(doc)

    print(f"  Loaded {len(entries)} agent dispatch entries "
          f"(skipped {skipped_ccusage} ccusage snapshots, {parse_errors} parse errors)",
          file=sys.stderr)
    return entries


def compute_stats_step_timing(stats_entries, closed_bead_estimates):
    """Compute per-command and per-step duration statistics from stats YAML entries.

    Groups by command (workflow type), then by step within each command.
    Computes median, P90, mean duration for each grouping.
    Also matches against bead estimates for estimate-vs-actual comparison.

    Args:
        stats_entries: list of dicts from load_stats_yaml_entries()
        closed_bead_estimates: dict of bead_id -> {title, estimated_minutes}

    Returns:
        dict with:
        - by_command: {command: {n, durations_ms stats, steps: {step: stats}}}
        - by_agent: {agent: {n, duration stats}}
        - estimate_vs_actual: list of {bead, estimated_minutes, actual_total_ms, step_count}
        - records: list of stats_step_timing record dicts for raw output
    """
    from collections import defaultdict

    # Group by command
    by_command = defaultdict(list)
    by_agent = defaultdict(list)
    by_command_step = defaultdict(lambda: defaultdict(list))
    by_bead = defaultdict(list)

    for entry in stats_entries:
        cmd = entry.get("command", "unknown")
        step = entry.get("step", "unknown")
        agent = entry.get("agent", "unknown")
        duration_ms = entry.get("duration_ms") or 0
        bead = entry.get("bead")
        tokens = entry.get("tokens") or 0

        if duration_ms > 0:
            by_command[cmd].append(duration_ms)
            by_agent[agent].append(duration_ms)
            by_command_step[cmd][step].append(duration_ms)

        if bead and duration_ms > 0:
            bead_str = str(bead)
            by_bead[bead_str].append({
                "duration_ms": duration_ms,
                "tokens": tokens,
                "command": cmd,
                "step": step,
            })

    # Compute per-command stats
    command_stats = {}
    for cmd, durations in sorted(by_command.items()):
        dur_minutes = [d / 60000.0 for d in durations]
        cmd_stat = compute_stats(dur_minutes)

        # Per-step breakdown within this command
        step_stats = {}
        for step, step_durations in sorted(by_command_step[cmd].items()):
            step_minutes = [d / 60000.0 for d in step_durations]
            step_stats[step] = compute_stats(step_minutes)

        command_stats[cmd] = {
            **cmd_stat,
            "total_duration_ms": sum(durations),
            "total_duration_min": round(sum(durations) / 60000.0, 2),
            "steps": step_stats,
        }

    # Compute per-agent stats
    agent_stats = {}
    for agent, durations in sorted(by_agent.items(), key=lambda x: len(x[1]), reverse=True):
        dur_minutes = [d / 60000.0 for d in durations]
        agent_stats[agent] = compute_stats(dur_minutes)

    # Estimate vs actual from bead data
    estimate_vs_actual = []
    for bead_id, dispatches in sorted(by_bead.items()):
        total_ms = sum(d["duration_ms"] for d in dispatches)
        total_tokens = sum(d["tokens"] for d in dispatches)
        # Look up estimate
        est_data = closed_bead_estimates.get(bead_id)
        if est_data:
            estimated_min = est_data["estimated_minutes"]
            actual_min = total_ms / 60000.0
            ratio = actual_min / estimated_min if estimated_min > 0 else None
            estimate_vs_actual.append({
                "bead": bead_id,
                "title": est_data["title"],
                "estimated_minutes": estimated_min,
                "actual_dispatch_minutes": round(actual_min, 2),
                "actual_dispatch_ms": total_ms,
                "dispatch_count": len(dispatches),
                "total_tokens": total_tokens,
                "ratio": round(ratio, 2) if ratio is not None else None,
                "commands": list(set(d["command"] for d in dispatches)),
            })

    # Build records for raw output
    records = []
    for cmd, stat in command_stats.items():
        record = {
            "record_type": "stats_step_timing",
            "command": cmd,
            "n": stat["n"],
            "median_minutes": stat.get("median"),
            "mean_minutes": stat.get("mean"),
            "p90_minutes": stat.get("p90"),
            "min_minutes": stat.get("min"),
            "max_minutes": stat.get("max"),
            "total_duration_min": stat.get("total_duration_min"),
        }
        records.append(record)

    for entry in estimate_vs_actual:
        records.append({
            "record_type": "stats_estimate_vs_actual",
            **entry,
        })

    return {
        "by_command": command_stats,
        "by_agent": agent_stats,
        "estimate_vs_actual": estimate_vs_actual,
        "records": records,
        "total_entries": len(stats_entries),
    }


USAGE_KV_RE = re.compile(
    r"<usage>\s*total_tokens:\s*(\d+)\s*\n\s*tool_uses:\s*(\d+)\s*\n\s*duration_ms:\s*(\d+)\s*</usage>",
    re.DOTALL,
)
USAGE_XML_RE = re.compile(
    r"<usage>\s*<total_tokens>(\d+)</total_tokens>\s*<tool_uses>(\d+)</tool_uses>\s*<duration_ms>(\d+)</duration_ms>\s*</usage>",
    re.DOTALL,
)

# --- Model pricing (per million tokens) ---
# Source: Anthropic pricing page, March 2026
# Format: {model_prefix: (input, cache_creation, cache_read, output)}
MODEL_PRICING = {
    "claude-opus-4":   (15.00, 3.75, 1.875, 75.00),
    "claude-sonnet-4": (3.00, 3.75, 0.30, 15.00),
    "claude-haiku-3":  (0.25, 0.30, 0.03, 1.25),
}

def get_model_pricing(model_name):
    """Return (input, cache_creation, cache_read, output) rates per million tokens.

    Matches model_name against known prefixes (e.g. 'claude-opus-4-6' -> 'claude-opus-4').
    Returns (0,0,0,0) for unknown/<synthetic> models.
    """
    if not model_name or model_name.startswith("<"):
        return (0.0, 0.0, 0.0, 0.0)
    for prefix, rates in MODEL_PRICING.items():
        if model_name.startswith(prefix):
            return rates
    return (0.0, 0.0, 0.0, 0.0)


def compute_request_cost(usage, model_name):
    """Compute dollar cost for a single API request given usage dict and model name.

    usage must have: input_tokens, cache_creation_input_tokens,
                     cache_read_input_tokens, output_tokens
    Returns cost in USD (float).
    """
    rates = get_model_pricing(model_name)
    input_cost = usage.get("input_tokens", 0) * rates[0] / 1_000_000
    cache_create_cost = usage.get("cache_creation_input_tokens", 0) * rates[1] / 1_000_000
    cache_read_cost = usage.get("cache_read_input_tokens", 0) * rates[2] / 1_000_000
    output_cost = usage.get("output_tokens", 0) * rates[3] / 1_000_000
    return input_cost + cache_create_cost + cache_read_cost + output_cost


# Configuration file patterns for "configuration" segment classification
CONFIG_PATTERNS = re.compile(
    r"(CLAUDE\.md|AGENTS\.md|settings\.json|memory/|\.claude/|compound-workflows\.md|compound-workflows\.local\.md)",
    re.IGNORECASE,
)

# AskUserQuestion category patterns
ASKUSER_CATEGORIES = {
    "triage": re.compile(
        r"\b(options?|choices?|select|pick|choose|which|red\s*team\s*findings?)\b",
        re.IGNORECASE,
    ),
    "confirmation": re.compile(
        r"\b(proceed|apply|commit|continue|ready|approve|go\s*ahead)\b",
        re.IGNORECASE,
    ),
    "design-decision": re.compile(
        r"\b(architecture|pattern|design|approach|structure|interface)\b",
        re.IGNORECASE,
    ),
    "scope": re.compile(
        r"\b(include|exclude|skip|add|remove|scope|in/out)\b",
        re.IGNORECASE,
    ),
    "diagnosis": re.compile(
        r"\b(why|cause|root|investigate|debug|failing)\b",
        re.IGNORECASE,
    ),
}

# Tool call classification buckets for proportional allocation
TOOL_BUCKET_MAP = {
    "bd": "bd",
    "Edit": "editing",
    "Write": "editing",
    "Read": "reading",
    "Grep": "reading",
    "Glob": "reading",
    "Agent": "agent-dispatch",
    "Task": "agent-dispatch",
    "AskUserQuestion": "user-dialogue",
}
# Everything else falls into "other"

# Bead ID pattern: "compound-workflows-marketplace-XXXX" where XXXX is 2-4 alphanumeric chars
BEAD_FULL_PREFIX = "compound-workflows-marketplace-"
# For bd commands: bd <subcommand> [compound-workflows-marketplace-]<id>
# Captures (subcommand, bead_id) — subcommand used for ambient filtering.
BD_CMD_BEAD_RE = re.compile(
    r"bd\s+(update|show|close|label|ready|blocked|create|search|list|stats)\s+(?:compound-workflows-marketplace-)?([a-z0-9]{2,5})\b"
)
# Ambient bd commands: these don't indicate active work on a specific bead.
# Only direct interaction (show, update, close, create referencing a bead) counts.
BD_AMBIENT_SUBCOMMANDS = {"list", "ready", "stats", "blocked", "search"}
# For git commit messages referencing bead IDs (in the commit message text)
BEAD_IN_COMMIT_RE = re.compile(
    r"compound-workflows-marketplace-([a-z0-9]{2,5})\b"
)
# For user messages: require "bead" prefix or full ID to avoid false positives
BEAD_USER_MSG_RE = re.compile(
    r"(?:bead\s+|compound-workflows-marketplace-)([a-z0-9]{2,5})\b",
    re.IGNORECASE,
)

# BD subcommand extraction
BD_SUBCOMMAND_RE = re.compile(r"^bd\s+(\w+)")

# BD subcommand categories
BD_CREATION_CMDS = {"create"}
BD_TRIAGE_CMDS = {"show", "ready", "list", "search", "blocked", "sql"}
BD_UPDATE_CMDS = {"update", "close", "label"}


def parse_timestamp(ts_str):
    """Parse ISO 8601 timestamp to datetime."""
    if not ts_str:
        return None
    try:
        # Handle Z suffix
        ts_str = ts_str.replace("Z", "+00:00")
        return datetime.fromisoformat(ts_str)
    except (ValueError, TypeError):
        return None


def compute_active_idle(sorted_timestamps, start_ts, end_ts):
    """Compute active and idle time within a time window.

    Args:
        sorted_timestamps: All session timestamps, already sorted ascending.
        start_ts: Window start (inclusive).
        end_ts: Window end (inclusive).

    Returns:
        dict with active_minutes, idle_minutes, idle_gap_count, entry_count
    """
    if not start_ts or not end_ts or start_ts >= end_ts:
        return {
            "active_minutes": 0,
            "idle_minutes": 0,
            "idle_gap_count": 0,
            "entry_count": 0,
        }

    # Filter timestamps within the window using binary search-like approach
    # (sorted_timestamps is already sorted)
    window_ts = []
    for ts in sorted_timestamps:
        if ts < start_ts:
            continue
        if ts > end_ts:
            break
        window_ts.append(ts)

    entry_count = len(window_ts)
    wall_clock_seconds = (end_ts - start_ts).total_seconds()

    if entry_count < 2:
        # Can't compute gaps with fewer than 2 entries
        return {
            "active_minutes": round(wall_clock_seconds / 60.0, 2),
            "idle_minutes": 0,
            "idle_gap_count": 0,
            "entry_count": entry_count,
        }

    # Compute gaps between consecutive timestamps
    idle_seconds = 0.0
    idle_gap_count = 0
    for i in range(1, len(window_ts)):
        gap = (window_ts[i] - window_ts[i - 1]).total_seconds()
        if gap >= IDLE_THRESHOLD_SECONDS:
            idle_seconds += gap
            idle_gap_count += 1

    active_seconds = wall_clock_seconds - idle_seconds
    # Guard against negative active time (shouldn't happen, but be safe)
    if active_seconds < 0:
        active_seconds = 0

    return {
        "active_minutes": round(active_seconds / 60.0, 2),
        "idle_minutes": round(idle_seconds / 60.0, 2),
        "idle_gap_count": idle_gap_count,
        "entry_count": entry_count,
    }


def extract_skill_phase(skill_name):
    """Map a skill invocation name to a workflow phase."""
    if not skill_name:
        return None
    # Strip namespace prefixes
    # e.g. "compound-workflows:compound:plan" -> "plan"
    # e.g. "compound-workflows:do-work" -> "do-work"
    parts = skill_name.split(":")
    short = parts[-1] if parts else skill_name
    # Also try the last two parts joined
    if len(parts) >= 2:
        two_part = parts[-2] + "-" + parts[-1]  # e.g. "do-plan"

    phase = SKILL_PHASE_MAP.get(short)
    if phase:
        return phase

    if len(parts) >= 2:
        phase = SKILL_PHASE_MAP.get(two_part)
        if phase:
            return phase

    # Try full name minus first prefix
    if len(parts) > 1:
        remainder = ":".join(parts[1:])
        for key, val in SKILL_PHASE_MAP.items():
            if key in remainder:
                return val

    return short  # Return the short name as-is if no mapping found


def extract_usage_from_text(text):
    """Extract usage info from text containing <usage> tags."""
    if not text or "<usage>" not in text:
        return None

    # Try KV format first
    m = USAGE_KV_RE.search(text)
    if m:
        return {
            "total_tokens": int(m.group(1)),
            "tool_uses": int(m.group(2)),
            "duration_ms": int(m.group(3)),
        }

    # Try XML format
    m = USAGE_XML_RE.search(text)
    if m:
        return {
            "total_tokens": int(m.group(1)),
            "tool_uses": int(m.group(2)),
            "duration_ms": int(m.group(3)),
        }

    return None


def extract_text_from_content(content):
    """Extract all text from a message content field (string or list)."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        texts = []
        for item in content:
            if isinstance(item, str):
                texts.append(item)
            elif isinstance(item, dict):
                if item.get("type") == "text":
                    texts.append(item.get("text", ""))
                elif item.get("type") == "tool_result":
                    inner = item.get("content", "")
                    texts.append(extract_text_from_content(inner))
        return "\n".join(texts)
    return ""


def classify_segment(tool_counts, user_message_count, bash_commands, wall_clock_minutes=0):
    """Classify a non-workflow segment by its dominant activity.

    Args:
        tool_counts: Counter of tool_name -> count
        user_message_count: number of user messages in this segment
        bash_commands: list of bash command strings in this segment
        wall_clock_minutes: wall-clock duration of this segment (for transition detection)

    Returns:
        tuple of (category, subcategory, bd_subcommand_counts)

    Primary categories:
    - coding: Edit+Write >= 30% of tools
    - light-coding: Edit+Write >= 15% of tools (but < 30%)
      Subcategories: orch-coding, interactive-dev, iterating, plain
    - exploration: Read+Grep+Glob >= 25% of tools (merged from old research+exploration)
    - bead-management: bd commands >= 30% of tools
    - discussion: user messages > 2x tools (or no tools but has messages)
    - configuration: config file patterns >= 30% of tools
    - mixed: no dominant category
      Subcategories: orchestration, interactive, agent-heavy, transition, still-mixed
    """
    total_tools = sum(tool_counts.values())
    bd_subcommand_counts = Counter()

    if total_tools == 0 and user_message_count == 0:
        # No activity — check if it's a transition (very short)
        if wall_clock_minutes < 2:
            return "mixed", "transition", bd_subcommand_counts
        return "mixed", "still-mixed", bd_subcommand_counts

    # Count bd commands and their subcommands
    bd_count = 0
    agent_task_count = tool_counts.get("Agent", 0) + tool_counts.get("Task", 0)
    for cmd in bash_commands:
        cmd_stripped = cmd.strip()
        if cmd_stripped.startswith("bd "):
            bd_count += 1
            m = BD_SUBCOMMAND_RE.match(cmd_stripped)
            if m:
                bd_subcommand_counts[m.group(1)] += 1

    # Check for test/run commands in bash (for light-coding:iterating)
    test_run_count = sum(
        1 for cmd in bash_commands
        if any(kw in cmd for kw in ["pytest", "python3 ", "npm test", "npm run",
                                     "make ", "cargo test", "go test", "bash ",
                                     "sh ", "./"])
    )

    # Check bead-management: bd calls >= 30% of tool calls
    if total_tools > 0 and bd_count / total_tools >= 0.30:
        return "bead-management", None, bd_subcommand_counts

    # Check discussion: user messages > 2x tool calls
    if total_tools > 0 and user_message_count > 2 * total_tools:
        return "discussion", None, bd_subcommand_counts
    if total_tools == 0 and user_message_count > 0:
        return "discussion", None, bd_subcommand_counts

    # Check coding: Edit + Write >= 30% (full coding)
    coding_count = tool_counts.get("Edit", 0) + tool_counts.get("Write", 0)
    if total_tools > 0 and coding_count / total_tools >= 0.30:
        return "coding", None, bd_subcommand_counts

    # Check exploration: Read + Grep + Glob >= 40% (was "research" at 40%,
    # now merged into exploration — both are read-heavy investigation)
    exploration_count = (
        tool_counts.get("Read", 0)
        + tool_counts.get("Grep", 0)
        + tool_counts.get("Glob", 0)
    )
    if total_tools > 0 and exploration_count / total_tools >= 0.40:
        return "exploration", None, bd_subcommand_counts

    # Check configuration: Bash calls with config patterns dominate
    config_bash_count = sum(
        1 for cmd in bash_commands if CONFIG_PATTERNS.search(cmd)
    )
    if total_tools > 0 and config_bash_count / total_tools >= 0.30:
        return "configuration", None, bd_subcommand_counts

    # --- Light-coding with subcategories ---
    # Edit+Write >= 15% (some but not dominant)
    if total_tools > 0 and coding_count / total_tools >= 0.15:
        # Determine light-coding subcategory
        if bd_count > 0:
            subcategory = "orch-coding"
        elif user_message_count > 0 and user_message_count >= coding_count:
            subcategory = "interactive-dev"
        elif test_run_count > 0:
            subcategory = "iterating"
        else:
            subcategory = "plain"
        return "light-coding", subcategory, bd_subcommand_counts

    # Exploration: Read+Grep+Glob >= 25% (softer threshold, was separate "exploration")
    if total_tools > 0 and exploration_count / total_tools >= 0.25:
        return "exploration", None, bd_subcommand_counts

    # Discussion with tools: user messages >= tool calls (softer than 2x)
    if total_tools > 0 and user_message_count >= total_tools:
        return "discussion", None, bd_subcommand_counts

    # --- Mixed with subcategories ---
    # Transition: very short segments between phases
    if wall_clock_minutes < 2:
        return "mixed", "transition", bd_subcommand_counts

    # Orchestration: bd commands + Agent dispatches dominate
    if total_tools > 0 and (bd_count + agent_task_count) / total_tools >= 0.40:
        return "mixed", "orchestration", bd_subcommand_counts

    # Interactive: high user_message ratio
    if total_tools > 0 and user_message_count > 0 and user_message_count / total_tools >= 0.5:
        return "mixed", "interactive", bd_subcommand_counts

    # Agent-heavy: Agent/Task tool calls dominate
    if total_tools > 0 and agent_task_count / total_tools >= 0.30:
        return "mixed", "agent-heavy", bd_subcommand_counts

    return "mixed", "still-mixed", bd_subcommand_counts


def categorize_bd_subcommands(bd_subcommand_counts):
    """Categorize bd subcommand counts into creation/triage/updating/other."""
    result = Counter()
    for subcmd, count in bd_subcommand_counts.items():
        if subcmd in BD_CREATION_CMDS:
            result["creation"] += count
        elif subcmd in BD_TRIAGE_CMDS:
            result["triage"] += count
        elif subcmd in BD_UPDATE_CMDS:
            result["updating"] += count
        else:
            result["other"] += count
    return dict(result)


def extract_bead_ids_from_session(filepath, known_bead_ids):
    """Scan a session file for bead ID references with timestamps.

    Phase 3 upgrade: returns timestamps for each bead reference, enabling
    time-windowed attribution instead of full-session attribution.

    Args:
        filepath: path to the JSONL file
        known_bead_ids: set of known bead short IDs from the database

    Returns:
        tuple of:
        - set of bead short IDs found in this session (for backwards compat)
        - dict of {bead_id: [list of timestamps]} for windowed attribution
        - str: reference type for each bead_id -> {bead_id: set of ref_types}
          where ref_types are 'bd_cmd', 'commit_ref', 'skill_args', 'user_msg'
    """
    found_ids = set()
    bead_timestamps = defaultdict(list)  # bead_id -> [datetime timestamps]
    bead_ref_types = defaultdict(set)    # bead_id -> set of reference type strings

    with open(filepath, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue

            entry_type = entry.get("type")
            ts = parse_timestamp(entry.get("timestamp"))

            if entry_type == "assistant":
                message = entry.get("message", {})
                content = message.get("content", [])
                if not isinstance(content, list):
                    continue

                for block in content:
                    if not isinstance(block, dict):
                        continue
                    if block.get("type") != "tool_use":
                        continue

                    tool_name = block.get("name", "")
                    tool_input = block.get("input", {})

                    if tool_name == "Bash":
                        cmd = tool_input.get("command", "")
                        # bd commands with bead IDs
                        # Filter out ambient commands (list, ready, stats,
                        # blocked, search) — they don't indicate active work.
                        for m in BD_CMD_BEAD_RE.finditer(cmd):
                            subcmd = m.group(1)
                            bid = m.group(2)
                            if bid in known_bead_ids and subcmd not in BD_AMBIENT_SUBCOMMANDS:
                                found_ids.add(bid)
                                if ts:
                                    bead_timestamps[bid].append(ts)
                                bead_ref_types[bid].add("bd_cmd")
                        # Full prefix references in any bash command
                        for m in BEAD_IN_COMMIT_RE.finditer(cmd):
                            bid = m.group(1)
                            if bid in known_bead_ids:
                                found_ids.add(bid)
                                if ts:
                                    bead_timestamps[bid].append(ts)
                                bead_ref_types[bid].add("commit_ref")

                    elif tool_name == "Skill":
                        # Skill args referencing bead IDs in filenames
                        args = tool_input.get("args", "")
                        if args:
                            for m in BEAD_IN_COMMIT_RE.finditer(args):
                                bid = m.group(1)
                                if bid in known_bead_ids:
                                    found_ids.add(bid)
                                    if ts:
                                        bead_timestamps[bid].append(ts)
                                    bead_ref_types[bid].add("skill_args")

            elif entry_type == "user":
                message = entry.get("message", {})
                content = message.get("content", "")
                # Only scan user-authored text blocks, NOT tool_result content.
                user_texts = []
                if isinstance(content, str):
                    user_texts.append(content)
                elif isinstance(content, list):
                    for item in content:
                        if isinstance(item, dict) and item.get("type") == "text":
                            user_texts.append(item.get("text", ""))
                        # Deliberately skip tool_result blocks
                for text in user_texts:
                    for m in BEAD_USER_MSG_RE.finditer(text):
                        bid = m.group(1)
                        if bid in known_bead_ids:
                            found_ids.add(bid)
                            if ts:
                                bead_timestamps[bid].append(ts)
                            bead_ref_types[bid].add("user_msg")

    # Sort timestamps for each bead
    for bid in bead_timestamps:
        bead_timestamps[bid].sort()

    return found_ids, dict(bead_timestamps), {k: v for k, v in bead_ref_types.items()}


def load_known_bead_ids():
    """Load all known bead IDs from the beads database."""
    try:
        result = subprocess.run(
            ["bd", "sql", "SELECT id FROM issues"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        ids = set()
        prefix = "compound-workflows-marketplace-"
        for line in result.stdout.splitlines():
            line = line.strip()
            if line.startswith(prefix):
                short_id = line[len(prefix):]
                if short_id:
                    ids.add(short_id)
        return ids
    except Exception as e:
        print(f"  WARNING: Could not load bead IDs from database: {e}", file=sys.stderr)
        return set()


def load_closed_bead_estimates():
    """Load estimated_minutes and metadata for closed beads from the database."""
    try:
        result = subprocess.run(
            [
                "bd", "sql",
                "SELECT id, title, estimated_minutes, issue_type, priority, "
                "JSON_EXTRACT(metadata, '$.impact_score') AS score "
                "FROM issues WHERE status = 'closed' AND estimated_minutes IS NOT NULL"
            ],
            capture_output=True,
            text=True,
            timeout=10,
        )
        beads = {}
        prefix = "compound-workflows-marketplace-"
        lines = result.stdout.strip().splitlines()
        # Skip header and separator lines
        for line in lines:
            if line.startswith("-") or line.startswith("id") or not line.strip():
                continue
            # Parse pipe-separated output
            parts = [p.strip() for p in line.split("|")]
            if len(parts) < 6:
                continue
            full_id = parts[0].strip()
            if not full_id.startswith(prefix):
                continue
            short_id = full_id[len(prefix):]
            title = parts[1].strip()
            try:
                est_min = int(parts[2].strip())
            except (ValueError, IndexError):
                continue
            issue_type = parts[3].strip() if parts[3].strip() != "<nil>" else None
            try:
                priority = int(parts[4].strip())
            except (ValueError, IndexError):
                priority = None
            score_str = parts[5].strip()
            try:
                impact_score = int(score_str) if score_str and score_str != "<nil>" else None
            except ValueError:
                impact_score = None
            beads[short_id] = {
                "title": title,
                "estimated_minutes": est_min,
                "issue_type": issue_type,
                "priority": priority,
                "impact_score": impact_score,
            }
        return beads
    except Exception as e:
        print(f"  WARNING: Could not load bead estimates: {e}", file=sys.stderr)
        return {}


def classify_estimate_bucket(est_min):
    """Classify an estimate into a size bucket."""
    if est_min < 15:
        return "<15min"
    elif est_min <= 60:
        return "15-60min"
    elif est_min <= 120:
        return "60-120min"
    else:
        return ">120min"


def compute_estimation_segments(closed_bead_estimates, bead_attribution_windowed):
    """Segment estimation accuracy by type, priority, session count, and estimate size.

    Args:
        closed_bead_estimates: dict bead_id -> {title, estimated_minutes, issue_type, priority, impact_score}
        bead_attribution_windowed: dict bead_id -> {sessions, total_active_minutes, ...}

    Returns:
        dict with segment data and summary statistics
    """
    # Build per-bead records with actual vs estimated
    bead_records = []
    for bid, est_data in closed_bead_estimates.items():
        if bid not in bead_attribution_windowed:
            continue
        bw = bead_attribution_windowed[bid]
        estimated = est_data["estimated_minutes"]
        if estimated <= 0:
            continue
        actual = bw["total_active_minutes"]
        ratio = actual / estimated
        session_count = len(bw["sessions"])

        bead_records.append({
            "bead_id": bid,
            "title": est_data["title"],
            "issue_type": est_data.get("issue_type") or "unknown",
            "priority": est_data.get("priority"),
            "impact_score": est_data.get("impact_score"),
            "estimated_minutes": estimated,
            "actual_minutes": round(actual, 1),
            "ratio": round(ratio, 2),
            "session_count": session_count,
            "multi_session": session_count > 1,
            "estimate_bucket": classify_estimate_bucket(estimated),
        })

    if not bead_records:
        return {"segments": {}, "records": [], "bead_count": 0}

    # Helper: compute segment stats from a list of ratios
    def segment_stats(ratios):
        if not ratios:
            return {"n": 0}
        return {
            "n": len(ratios),
            "median_ratio": round(statistics.median(ratios), 2),
            "mean_ratio": round(statistics.mean(ratios), 2),
            "min_ratio": round(min(ratios), 2),
            "max_ratio": round(max(ratios), 2),
            "under_estimated": sum(1 for r in ratios if r > 1.0),
            "over_estimated": sum(1 for r in ratios if r < 1.0),
            "exact": sum(1 for r in ratios if r == 1.0),
        }

    segments = {}

    # Segment by issue_type
    by_type = defaultdict(list)
    for rec in bead_records:
        by_type[rec["issue_type"]].append(rec["ratio"])
    segments["by_type"] = {t: segment_stats(ratios) for t, ratios in sorted(by_type.items())}

    # Segment by priority
    by_priority = defaultdict(list)
    for rec in bead_records:
        p = rec["priority"]
        label = f"P{p}" if p is not None else "unknown"
        by_priority[label].append(rec["ratio"])
    segments["by_priority"] = {p: segment_stats(ratios) for p, ratios in sorted(by_priority.items())}

    # Segment by single-session vs multi-session
    by_session_type = defaultdict(list)
    for rec in bead_records:
        label = "multi-session" if rec["multi_session"] else "single-session"
        by_session_type[label].append(rec["ratio"])
    segments["by_session_type"] = {s: segment_stats(ratios) for s, ratios in sorted(by_session_type.items())}

    # Segment by estimate size bucket
    by_bucket = defaultdict(list)
    for rec in bead_records:
        by_bucket[rec["estimate_bucket"]].append(rec["ratio"])
    # Sort buckets in logical order
    bucket_order = ["<15min", "15-60min", "60-120min", ">120min"]
    segments["by_estimate_bucket"] = {
        b: segment_stats(by_bucket[b]) for b in bucket_order if b in by_bucket
    }

    # Overall stats
    all_ratios = [rec["ratio"] for rec in bead_records]
    segments["overall"] = segment_stats(all_ratios)

    return {
        "segments": segments,
        "records": bead_records,
        "bead_count": len(bead_records),
    }


def detect_concurrent_sessions(session_ranges):
    """Detect overlapping session timestamp ranges.

    Args:
        session_ranges: list of (session_id, first_ts, last_ts)

    Returns:
        list of overlap records: {session_a, session_b, overlap_start, overlap_end, overlap_minutes}
    """
    # Sort by start time
    sorted_ranges = sorted(session_ranges, key=lambda x: x[1])
    overlaps = []

    for i in range(len(sorted_ranges)):
        sid_a, start_a, end_a = sorted_ranges[i]
        for j in range(i + 1, len(sorted_ranges)):
            sid_b, start_b, end_b = sorted_ranges[j]
            # Since sorted by start, if start_b >= end_a, no more overlaps for session_a
            if start_b >= end_a:
                break
            # Overlap exists: start_b < end_a
            overlap_start = start_b  # start_b >= start_a since sorted
            overlap_end = min(end_a, end_b)
            overlap_minutes = (overlap_end - overlap_start).total_seconds() / 60.0
            if overlap_minutes > 0:
                overlaps.append({
                    "session_a": sid_a,
                    "session_b": sid_b,
                    "overlap_start": overlap_start.isoformat(),
                    "overlap_end": overlap_end.isoformat(),
                    "overlap_minutes": round(overlap_minutes, 2),
                })

    return overlaps


def compute_windowed_bead_attribution(
    bead_timestamps, bead_ref_types, sorted_session_ts, session_first_ts,
    session_last_ts, session_id, skill_invocations
):
    """Compute time-windowed bead attribution for a session.

    For each bead referenced in this session:
    - If the bead has specific timestamps (bd commands, user mentions),
      compute a window: 2 min before first reference to 2 min after last reference.
    - Clamp to session boundaries.
    - Compute active time within that window.

    For phase-to-bead mapping (sub-item 3): if a Skill invocation's args reference
    a bead ID, attribute the phase's time to that bead.

    Args:
        bead_timestamps: dict {bead_id: [sorted timestamps]}
        bead_ref_types: dict {bead_id: set of ref_type strings}
        sorted_session_ts: all session timestamps sorted
        session_first_ts: session start
        session_last_ts: session end
        session_id: session ID
        skill_invocations: list of skill invocations with timestamps

    Returns:
        list of windowed attribution records
    """
    attributions = []
    n_beads = len(bead_timestamps)

    for bid, ts_list in bead_timestamps.items():
        ref_types = bead_ref_types.get(bid, set())
        has_specific_refs = bool(ref_types - {"commit_ref"})

        if ts_list and has_specific_refs:
            # Windowed attribution: 2 min before first, 2 min after last
            window_start = ts_list[0] - timedelta(seconds=BEAD_WINDOW_BEFORE_SECONDS)
            window_end = ts_list[-1] + timedelta(seconds=BEAD_WINDOW_AFTER_SECONDS)

            # Clamp to session boundaries
            if session_first_ts:
                window_start = max(window_start, session_first_ts)
            if session_last_ts:
                window_end = min(window_end, session_last_ts)

            # Compute active time in window
            ai = compute_active_idle(sorted_session_ts, window_start, window_end)

            # Check phase-to-bead mapping: which phases overlap this window?
            phases_in_window = []
            for i, inv in enumerate(skill_invocations):
                phase_start = inv["timestamp"]
                if i + 1 < len(skill_invocations):
                    phase_end = skill_invocations[i + 1]["timestamp"]
                else:
                    phase_end = session_last_ts

                if phase_start and phase_end and window_start and window_end:
                    # Check overlap
                    if phase_start < window_end and phase_end > window_start:
                        phases_in_window.append(inv["phase"])

                # Also check if Skill args reference this bead (sub-item 3)
                args = inv.get("args", "")
                if args and bid in args:
                    if inv["phase"] not in phases_in_window:
                        phases_in_window.append(inv["phase"])

            attributions.append({
                "bead_id": bid,
                "session_id": session_id,
                "method": "windowed",
                "reference_count": len(ts_list),
                "ref_types": sorted(ref_types),
                "window_start": window_start.isoformat() if window_start else None,
                "window_end": window_end.isoformat() if window_end else None,
                "active_minutes": ai["active_minutes"],
                "wall_clock_minutes": round(
                    (window_end - window_start).total_seconds() / 60.0, 2
                ) if window_start and window_end else 0,
                "phases_in_window": phases_in_window,
            })
        elif ts_list:
            # Has timestamps but only from commit_ref — use proportional splitting
            if session_first_ts and session_last_ts:
                session_ai = compute_active_idle(
                    sorted_session_ts, session_first_ts, session_last_ts
                )
                proportional_active = session_ai["active_minutes"] / max(n_beads, 1)
                proportional_wall = (
                    (session_last_ts - session_first_ts).total_seconds() / 60.0
                ) / max(n_beads, 1)
            else:
                proportional_active = 0
                proportional_wall = 0

            attributions.append({
                "bead_id": bid,
                "session_id": session_id,
                "method": "proportional",
                "reference_count": len(ts_list),
                "ref_types": sorted(ref_types),
                "window_start": None,
                "window_end": None,
                "active_minutes": round(proportional_active, 2),
                "wall_clock_minutes": round(proportional_wall, 2),
                "phases_in_window": [],
            })
        else:
            # No timestamps (shouldn't happen but be safe)
            attributions.append({
                "bead_id": bid,
                "session_id": session_id,
                "method": "proportional",
                "reference_count": 0,
                "ref_types": sorted(ref_types),
                "window_start": None,
                "window_end": None,
                "active_minutes": 0,
                "wall_clock_minutes": 0,
                "phases_in_window": [],
            })

    return attributions


def scan_compact_summary_timestamps(filepath):
    """Scan a session file for isCompactSummary entries.

    These mark when /compact actually executes, and serve as the true end
    boundary for compact-prep phases (which otherwise bleed into the next
    Skill invocation boundary).

    Returns:
        list of datetime timestamps where isCompactSummary was found, sorted ascending.
    """
    timestamps = []
    with open(filepath, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            if entry.get("isCompactSummary"):
                ts = parse_timestamp(entry.get("timestamp"))
                if ts:
                    timestamps.append(ts)
    timestamps.sort()
    return timestamps


# Productive tool calls for reorientation measurement — excludes
# orientation tools (Read, Grep, Glob) and non-productive (Bash for reading).
PRODUCTIVE_TOOLS = {"Edit", "Write", "Agent", "Task"}


def extract_compaction_costs(filepath, session_id):
    """Extract cost and reorientation data for each compaction event in a session.

    For each isCompactSummary entry:
    1. Find the assistant entry immediately preceding it and read its message.usage
       to compute the compaction request's token cost.
    2. Find the first productive tool call (Edit/Write/Agent/Task) after the
       compaction and measure the reorientation gap.

    Returns:
        list of dicts with: session, timestamp, token_cost, reorientation_minutes,
        model, input_tokens, output_tokens, cache_creation_tokens, cache_read_tokens
    """
    results = []

    # Two-pass approach: first pass collects all entries with timestamps
    entries = []
    with open(filepath, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            entries.append(entry)

    # Walk through entries to find compaction events
    last_assistant_usage = None  # (timestamp, cost, model, usage_dict)
    for i, entry in enumerate(entries):
        entry_type = entry.get("type")
        ts_str = entry.get("timestamp")
        ts = parse_timestamp(ts_str)

        # Track last assistant entry with usage
        if entry_type == "assistant":
            message = entry.get("message", {})
            usage = message.get("usage")
            model = message.get("model", "")
            if usage and ts:
                cost = compute_request_cost(usage, model)
                last_assistant_usage = {
                    "timestamp": ts,
                    "cost": cost,
                    "model": model,
                    "input_tokens": usage.get("input_tokens", 0),
                    "cache_creation_input_tokens": usage.get("cache_creation_input_tokens", 0),
                    "cache_read_input_tokens": usage.get("cache_read_input_tokens", 0),
                    "output_tokens": usage.get("output_tokens", 0),
                }

        # Found a compaction event
        if entry.get("isCompactSummary") and ts:
            compaction_ts = ts

            # Get the preceding assistant's cost
            token_cost = 0.0
            model_name = ""
            input_tok = 0
            output_tok = 0
            cache_create_tok = 0
            cache_read_tok = 0
            if last_assistant_usage:
                token_cost = last_assistant_usage["cost"]
                model_name = last_assistant_usage["model"]
                input_tok = last_assistant_usage["input_tokens"]
                output_tok = last_assistant_usage["output_tokens"]
                cache_create_tok = last_assistant_usage["cache_creation_input_tokens"]
                cache_read_tok = last_assistant_usage["cache_read_input_tokens"]

            # Find first productive tool call after compaction
            reorientation_minutes = None
            for j in range(i + 1, len(entries)):
                future_entry = entries[j]
                if future_entry.get("type") != "assistant":
                    continue
                future_msg = future_entry.get("message", {})
                future_content = future_msg.get("content", [])
                if not isinstance(future_content, list):
                    continue
                future_ts_str = future_entry.get("timestamp")
                future_ts = parse_timestamp(future_ts_str)
                if not future_ts:
                    continue

                # Check tool calls in this assistant message
                found_productive = False
                for block in future_content:
                    if not isinstance(block, dict):
                        continue
                    if block.get("type") != "tool_use":
                        continue
                    tool_name = block.get("name", "")
                    if tool_name in PRODUCTIVE_TOOLS:
                        found_productive = True
                        break

                if found_productive:
                    gap = (future_ts - compaction_ts).total_seconds() / 60.0
                    reorientation_minutes = round(gap, 2)
                    break

            results.append({
                "session": session_id,
                "timestamp": compaction_ts.isoformat(),
                "token_cost": round(token_cost, 4),
                "reorientation_minutes": reorientation_minutes,
                "model": model_name,
                "input_tokens": input_tok,
                "output_tokens": output_tok,
                "cache_creation_tokens": cache_create_tok,
                "cache_read_tokens": cache_read_tok,
            })

    return results


def process_session(filepath):
    """Process a single JSONL session file.

    Returns a dict with:
    - session: session metadata
    - phases: list of phase observations
    - agents: list of agent observations
    - sorted_timestamps: sorted list of all parsed timestamps
    - skill_invocations: list of skill invocations with timestamps
    - tool_events: list of (timestamp, tool_name) tuples
    - bash_commands_with_ts: list of (timestamp, command) tuples
    - user_msg_timestamps: list of timestamps for user messages
    - compact_summary_timestamps: sorted list of isCompactSummary timestamps
    - errors: list of error messages
    """
    session_id = os.path.splitext(os.path.basename(filepath))[0]
    errors = []

    # Track timestamps for session duration
    timestamps = []
    entry_count = 0

    # Track Skill invocations (phases)
    skill_invocations = []  # (timestamp, skill_name, phase, tool_use_id)

    # Track Agent/Task dispatches
    agent_dispatches = {}  # tool_use_id -> dispatch info

    # Track agent completions
    agent_completions = []  # completed agent observations

    # Tool call counts
    tool_counts = Counter()
    # Tool calls with timestamps for phase assignment
    tool_events = []  # (timestamp, tool_name)

    # Bash commands with timestamps (for segment classification and bead detection)
    bash_commands_with_ts = []  # (timestamp, command_string)

    # User message tracking
    user_message_count = 0
    user_msg_timestamps = []  # timestamps of user messages
    correction_count = 0

    # Compaction events
    compaction_count = 0

    # Git commits
    git_commit_count = 0

    # Per-request cost tracking
    # Each entry: (timestamp, model, cost, input_tokens, cache_creation_tokens, cache_read_tokens, output_tokens)
    request_costs = []
    session_cost_by_model = defaultdict(float)  # model_prefix -> total cost
    session_total_cost = 0.0

    # Process line by line for memory efficiency
    with open(filepath, "r") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError as e:
                errors.append(f"Line {line_num}: JSON parse error: {e}")
                continue

            entry_count += 1
            entry_type = entry.get("type")
            ts_str = entry.get("timestamp")
            ts = parse_timestamp(ts_str)
            if ts:
                timestamps.append(ts)

            # --- Compaction events ---
            if entry.get("isCompactSummary"):
                compaction_count += 1

            # --- Skip non-message types for tool extraction ---
            if entry_type == "assistant":
                message = entry.get("message", {})

                # --- Per-request cost extraction ---
                usage = message.get("usage")
                model = message.get("model", "")
                if usage:
                    cost = compute_request_cost(usage, model)
                    session_total_cost += cost
                    # Map to model prefix for grouping
                    model_prefix = ""
                    for prefix in MODEL_PRICING:
                        if model.startswith(prefix):
                            model_prefix = prefix
                            break
                    if model_prefix:
                        session_cost_by_model[model_prefix] += cost
                    request_costs.append({
                        "timestamp": ts,
                        "model": model,
                        "cost": cost,
                        "input_tokens": usage.get("input_tokens", 0),
                        "cache_creation_input_tokens": usage.get("cache_creation_input_tokens", 0),
                        "cache_read_input_tokens": usage.get("cache_read_input_tokens", 0),
                        "output_tokens": usage.get("output_tokens", 0),
                    })

                content = message.get("content", [])
                if not isinstance(content, list):
                    continue

                for block in content:
                    if not isinstance(block, dict):
                        continue
                    if block.get("type") != "tool_use":
                        continue

                    tool_name = block.get("name", "")
                    tool_id = block.get("id", "")
                    tool_input = block.get("input", {})

                    # Count all tool calls
                    tool_counts[tool_name] += 1
                    if ts:
                        tool_events.append((ts, tool_name))

                    # --- Skill invocations ---
                    if tool_name == "Skill":
                        skill_name = tool_input.get("skill", "")
                        phase = extract_skill_phase(skill_name)
                        skill_invocations.append(
                            {
                                "timestamp": ts,
                                "ts_str": ts_str,
                                "skill_name": skill_name,
                                "phase": phase,
                                "tool_use_id": tool_id,
                                "args": tool_input.get("args", ""),
                            }
                        )

                    # --- Agent/Task dispatches ---
                    if tool_name in ("Agent", "Task"):
                        agent_dispatches[tool_id] = {
                            "tool_use_id": tool_id,
                            "tool_type": tool_name,
                            "subagent_type": tool_input.get(
                                "subagent_type", ""
                            ),
                            "description": tool_input.get("description", ""),
                            "dispatch_timestamp": ts,
                            "dispatch_ts_str": ts_str,
                        }

                    # --- Bash commands ---
                    if tool_name == "Bash":
                        cmd = tool_input.get("command", "")
                        if ts:
                            bash_commands_with_ts.append((ts, cmd))
                        # --- Git commits ---
                        if "git commit" in cmd:
                            git_commit_count += 1

            elif entry_type == "user":
                message = entry.get("message", {})
                content = message.get("content", "")

                # Count user messages (only text-bearing ones)
                text = extract_text_from_content(content)
                if isinstance(content, str) and content.strip():
                    user_message_count += 1
                    if ts:
                        user_msg_timestamps.append(ts)
                    # Check for corrections
                    if CORRECTION_PATTERNS.search(content):
                        correction_count += 1
                elif isinstance(content, list):
                    # Check if there's a direct user text (not just tool_results)
                    has_user_text = False
                    for item in content:
                        if isinstance(item, dict):
                            if item.get("type") == "text":
                                has_user_text = True
                                txt = item.get("text", "")
                                if CORRECTION_PATTERNS.search(txt):
                                    correction_count += 1
                    if has_user_text:
                        user_message_count += 1
                        if ts:
                            user_msg_timestamps.append(ts)

                    # Check tool_result blocks for agent completions
                    for item in content:
                        if not isinstance(item, dict):
                            continue
                        if item.get("type") != "tool_result":
                            continue

                        result_tool_id = item.get("tool_use_id", "")
                        if result_tool_id in agent_dispatches:
                            dispatch = agent_dispatches[result_tool_id]
                            # Extract usage from result content
                            result_text = extract_text_from_content(
                                item.get("content", "")
                            )
                            usage = extract_usage_from_text(result_text)

                            completion = {
                                **dispatch,
                                "completion_timestamp": ts,
                                "completion_ts_str": ts_str,
                            }

                            if usage:
                                completion["usage_total_tokens"] = usage[
                                    "total_tokens"
                                ]
                                completion["usage_tool_uses"] = usage[
                                    "tool_uses"
                                ]
                                completion["usage_duration_ms"] = usage[
                                    "duration_ms"
                                ]

                            # Compute wall-clock duration from timestamps
                            if (
                                dispatch.get("dispatch_timestamp")
                                and ts
                            ):
                                delta = (
                                    ts - dispatch["dispatch_timestamp"]
                                )
                                completion["wall_clock_duration_ms"] = (
                                    int(delta.total_seconds() * 1000)
                                )

                            agent_completions.append(completion)

    # --- Scan for isCompactSummary timestamps ---
    compact_summary_ts = scan_compact_summary_timestamps(filepath)

    # --- Sort timestamps once for active/idle computation ---
    sorted_ts = sorted(timestamps)

    # --- Compute session metadata ---
    if sorted_ts:
        first_ts = sorted_ts[0]
        last_ts = sorted_ts[-1]
        total_duration = (last_ts - first_ts).total_seconds() / 60.0
    else:
        first_ts = None
        last_ts = None
        total_duration = 0

    # Compute session-level active/idle
    session_active_idle = compute_active_idle(sorted_ts, first_ts, last_ts)

    session_meta = {
        "record_type": "session",
        "session_id": session_id,
        "first_timestamp": first_ts.isoformat() if first_ts else None,
        "last_timestamp": last_ts.isoformat() if last_ts else None,
        "total_duration_minutes": round(total_duration, 2),
        "active_minutes": session_active_idle["active_minutes"],
        "idle_minutes": session_active_idle["idle_minutes"],
        "idle_gap_count": session_active_idle["idle_gap_count"],
        "entry_count": entry_count,
        "user_message_count": user_message_count,
        "correction_count": correction_count,
        "compaction_count": compaction_count,
        "git_commit_count": git_commit_count,
        "tool_counts": dict(tool_counts),
        "skill_invocation_count": len(skill_invocations),
        "agent_dispatch_count": len(agent_dispatches),
        "agent_completion_count": len(agent_completions),
        "session_cost_usd": round(session_total_cost, 6),
        "cost_by_model": {k: round(v, 6) for k, v in session_cost_by_model.items()},
    }

    # --- Compute phase observations ---
    # Phase boundary notes:
    # - compact-prep: Uses isCompactSummary JSONL entry as true end marker
    #   (the /compact execution), falling back to next Skill invocation.
    # - brainstorm, plan, deepen-plan, work, review, compound: The next-Skill-
    #   invocation boundary is accurate. These phases run until the user invokes
    #   the next skill. There is no specific JSONL marker for their completion
    #   analogous to isCompactSummary. The user typically invokes the next skill
    #   immediately after the current one finishes, so boundary bleed is minimal.
    # - abandon: Runs at session end, so last_ts is the natural boundary.
    # - setup, qa: Short-lived, typically followed immediately by another skill.
    phase_observations = []
    for i, inv in enumerate(skill_invocations):
        phase_start = inv["timestamp"]
        # Default: phase ends at next skill invocation or end of session
        if i + 1 < len(skill_invocations):
            default_phase_end = skill_invocations[i + 1]["timestamp"]
        else:
            default_phase_end = last_ts

        phase_end = default_phase_end

        # PHASE BOUNDARY CORRECTION: For compact-prep, use isCompactSummary
        # as the true end marker instead of next Skill invocation.
        compact_prep_boundary_source = None
        if inv["phase"] == "compact-prep" and phase_start and compact_summary_ts:
            # Find the first isCompactSummary after this phase starts
            for cs_ts in compact_summary_ts:
                if cs_ts > phase_start:
                    # Use this as end, but don't exceed the default boundary
                    if default_phase_end is None or cs_ts <= default_phase_end:
                        phase_end = cs_ts
                        compact_prep_boundary_source = "isCompactSummary"
                    break
            if not compact_prep_boundary_source:
                compact_prep_boundary_source = "next-skill-fallback"

        if phase_start and phase_end:
            phase_duration = (
                phase_end - phase_start
            ).total_seconds() / 60.0
        else:
            phase_duration = None

        # Count tool calls during this phase
        phase_tools = Counter()
        if phase_start and phase_end:
            for evt_ts, evt_name in tool_events:
                if phase_start <= evt_ts <= phase_end:
                    phase_tools[evt_name] += 1

        # Compute per-phase cost
        phase_cost = 0.0
        if phase_start and phase_end:
            for rc in request_costs:
                rc_ts = rc["timestamp"]
                if rc_ts and phase_start <= rc_ts <= phase_end:
                    phase_cost += rc["cost"]

        # Compute active/idle for this phase
        phase_active_idle = compute_active_idle(
            sorted_ts, phase_start, phase_end
        )

        # NESTED COMPOUND SUBTRACTION: If this is a compact-prep phase,
        # check for nested compound skill invocations within the window
        # and subtract their duration from compact-prep's active time.
        nested_compound_minutes = 0.0
        if inv["phase"] == "compact-prep" and phase_start and phase_end:
            for j, other_inv in enumerate(skill_invocations):
                if other_inv["phase"] == "compound" and other_inv["timestamp"]:
                    compound_start = other_inv["timestamp"]
                    # Compound must start within compact-prep window
                    if phase_start < compound_start < phase_end:
                        # Find compound end
                        if j + 1 < len(skill_invocations):
                            compound_end = skill_invocations[j + 1]["timestamp"]
                        else:
                            compound_end = last_ts
                        # Clamp compound end to compact-prep boundary
                        if compound_end and compound_end > phase_end:
                            compound_end = phase_end
                        if compound_start and compound_end:
                            compound_ai = compute_active_idle(
                                sorted_ts, compound_start, compound_end
                            )
                            nested_compound_minutes += compound_ai["active_minutes"]

        net_active = phase_active_idle["active_minutes"]
        if nested_compound_minutes > 0:
            net_active = max(0, net_active - nested_compound_minutes)

        phase_obs = {
            "record_type": "phase",
            "session_id": session_id,
            "skill_name": inv["skill_name"],
            "phase": inv["phase"],
            "args": inv["args"],
            "start_timestamp": inv["ts_str"],
            "end_timestamp": (
                phase_end.isoformat() if phase_end else None
            ),
            "duration_minutes": (
                round(phase_duration, 2) if phase_duration is not None else None
            ),
            "active_minutes": phase_active_idle["active_minutes"],
            "idle_minutes": phase_active_idle["idle_minutes"],
            "idle_gap_count": phase_active_idle["idle_gap_count"],
            "entry_count": phase_active_idle["entry_count"],
            "tool_counts": dict(phase_tools),
            "phase_cost_usd": round(phase_cost, 6),
        }

        # Add compact-prep-specific fields
        if inv["phase"] == "compact-prep":
            phase_obs["boundary_source"] = compact_prep_boundary_source
            if nested_compound_minutes > 0:
                phase_obs["gross_active_minutes"] = phase_active_idle["active_minutes"]
                phase_obs["net_active_minutes"] = round(net_active, 2)
                phase_obs["nested_compound_minutes"] = round(nested_compound_minutes, 2)

        phase_observations.append(phase_obs)

    # --- Format agent observations ---
    agent_observations = []
    for comp in agent_completions:
        obs = {
            "record_type": "agent",
            "session_id": session_id,
            "tool_type": comp.get("tool_type"),
            "subagent_type": comp.get("subagent_type"),
            "description": comp.get("description"),
            "dispatch_timestamp": comp.get("dispatch_ts_str"),
            "completion_timestamp": comp.get("completion_ts_str"),
            "wall_clock_duration_ms": comp.get("wall_clock_duration_ms"),
            "usage_total_tokens": comp.get("usage_total_tokens"),
            "usage_tool_uses": comp.get("usage_tool_uses"),
            "usage_duration_ms": comp.get("usage_duration_ms"),
        }
        agent_observations.append(obs)

    return {
        "session": session_meta,
        "phases": phase_observations,
        "agents": agent_observations,
        "sorted_timestamps": sorted_ts,
        "skill_invocations": skill_invocations,
        "tool_events": tool_events,
        "bash_commands_with_ts": bash_commands_with_ts,
        "user_msg_timestamps": user_msg_timestamps,
        "compact_summary_timestamps": compact_summary_ts,
        "request_costs": request_costs,
        "first_ts": first_ts,
        "last_ts": last_ts,
        "errors": errors,
    }


def compute_segments(result):
    """Compute non-workflow segments for a session.

    A segment is:
    - Time before the first Skill invocation
    - Time between Skill invocations (these are the workflow phase segments, but we
      also want to classify them)
    - Time after the last Skill invocation
    - The entire session if no Skill invocations

    For workflow phases (between Skill invocations), we already have phase records.
    We create segment records for the non-workflow parts: before first Skill,
    after last Skill, and entire sessions without Skills.

    Returns list of segment dicts.
    """
    session = result["session"]
    session_id = session["session_id"]
    skill_invocations = result["skill_invocations"]
    sorted_ts = result["sorted_timestamps"]
    tool_events = result["tool_events"]
    bash_commands_with_ts = result["bash_commands_with_ts"]
    user_msg_timestamps = result["user_msg_timestamps"]
    first_ts = result["first_ts"]
    last_ts = result["last_ts"]

    segments = []

    if not first_ts or not last_ts:
        return segments

    def make_segment(seg_start, seg_end, seg_type):
        """Create a segment record for a given time window."""
        if not seg_start or not seg_end or seg_start >= seg_end:
            return None

        # Collect tool counts in this window
        seg_tools = Counter()
        seg_bash_cmds = []
        for evt_ts, evt_name in tool_events:
            if seg_start <= evt_ts <= seg_end:
                seg_tools[evt_name] += 1
        for evt_ts, cmd in bash_commands_with_ts:
            if seg_start <= evt_ts <= seg_end:
                seg_bash_cmds.append(cmd)

        # Count user messages in this window
        seg_user_msgs = sum(
            1 for t in user_msg_timestamps if seg_start <= t <= seg_end
        )

        # Active/idle
        ai = compute_active_idle(sorted_ts, seg_start, seg_end)
        wall_minutes = (seg_end - seg_start).total_seconds() / 60.0

        # Classify (now returns 3-tuple with subcategory)
        category, subcategory, bd_subcmds = classify_segment(
            seg_tools, seg_user_msgs, seg_bash_cmds, wall_minutes
        )
        bd_categories = categorize_bd_subcommands(bd_subcmds)

        seg = {
            "record_type": "segment",
            "session_id": session_id,
            "segment_type": seg_type,  # "pre-workflow", "post-workflow", "full-session", "workflow-phase"
            "category": category,
            "active_minutes": ai["active_minutes"],
            "idle_minutes": ai["idle_minutes"],
            "wall_clock_minutes": round(wall_minutes, 2),
            "tool_counts": dict(seg_tools),
            "bd_subcommand_counts": dict(bd_subcmds),
            "bd_categories": bd_categories,
            "user_message_count": seg_user_msgs,
            "total_tool_calls": sum(seg_tools.values()),
        }
        if subcategory:
            seg["subcategory"] = subcategory
        return seg

    if not skill_invocations:
        # Entire session is non-workflow
        seg = make_segment(first_ts, last_ts, "full-session")
        if seg:
            segments.append(seg)
    else:
        # Pre-workflow segment (before first Skill)
        first_skill_ts = skill_invocations[0]["timestamp"]
        if first_skill_ts and first_ts and first_skill_ts > first_ts:
            seg = make_segment(first_ts, first_skill_ts, "pre-workflow")
            if seg:
                segments.append(seg)

        # Workflow phase segments (between Skill invocations) - classify them too
        for i, inv in enumerate(skill_invocations):
            phase_start = inv["timestamp"]
            if i + 1 < len(skill_invocations):
                phase_end = skill_invocations[i + 1]["timestamp"]
            else:
                phase_end = last_ts
            seg = make_segment(phase_start, phase_end, "workflow-phase")
            if seg:
                seg["phase"] = inv.get("phase", "unknown")
                segments.append(seg)

        # Post-workflow segment (after last Skill)
        last_skill_ts = skill_invocations[-1]["timestamp"]
        # For post-workflow, we need to check if there's activity after the last
        # phase ends. The last phase already extends to last_ts, so post-workflow
        # is only meaningful if there's no last phase (edge case).
        # Actually, the last phase ends at last_ts, so there's no post-workflow gap.
        # But we should check: if there's time between the last phase's assigned end
        # and last_ts when there are multiple invocations... No, the last phase
        # always extends to last_ts. So post-workflow is empty by construction.
        # We skip it.

    return segments


def compute_stats(values):
    """Compute summary statistics for a list of numeric values."""
    if not values:
        return {"n": 0}
    values = sorted(values)
    n = len(values)
    result = {
        "n": n,
        "min": round(values[0], 2),
        "max": round(values[-1], 2),
        "mean": round(statistics.mean(values), 2),
        "median": round(statistics.median(values), 2),
    }
    if n >= 10:
        p90_idx = int(n * 0.9)
        result["p90"] = round(values[min(p90_idx, n - 1)], 2)
    return result


def classify_tool_call_bucket(tool_name, bash_cmd=None):
    """Classify a tool call into a proportional allocation bucket.

    Returns one of: bd, editing, reading, agent-dispatch, user-dialogue, other
    """
    if tool_name == "Bash" and bash_cmd:
        if bash_cmd.strip().startswith("bd "):
            return "bd"
        return "other"
    return TOOL_BUCKET_MAP.get(tool_name, "other")


def compute_dedup_active_minutes(all_session_results):
    """Compute deduplicated active minutes across all sessions.

    Uses minute-level deduplication: collect all active (Y,M,D,H,M) tuples
    across all sessions into a global set. Active = consecutive entries with
    gaps < 5 min.

    Also computes true wall-clock by merging session intervals.

    Args:
        all_session_results: list of process_session() result dicts

    Returns:
        dict with:
        - dedup_active_minutes: int (set size)
        - merged_wall_clock_minutes: float
        - merged_intervals: list of (start_iso, end_iso) strings
        - session_count: int
    """
    global_active_minutes = set()  # (year, month, day, hour, minute) tuples

    for result in all_session_results:
        sorted_ts = result["sorted_timestamps"]
        if len(sorted_ts) < 2:
            # Single entry: add its minute
            if sorted_ts:
                ts = sorted_ts[0]
                global_active_minutes.add((ts.year, ts.month, ts.day, ts.hour, ts.minute))
            continue

        # Walk consecutive entries, mark minutes as active when gap < threshold
        for i in range(1, len(sorted_ts)):
            gap = (sorted_ts[i] - sorted_ts[i - 1]).total_seconds()
            if gap < IDLE_THRESHOLD_SECONDS:
                # Both entries are in an active stretch — add all minutes in between
                t1 = sorted_ts[i - 1]
                t2 = sorted_ts[i]
                # Add minute-level tuples for all minutes from t1 to t2
                current = t1.replace(second=0, microsecond=0)
                end = t2.replace(second=0, microsecond=0)
                while current <= end:
                    global_active_minutes.add(
                        (current.year, current.month, current.day,
                         current.hour, current.minute)
                    )
                    current += timedelta(minutes=1)

    # Merge session intervals for true wall-clock
    intervals = []
    for result in all_session_results:
        if result["first_ts"] and result["last_ts"]:
            intervals.append((result["first_ts"], result["last_ts"]))

    merged = merge_intervals(intervals)
    merged_wall_minutes = sum(
        (end - start).total_seconds() / 60.0 for start, end in merged
    )

    return {
        "dedup_active_minutes": len(global_active_minutes),
        "merged_wall_clock_minutes": round(merged_wall_minutes, 2),
        "merged_intervals": [
            (start.isoformat(), end.isoformat()) for start, end in merged
        ],
        "session_count": len(all_session_results),
    }


def merge_intervals(intervals):
    """Merge overlapping/adjacent time intervals.

    Args:
        intervals: list of (start_datetime, end_datetime) tuples

    Returns:
        list of merged (start_datetime, end_datetime) tuples
    """
    if not intervals:
        return []
    sorted_iv = sorted(intervals, key=lambda x: x[0])
    merged = [sorted_iv[0]]
    for start, end in sorted_iv[1:]:
        prev_start, prev_end = merged[-1]
        if start <= prev_end:
            # Overlapping or adjacent — extend
            merged[-1] = (prev_start, max(prev_end, end))
        else:
            merged.append((start, end))
    return merged


def compute_proportional_allocation(tool_events, bash_commands_with_ts, start_ts, end_ts, active_minutes):
    """Compute proportional tool-call time allocation for a time window.

    Classifies each tool call into a bucket and allocates active time proportionally.

    Args:
        tool_events: list of (timestamp, tool_name) tuples
        bash_commands_with_ts: list of (timestamp, command) tuples
        start_ts: window start
        end_ts: window end
        active_minutes: total active minutes in the window

    Returns:
        dict with bucket -> {count, fraction, allocated_minutes}
    """
    if not start_ts or not end_ts or active_minutes <= 0:
        return {}

    # Build bash command lookup by timestamp
    bash_by_ts = {}
    for ts, cmd in bash_commands_with_ts:
        if start_ts <= ts <= end_ts:
            bash_by_ts[ts] = cmd

    # Classify each tool call in the window
    bucket_counts = Counter()
    total_in_window = 0
    for ts, tool_name in tool_events:
        if start_ts <= ts <= end_ts:
            bash_cmd = bash_by_ts.get(ts) if tool_name == "Bash" else None
            bucket = classify_tool_call_bucket(tool_name, bash_cmd)
            bucket_counts[bucket] += 1
            total_in_window += 1

    if total_in_window == 0:
        return {}

    result = {}
    for bucket, count in bucket_counts.items():
        fraction = count / total_in_window
        result[bucket] = {
            "count": count,
            "fraction": round(fraction, 4),
            "allocated_minutes": round(active_minutes * fraction, 2),
        }
    return result


def extract_askuser_events(filepath):
    """Extract AskUserQuestion tool calls with timestamps and question text.

    Also finds the next assistant message timestamp after each question
    (to compute time-to-response).

    Args:
        filepath: path to the JSONL file

    Returns:
        list of dicts with: timestamp, question_text, category, response_timestamp, wait_minutes
    """
    events = []
    # First pass: collect AskUserQuestion events and all timestamps by type
    entries = []
    with open(filepath, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            ts = parse_timestamp(entry.get("timestamp"))
            entry_type = entry.get("type")
            entries.append((ts, entry_type, entry))

    # Find AskUserQuestion tool calls and their response timestamps
    for idx, (ts, entry_type, entry) in enumerate(entries):
        if entry_type != "assistant":
            continue
        message = entry.get("message", {})
        content = message.get("content", [])
        if not isinstance(content, list):
            continue

        for block in content:
            if not isinstance(block, dict):
                continue
            if block.get("type") != "tool_use":
                continue
            if block.get("name") != "AskUserQuestion":
                continue

            tool_input = block.get("input", {})
            # AskUserQuestion has "questions" (list) field
            questions_list = tool_input.get("questions", [])
            if isinstance(questions_list, list) and questions_list:
                # Concatenate all question texts
                parts = []
                for q in questions_list:
                    if isinstance(q, dict):
                        parts.append(q.get("question", ""))
                        parts.append(q.get("header", ""))
                        # Include option labels for categorization
                        for opt in q.get("options", []):
                            if isinstance(opt, dict):
                                parts.append(opt.get("label", ""))
                                parts.append(opt.get("description", ""))
                    elif isinstance(q, str):
                        parts.append(q)
                question_text = " ".join(p for p in parts if p)
            else:
                # Fallback: try "question" (singular) or "text"
                question_text = tool_input.get("question", "")
                if not question_text:
                    question_text = tool_input.get("text", "")

            # Categorize
            category = categorize_askuser(question_text)

            # Find next assistant message timestamp (= end of user wait)
            response_ts = None
            for future_idx in range(idx + 1, len(entries)):
                future_ts, future_type, _ = entries[future_idx]
                if future_type == "assistant" and future_ts and future_ts > ts:
                    response_ts = future_ts
                    break

            wait_minutes = None
            if ts and response_ts:
                wait_minutes = round(
                    (response_ts - ts).total_seconds() / 60.0, 2
                )

            events.append({
                "timestamp": ts,
                "question_text": question_text[:200],  # Truncate for storage
                "category": category,
                "response_timestamp": response_ts,
                "wait_minutes": wait_minutes,
            })

    return events


def categorize_askuser(question_text):
    """Categorize an AskUserQuestion by keyword matching.

    Returns the first matching category, or 'other'.
    """
    for category, pattern in ASKUSER_CATEGORIES.items():
        if pattern.search(question_text):
            return category
    return "other"


def build_phase_windows(skill_invocations, last_ts, compact_summary_timestamps=None):
    """Build phase windows from skill invocations for AUQ-to-workflow matching.

    Returns a list of (phase_name, start_ts, end_ts) tuples.
    Reuses the same boundary logic as the main phase processing:
    - compact-prep uses isCompactSummary as end marker when available
    - Other phases end at the next skill invocation or session end
    """
    windows = []
    compact_summary_ts = compact_summary_timestamps or []
    for i, inv in enumerate(skill_invocations):
        phase_start = inv["timestamp"]
        if not phase_start:
            continue

        # Default: phase ends at next skill invocation or end of session
        if i + 1 < len(skill_invocations):
            phase_end = skill_invocations[i + 1]["timestamp"]
        else:
            phase_end = last_ts

        # compact-prep boundary correction
        if inv["phase"] == "compact-prep" and compact_summary_ts:
            for cs_ts in compact_summary_ts:
                if cs_ts > phase_start:
                    if phase_end is None or cs_ts <= phase_end:
                        phase_end = cs_ts
                    break

        if phase_start and phase_end:
            windows.append((inv["phase"], phase_start, phase_end))

    return windows


def assign_askuser_to_workflow(event_ts, phase_windows):
    """Determine which workflow phase an AskUserQuestion event falls within.

    Args:
        event_ts: datetime timestamp of the AUQ event
        phase_windows: list of (phase_name, start_ts, end_ts) tuples

    Returns:
        phase name string, or "non-workflow" if outside all windows
    """
    if not event_ts:
        return "non-workflow"
    for phase_name, start_ts, end_ts in phase_windows:
        if start_ts <= event_ts <= end_ts:
            return phase_name
    return "non-workflow"


def compute_permission_prompt_estimate(jsonl_files, all_askuser_events):
    """Estimate cost of OS-level permission prompts.

    There is no JSONL signal for OS-level permission prompts. This function
    uses a proxy: count Bash tool calls in permissionMode="default" sessions
    that match known heuristic-triggering patterns ($(), <<, {").

    The estimate multiplies the triggering-pattern count by the median user
    response time for confirmation AskUserQuestion events as an upper bound.

    Args:
        jsonl_files: list of JSONL file paths
        all_askuser_events: list of AskUserQuestion event dicts (with category, wait_minutes)

    Returns:
        dict with estimation data for the summary
    """
    # Heuristic-triggering patterns in Bash commands
    # These are the patterns documented in AGENTS.md Bash Generation Rules
    PERMISSION_PATTERNS = [
        re.compile(r'\$\('),       # $() command substitution
        re.compile(r'<<'),          # heredoc
        re.compile(r'\{"'),         # JSON-like brace-quote ({"key": ...)
    ]

    # Compute median confirmation wait time from AskUserQuestion data
    confirmation_waits = [
        evt["wait_minutes"]
        for evt in all_askuser_events
        if evt.get("category") == "confirmation" and evt.get("wait_minutes") is not None
    ]
    median_confirmation_wait = round(statistics.median(confirmation_waits), 2) if confirmation_waits else 5.0

    # Per-session analysis
    sessions_default_mode = 0
    sessions_accept_edits = 0
    sessions_no_mode = 0
    total_triggering_commands = 0
    pattern_counts = defaultdict(int)  # pattern_name -> count
    triggering_by_session = []  # (session_id, count)

    for filepath in jsonl_files:
        session_id = os.path.basename(filepath).replace(".jsonl", "")

        # Determine permission mode for this session
        # permissionMode can vary within a session; collect unique modes per user entry
        session_modes = set()
        bash_commands_in_default = []  # (timestamp_approx, command) for entries under default mode

        # We need to track the "current" permissionMode as it appears on user entries,
        # then count bash commands from assistant entries that follow default-mode user entries.
        # Strategy: scan sequentially, track last-seen permissionMode, and count
        # bash calls from assistant entries when mode is "default".
        current_mode = None

        with open(filepath, "r") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    continue

                entry_type = entry.get("type")

                if entry_type == "user":
                    pm = entry.get("permissionMode")
                    if pm:
                        current_mode = pm
                        session_modes.add(pm)

                elif entry_type == "assistant" and current_mode == "default":
                    # Count bash commands that match triggering patterns
                    message = entry.get("message", {})
                    content = message.get("content", [])
                    if not isinstance(content, list):
                        continue
                    for block in content:
                        if not isinstance(block, dict):
                            continue
                        if block.get("type") != "tool_use":
                            continue
                        if block.get("name") != "Bash":
                            continue
                        cmd = block.get("input", {}).get("command", "")
                        if not cmd:
                            continue
                        for pat in PERMISSION_PATTERNS:
                            if pat.search(cmd):
                                bash_commands_in_default.append(cmd)
                                # Track which pattern matched (use first match)
                                if re.search(r'\$\(', cmd):
                                    pattern_counts["$()"] += 1
                                elif re.search(r'<<', cmd):
                                    pattern_counts["<<"] += 1
                                elif re.search(r'\{"', cmd):
                                    pattern_counts['{"'] += 1
                                break  # Only count each command once

        # Classify session by mode
        if "default" in session_modes:
            sessions_default_mode += 1
        if "acceptEdits" in session_modes:
            sessions_accept_edits += 1
        if not session_modes:
            sessions_no_mode += 1

        if bash_commands_in_default:
            triggering_by_session.append((session_id, len(bash_commands_in_default)))
            total_triggering_commands += len(bash_commands_in_default)

    # Compute estimate
    estimated_total_minutes = round(total_triggering_commands * median_confirmation_wait, 1)
    estimated_total_hours = round(estimated_total_minutes / 60.0, 2)

    return {
        "record_type": "permission_prompt_estimate",
        "sessions_with_default_mode": sessions_default_mode,
        "sessions_with_accept_edits": sessions_accept_edits,
        "sessions_no_mode_field": sessions_no_mode,
        "total_triggering_bash_commands": total_triggering_commands,
        "pattern_counts": dict(pattern_counts),
        "median_confirmation_wait_min": median_confirmation_wait,
        "estimated_total_minutes": estimated_total_minutes,
        "estimated_total_hours": estimated_total_hours,
        "sessions_with_triggers": len(triggering_by_session),
        "methodology": (
            "Upper-bound estimate. Not every pattern-matching Bash call triggers "
            "a permission prompt (static rules suppress some heuristics). Not every "
            "prompt takes as long as a confirmation AskUserQuestion (permission prompts "
            "are simpler yes/no). True cost is likely 30-50% of this estimate."
        ),
    }


def compute_orchestration_analysis(segments, tool_events, bash_commands_with_ts):
    """For orchestration/orch-coding segments, compute bd overhead vs productive split.

    Args:
        segments: list of segment dicts
        tool_events: list of (timestamp, tool_name) from all sessions
        bash_commands_with_ts: list of (timestamp, command) from all sessions

    Returns:
        dict with bd_minutes, productive_minutes, bd_fraction, productive_fraction
    """
    # Build a lookup of bash commands by timestamp for fast access
    bash_lookup = {}
    for ts, cmd in bash_commands_with_ts:
        bash_lookup[ts] = cmd

    total_bd_count = 0
    total_productive_count = 0
    total_active = 0.0

    productive_tools = {"Edit", "Write", "Read", "Agent", "Task", "Grep", "Glob"}

    for seg in segments:
        # Check if this is an orchestration or orch-coding segment
        is_orch = (seg.get("subcategory") == "orchestration" or
                   seg.get("subcategory") == "orch-coding")
        if not is_orch:
            continue

        total_active += seg["active_minutes"]

        # Count tool calls in this segment's tool_counts
        for tool_name, count in seg.get("tool_counts", {}).items():
            if tool_name == "Bash":
                # Need to check individual commands — use bd_subcommand_counts
                bd_count = sum(seg.get("bd_subcommand_counts", {}).values())
                non_bd_bash = count - bd_count
                total_bd_count += bd_count
                total_productive_count += non_bd_bash
            elif tool_name in productive_tools:
                total_productive_count += count
            # Other tools (Skill, etc.) not counted in either bucket

    total_tool_count = total_bd_count + total_productive_count
    bd_fraction = total_bd_count / total_tool_count if total_tool_count > 0 else 0
    productive_fraction = total_productive_count / total_tool_count if total_tool_count > 0 else 0

    return {
        "bd_count": total_bd_count,
        "productive_count": total_productive_count,
        "total_count": total_tool_count,
        "total_active_minutes": round(total_active, 2),
        "bd_allocated_minutes": round(total_active * bd_fraction, 2),
        "productive_allocated_minutes": round(total_active * productive_fraction, 2),
        "bd_fraction": round(bd_fraction, 4),
        "productive_fraction": round(productive_fraction, 4),
    }


def read_total_cost_from_file():
    """Read total cost from memory/cost-analysis.md.

    Looks for the total dollar amount in the Historical Daily Totals table.
    Returns total cost across all recorded days.
    """
    # Script is at .workflows/session-analysis/extract-timings.py
    # Repo root is two levels up from the script directory
    repo_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    cost_file = os.path.join(repo_root, "memory", "cost-analysis.md")
    if not os.path.exists(cost_file):
        return None

    total_cost = 0.0
    in_historical_table = False
    try:
        with open(cost_file, "r") as f:
            for line in f:
                # Look for "Historical Daily Totals" section
                if "Historical Daily Totals" in line:
                    in_historical_table = True
                    continue
                if in_historical_table:
                    # Parse table rows like: | 2026-03-10 | $209.74 | ...
                    if line.strip().startswith("|") and "$" in line:
                        parts = [p.strip() for p in line.split("|")]
                        for part in parts:
                            if part.startswith("$"):
                                try:
                                    val = float(part.replace("$", "").replace(",", ""))
                                    total_cost += val
                                    break  # Only take the first $ value per row (Total Cost)
                                except ValueError:
                                    pass
                    # Stop at next section
                    elif line.startswith("#") and in_historical_table:
                        break
    except Exception:
        return None

    return total_cost if total_cost > 0 else None


def load_bead_closures_by_date():
    """Load bead closure counts grouped by date from the database."""
    try:
        result = subprocess.run(
            [
                "bd", "sql",
                "SELECT DATE(closed_at) as date, COUNT(*) as count "
                "FROM issues WHERE status='closed' AND closed_at IS NOT NULL "
                "GROUP BY DATE(closed_at) ORDER BY date"
            ],
            capture_output=True,
            text=True,
            timeout=10,
        )
        closures = {}  # date_str -> count
        for line in result.stdout.splitlines():
            line = line.strip()
            if not line or line.startswith("-") or line.startswith("date"):
                continue
            parts = [p.strip() for p in line.split("|")]
            if len(parts) < 2:
                continue
            date_str = parts[0].strip()
            # Extract just the date portion (YYYY-MM-DD) from full timestamp
            if " " in date_str:
                date_str = date_str.split(" ")[0]
            try:
                count = int(parts[1].strip())
                closures[date_str] = count
            except (ValueError, IndexError):
                continue
        return closures
    except Exception as e:
        print(f"  WARNING: Could not load bead closures by date: {e}", file=sys.stderr)
        return {}


def count_closed_beads():
    """Count closed beads from the database."""
    try:
        result = subprocess.run(
            ["bd", "sql", "SELECT COUNT(*) FROM issues WHERE status = 'closed'"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        for line in result.stdout.splitlines():
            line = line.strip()
            if line.isdigit():
                return int(line)
    except Exception:
        pass
    return None


def format_stats_row(label, stats):
    """Format a stats dict as a markdown table row."""
    if stats["n"] == 0:
        return f"| {label} | 0 | - | - | - | - | - |"
    p90 = stats.get("p90", "-")
    return (
        f"| {label} | {stats['n']} | {stats['min']} | "
        f"{stats['median']} | {stats['mean']} | {stats['max']} | {p90} |"
    )


def main():
    jsonl_files = sorted(glob.glob(os.path.join(JSONL_DIR, "*.jsonl")))
    print(f"Found {len(jsonl_files)} JSONL files", file=sys.stderr)

    # Load known bead IDs from database
    print("Loading bead IDs from database...", file=sys.stderr)
    known_bead_ids = load_known_bead_ids()
    print(f"  Found {len(known_bead_ids)} known bead IDs", file=sys.stderr)

    # Load closed bead estimates
    print("Loading closed bead estimates...", file=sys.stderr)
    closed_bead_estimates = load_closed_bead_estimates()
    print(f"  Found {len(closed_bead_estimates)} closed beads with estimates", file=sys.stderr)

    all_sessions = []
    all_phases = []
    all_agents = []
    all_segments = []
    all_errors = []
    total_errors = 0

    # Session-level (old) bead attribution for comparison
    bead_attribution_old = defaultdict(lambda: {
        "sessions": set(),
        "total_active_minutes": 0,
        "total_wall_clock_minutes": 0,
        "phases": Counter(),
    })

    # Windowed bead attribution (new, phase 3)
    bead_attribution_windowed = defaultdict(lambda: {
        "sessions": set(),
        "total_active_minutes": 0,
        "total_wall_clock_minutes": 0,
        "phases": Counter(),
        "methods": Counter(),
        "ref_types": Counter(),
        "reference_count": 0,
    })

    # All windowed attribution records (for raw output)
    all_windowed_attributions = []

    # Session ranges for concurrent detection (sub-item 1)
    session_ranges = []  # (session_id, first_ts, last_ts)

    # Token-per-phase aggregation (sub-item 5)
    phase_token_totals = defaultdict(lambda: {
        "total_tokens": 0,
        "agent_count": 0,
        "total_duration_ms": 0,
    })

    # S2: Collect all session results for dedup and proportional analysis
    all_session_results = []
    # S2: All tool events and bash commands across sessions (for orchestration analysis)
    all_tool_events = []
    all_bash_commands_with_ts = []
    # S2: AskUserQuestion events across all sessions
    all_askuser_events = []

    # P5-S1: Project cost aggregation
    project_cost_total = 0.0
    project_cost_by_model = defaultdict(float)
    project_cost_by_phase = defaultdict(float)
    project_token_totals = defaultdict(int)  # token type -> total

    # P5-S5: Compaction cost records
    all_compaction_costs = []

    with open(RAW_OUTPUT, "w") as raw_out:
        for i, filepath in enumerate(jsonl_files):
            basename = os.path.basename(filepath)
            size_mb = os.path.getsize(filepath) / (1024 * 1024)
            print(
                f"  [{i+1}/{len(jsonl_files)}] {basename} ({size_mb:.1f} MB)",
                file=sys.stderr,
            )

            try:
                result = process_session(filepath)
            except Exception as e:
                print(
                    f"    ERROR processing {basename}: {e}", file=sys.stderr
                )
                total_errors += 1
                continue

            session = result["session"]
            phases = result["phases"]
            agents = result["agents"]
            errors = result["errors"]

            if errors:
                total_errors += len(errors)
                for err in errors[:3]:  # Log first 3 per file
                    print(f"    WARN: {err}", file=sys.stderr)

            # S2: Collect session result for dedup analysis
            all_session_results.append(result)
            all_tool_events.extend(result["tool_events"])
            all_bash_commands_with_ts.extend(result["bash_commands_with_ts"])

            # S2: Extract AskUserQuestion events
            askuser_events = extract_askuser_events(filepath)
            # P5-S3: Tag each event with session_id and workflow phase
            session_phase_windows = build_phase_windows(
                result["skill_invocations"],
                result["last_ts"],
                result.get("compact_summary_timestamps"),
            )
            for evt in askuser_events:
                evt["session_id"] = session["session_id"]
                evt["workflow"] = assign_askuser_to_workflow(
                    evt["timestamp"], session_phase_windows
                )
            all_askuser_events.extend(askuser_events)

            # Track session ranges for concurrent detection
            if result["first_ts"] and result["last_ts"]:
                session_ranges.append((
                    session["session_id"],
                    result["first_ts"],
                    result["last_ts"],
                ))

            # P5-S1: Aggregate cost data
            project_cost_total += session.get("session_cost_usd", 0)
            for model_prefix, mcost in session.get("cost_by_model", {}).items():
                project_cost_by_model[model_prefix] += mcost
            for phase_obs in phases:
                phase_name = phase_obs.get("phase", "non-workflow")
                project_cost_by_phase[phase_name] += phase_obs.get("phase_cost_usd", 0)
            # Sum tokens for overall token accounting
            for rc in result.get("request_costs", []):
                project_token_totals["input_tokens"] += rc["input_tokens"]
                project_token_totals["cache_creation_input_tokens"] += rc["cache_creation_input_tokens"]
                project_token_totals["cache_read_input_tokens"] += rc["cache_read_input_tokens"]
                project_token_totals["output_tokens"] += rc["output_tokens"]

            # P5-S5: Extract compaction costs for sessions with compaction
            if session.get("compaction_count", 0) > 0:
                session_compaction_costs = extract_compaction_costs(
                    filepath, session["session_id"]
                )
                all_compaction_costs.extend(session_compaction_costs)

            # Compute segments
            segments = compute_segments(result)

            # --- Token-per-phase aggregation (sub-item 5) ---
            # For each agent completion, determine which phase it falls in
            for agent_obs in agents:
                agent_ts_str = agent_obs.get("dispatch_timestamp")
                agent_ts = parse_timestamp(agent_ts_str) if agent_ts_str else None
                tokens = agent_obs.get("usage_total_tokens", 0)
                duration_ms = agent_obs.get("usage_duration_ms", 0)

                if not agent_ts or not tokens:
                    continue

                # Find which phase this agent belongs to
                assigned_phase = None
                skill_invocations = result["skill_invocations"]
                for idx, inv in enumerate(skill_invocations):
                    phase_start = inv["timestamp"]
                    if idx + 1 < len(skill_invocations):
                        phase_end = skill_invocations[idx + 1]["timestamp"]
                    else:
                        phase_end = result["last_ts"]
                    if phase_start and phase_end and phase_start <= agent_ts <= phase_end:
                        assigned_phase = inv["phase"]
                        break

                if not assigned_phase:
                    assigned_phase = "non-workflow"

                phase_token_totals[assigned_phase]["total_tokens"] += tokens
                phase_token_totals[assigned_phase]["agent_count"] += 1
                if duration_ms:
                    phase_token_totals[assigned_phase]["total_duration_ms"] += duration_ms

            # Extract bead IDs referenced in this session (with timestamps)
            if known_bead_ids:
                session_bead_ids, bead_ts_map, bead_ref_types = \
                    extract_bead_ids_from_session(filepath, known_bead_ids)

                if session_bead_ids:
                    session_id = session["session_id"]
                    session_active = session["active_minutes"]
                    session_wall = session["total_duration_minutes"]
                    session_phases = set()
                    for p in phases:
                        session_phases.add(p["phase"])

                    # Old session-level attribution (for comparison)
                    for bid in session_bead_ids:
                        ba = bead_attribution_old[bid]
                        ba["sessions"].add(session_id)
                        ba["total_active_minutes"] += session_active
                        ba["total_wall_clock_minutes"] += session_wall
                        for ph in session_phases:
                            ba["phases"][ph] += 1

                    # New windowed attribution (sub-items 2, 3, 4)
                    windowed_attrs = compute_windowed_bead_attribution(
                        bead_ts_map, bead_ref_types,
                        result["sorted_timestamps"],
                        result["first_ts"], result["last_ts"],
                        session_id, result["skill_invocations"],
                    )
                    all_windowed_attributions.extend(windowed_attrs)

                    for attr in windowed_attrs:
                        bid = attr["bead_id"]
                        bw = bead_attribution_windowed[bid]
                        bw["sessions"].add(session_id)
                        bw["total_active_minutes"] += attr["active_minutes"]
                        bw["total_wall_clock_minutes"] += attr["wall_clock_minutes"]
                        bw["methods"][attr["method"]] += 1
                        bw["reference_count"] += attr["reference_count"]
                        for rt in attr.get("ref_types", []):
                            bw["ref_types"][rt] += 1
                        for ph in attr.get("phases_in_window", []):
                            bw["phases"][ph] += 1
            else:
                session_bead_ids = set()

            # Write raw observations
            raw_out.write(json.dumps(session) + "\n")
            for p in phases:
                raw_out.write(json.dumps(p) + "\n")
            for a in agents:
                raw_out.write(json.dumps(a) + "\n")
            for s in segments:
                raw_out.write(json.dumps(s) + "\n")

            all_sessions.append(session)
            all_phases.extend(phases)
            all_agents.extend(agents)
            all_segments.extend(segments)

        # --- Concurrent session detection (sub-item 1) ---
        print("Detecting concurrent sessions...", file=sys.stderr)
        concurrent_overlaps = detect_concurrent_sessions(session_ranges)
        print(f"  Found {len(concurrent_overlaps)} overlapping session pairs", file=sys.stderr)
        for overlap in concurrent_overlaps:
            record = {"record_type": "concurrent_sessions", **overlap}
            raw_out.write(json.dumps(record) + "\n")

        # Write old-style bead attribution records (for comparison)
        for bid, ba in sorted(bead_attribution_old.items(), key=lambda x: x[1]["total_active_minutes"], reverse=True):
            record = {
                "record_type": "bead_attribution",
                "bead_id": bid,
                "sessions": sorted(ba["sessions"]),
                "session_count": len(ba["sessions"]),
                "total_active_minutes": round(ba["total_active_minutes"], 2),
                "total_wall_clock_minutes": round(ba["total_wall_clock_minutes"], 2),
                "phases": dict(ba["phases"]),
            }
            raw_out.write(json.dumps(record) + "\n")

        # Write windowed bead attribution records
        for attr in all_windowed_attributions:
            record = {"record_type": "bead_windowed_attribution", **attr}
            raw_out.write(json.dumps(record) + "\n")

        # Write aggregated windowed attribution
        for bid, bw in sorted(bead_attribution_windowed.items(), key=lambda x: x[1]["total_active_minutes"], reverse=True):
            record = {
                "record_type": "bead_windowed_summary",
                "bead_id": bid,
                "sessions": sorted(bw["sessions"]),
                "session_count": len(bw["sessions"]),
                "total_active_minutes": round(bw["total_active_minutes"], 2),
                "total_wall_clock_minutes": round(bw["total_wall_clock_minutes"], 2),
                "phases": dict(bw["phases"]),
                "methods": dict(bw["methods"]),
                "ref_types": dict(bw["ref_types"]),
                "reference_count": bw["reference_count"],
            }
            raw_out.write(json.dumps(record) + "\n")

        # Write phase token aggregation records (sub-item 5)
        for phase, tokens in sorted(phase_token_totals.items(), key=lambda x: x[1]["total_tokens"], reverse=True):
            record = {
                "record_type": "phase_tokens",
                "phase": phase,
                "total_tokens": tokens["total_tokens"],
                "agent_count": tokens["agent_count"],
                "total_duration_ms": tokens["total_duration_ms"],
            }
            raw_out.write(json.dumps(record) + "\n")

        # --- P5-S1: Project cost record ---
        print("Computing project cost from JSONL...", file=sys.stderr)
        # Non-workflow cost = total - sum of all phase costs
        phase_cost_sum = sum(project_cost_by_phase.values())
        non_workflow_cost = project_cost_total - phase_cost_sum
        if abs(non_workflow_cost) > 0.000001:
            project_cost_by_phase["non-workflow"] += non_workflow_cost

        project_cost_record = {
            "record_type": "project_cost",
            "total_cost_usd": round(project_cost_total, 2),
            "cost_by_model": {k: round(v, 2) for k, v in sorted(
                project_cost_by_model.items(), key=lambda x: x[1], reverse=True
            )},
            "cost_by_phase": {k: round(v, 2) for k, v in sorted(
                project_cost_by_phase.items(), key=lambda x: x[1], reverse=True
            )},
            "token_totals": dict(project_token_totals),
            "request_count": sum(
                s.get("entry_count", 0) for s in all_sessions
            ),
        }
        raw_out.write(json.dumps(project_cost_record) + "\n")
        print(f"  Project cost: ${project_cost_total:.2f}", file=sys.stderr)
        for mp, mc in sorted(project_cost_by_model.items(), key=lambda x: x[1], reverse=True):
            print(f"    {mp}: ${mc:.2f}", file=sys.stderr)

        # --- P5-S2: Stats YAML mining ---
        print("Mining stats YAML files...", file=sys.stderr)
        stats_entries = load_stats_yaml_entries()
        stats_timing_data = compute_stats_step_timing(stats_entries, closed_bead_estimates)
        for rec in stats_timing_data["records"]:
            raw_out.write(json.dumps(rec) + "\n")
        print(f"  Stats: {stats_timing_data['total_entries']} entries, "
              f"{len(stats_timing_data['by_command'])} commands, "
              f"{len(stats_timing_data['estimate_vs_actual'])} bead estimate matches",
              file=sys.stderr)

        # --- S2: Deduplicated active time ---
        print("Computing deduplicated active time...", file=sys.stderr)
        dedup_data = compute_dedup_active_minutes(all_session_results)
        dedup_record = {"record_type": "dedup_active_time", **dedup_data}
        # Remove non-serializable merged_intervals (already serialized as strings)
        raw_out.write(json.dumps(dedup_record) + "\n")
        print(f"  Dedup active: {dedup_data['dedup_active_minutes']} min, "
              f"Merged wall-clock: {dedup_data['merged_wall_clock_minutes']} min",
              file=sys.stderr)

        # --- S2: Proportional tool-call allocation per segment ---
        print("Computing proportional tool-call allocations...", file=sys.stderr)
        # We need tool_events and bash_commands per session, already collected
        # Compute per-segment allocations for the 6 major buckets
        proportional_records = []
        # Define major buckets of interest
        major_bucket_categories = {
            "work": lambda seg: seg.get("phase") == "work",
            "coding": lambda seg: seg["category"] == "coding",
            "brainstorm": lambda seg: seg.get("phase") == "brainstorm",
            "orchestration": lambda seg: (seg.get("subcategory") == "orchestration"
                                          or seg.get("subcategory") == "orch-coding"),
            "plan": lambda seg: seg.get("phase") in ("plan", "deepen-plan"),
            "interactive-dev": lambda seg: seg.get("subcategory") == "interactive-dev",
        }

        for bucket_name, filter_fn in major_bucket_categories.items():
            matching_segs = [seg for seg in all_segments if filter_fn(seg)]
            if not matching_segs:
                continue

            # Aggregate tool call counts across matching segments
            agg_buckets = Counter()
            total_active_for_bucket = 0.0
            total_tool_count = 0
            for seg in matching_segs:
                total_active_for_bucket += seg["active_minutes"]
                for tool_name, count in seg.get("tool_counts", {}).items():
                    if tool_name == "Bash":
                        # Check each bash command for bd
                        bd_count = sum(seg.get("bd_subcommand_counts", {}).values())
                        agg_buckets["bd"] += bd_count
                        agg_buckets["other"] += count - bd_count
                    else:
                        tb = TOOL_BUCKET_MAP.get(tool_name, "other")
                        agg_buckets[tb] += count
                    total_tool_count += count

            if total_tool_count == 0:
                continue

            alloc = {}
            for tb, count in agg_buckets.items():
                frac = count / total_tool_count
                alloc[tb] = {
                    "count": count,
                    "fraction": round(frac, 4),
                    "allocated_minutes": round(total_active_for_bucket * frac, 2),
                }

            prop_record = {
                "record_type": "proportional_allocation",
                "bucket": bucket_name,
                "segment_count": len(matching_segs),
                "total_active_minutes": round(total_active_for_bucket, 2),
                "total_tool_calls": total_tool_count,
                "allocation": alloc,
            }
            proportional_records.append(prop_record)
            raw_out.write(json.dumps(prop_record) + "\n")

        # --- S2: AskUserQuestion categorization ---
        print(f"Categorizing {len(all_askuser_events)} AskUserQuestion events...",
              file=sys.stderr)
        askuser_by_category = defaultdict(lambda: {"count": 0, "total_wait_minutes": 0.0})
        for evt in all_askuser_events:
            cat = evt["category"]
            askuser_by_category[cat]["count"] += 1
            if evt["wait_minutes"] is not None:
                askuser_by_category[cat]["total_wait_minutes"] += evt["wait_minutes"]

        askuser_record = {
            "record_type": "askuser_categorization",
            "total_events": len(all_askuser_events),
            "categories": {
                cat: {
                    "count": data["count"],
                    "total_wait_minutes": round(data["total_wait_minutes"], 2),
                    "avg_wait_minutes": round(
                        data["total_wait_minutes"] / data["count"], 2
                    ) if data["count"] > 0 else 0,
                }
                for cat, data in askuser_by_category.items()
            },
        }
        raw_out.write(json.dumps(askuser_record) + "\n")

        # --- P5-S3: AskUserQuestion per-workflow breakdown ---
        print("Breaking down AskUserQuestion events by workflow...",
              file=sys.stderr)
        # All events by workflow
        all_by_workflow = defaultdict(lambda: {"count": 0, "total_wait_minutes": 0.0})
        # Confirmation events by workflow
        confirm_by_workflow = defaultdict(lambda: {"count": 0, "total_wait_minutes": 0.0})
        # All categories by workflow (nested: workflow -> category -> count)
        cats_by_workflow = defaultdict(lambda: defaultdict(int))

        for evt in all_askuser_events:
            wf = evt.get("workflow", "non-workflow")
            cat = evt["category"]

            all_by_workflow[wf]["count"] += 1
            if evt["wait_minutes"] is not None:
                all_by_workflow[wf]["total_wait_minutes"] += evt["wait_minutes"]

            cats_by_workflow[wf][cat] += 1

            if cat == "confirmation":
                confirm_by_workflow[wf]["count"] += 1
                if evt["wait_minutes"] is not None:
                    confirm_by_workflow[wf]["total_wait_minutes"] += evt["wait_minutes"]

        # Build the record
        askuser_per_workflow_record = {
            "record_type": "askuser_per_workflow",
            "total_events": len(all_askuser_events),
            "total_confirmation_events": sum(
                d["count"] for d in confirm_by_workflow.values()
            ),
            "all_by_workflow": {
                wf: {
                    "count": data["count"],
                    "total_wait_minutes": round(data["total_wait_minutes"], 2),
                    "avg_wait_minutes": round(
                        data["total_wait_minutes"] / data["count"], 2
                    ) if data["count"] > 0 else 0,
                }
                for wf, data in all_by_workflow.items()
            },
            "confirmation_by_workflow": {
                wf: {
                    "count": data["count"],
                    "total_wait_minutes": round(data["total_wait_minutes"], 2),
                    "avg_wait_minutes": round(
                        data["total_wait_minutes"] / data["count"], 2
                    ) if data["count"] > 0 else 0,
                }
                for wf, data in confirm_by_workflow.items()
            },
            "categories_by_workflow": {
                wf: dict(cats)
                for wf, cats in cats_by_workflow.items()
            },
        }
        raw_out.write(json.dumps(askuser_per_workflow_record) + "\n")

        # --- P5-S4: Estimation accuracy segmentation ---
        print("Computing estimation accuracy segments...", file=sys.stderr)
        estimation_segment_data = compute_estimation_segments(
            closed_bead_estimates, bead_attribution_windowed
        )
        if estimation_segment_data["bead_count"] > 0:
            est_seg_record = {
                "record_type": "estimation_segments",
                "bead_count": estimation_segment_data["bead_count"],
                "segments": estimation_segment_data["segments"],
            }
            raw_out.write(json.dumps(est_seg_record) + "\n")
            # Also emit per-bead detail records
            for rec in estimation_segment_data["records"]:
                detail_record = {"record_type": "estimation_segment_detail", **rec}
                raw_out.write(json.dumps(detail_record) + "\n")
            print(f"  Segmented {estimation_segment_data['bead_count']} beads across "
                  f"{len(estimation_segment_data['segments'])} dimensions",
                  file=sys.stderr)
        else:
            estimation_segment_data = None
            print("  No beads with both estimates and windowed attribution", file=sys.stderr)

        # --- P5-S5: Compaction cost ---
        print(f"Computing compaction costs ({len(all_compaction_costs)} events)...",
              file=sys.stderr)
        for cc in all_compaction_costs:
            record = {"record_type": "compaction_cost", **cc}
            raw_out.write(json.dumps(record) + "\n")

        # Aggregate compaction cost stats
        compaction_cost_data = None
        if all_compaction_costs:
            costs = [cc["token_cost"] for cc in all_compaction_costs]
            reorient_times = [
                cc["reorientation_minutes"]
                for cc in all_compaction_costs
                if cc["reorientation_minutes"] is not None
            ]
            compaction_cost_data = {
                "event_count": len(all_compaction_costs),
                "total_cost_usd": round(sum(costs), 4),
                "median_cost_usd": round(statistics.median(costs), 4) if costs else 0,
                "mean_cost_usd": round(statistics.mean(costs), 4) if costs else 0,
                "max_cost_usd": round(max(costs), 4) if costs else 0,
                "min_cost_usd": round(min(costs), 4) if costs else 0,
                "reorientation_event_count": len(reorient_times),
                "median_reorientation_minutes": round(
                    statistics.median(reorient_times), 2
                ) if reorient_times else None,
                "mean_reorientation_minutes": round(
                    statistics.mean(reorient_times), 2
                ) if reorient_times else None,
                "max_reorientation_minutes": round(
                    max(reorient_times), 2
                ) if reorient_times else None,
                "total_reorientation_minutes": round(
                    sum(reorient_times), 2
                ) if reorient_times else None,
                "sessions_with_compaction": len(set(
                    cc["session"] for cc in all_compaction_costs
                )),
            }
            summary_record = {
                "record_type": "compaction_cost_summary",
                **compaction_cost_data,
            }
            raw_out.write(json.dumps(summary_record) + "\n")
            print(f"  Compaction: {len(all_compaction_costs)} events, "
                  f"total cost ${sum(costs):.2f}, "
                  f"median reorientation {compaction_cost_data.get('median_reorientation_minutes', 'N/A')} min",
                  file=sys.stderr)
        else:
            print("  No compaction events found", file=sys.stderr)

        # --- P5-S6: Velocity trend ---
        print("Computing velocity trend...", file=sys.stderr)
        bead_closures_by_date = load_bead_closures_by_date()

        # Bucket active time by date from session data
        active_minutes_by_date = defaultdict(float)
        for result in all_session_results:
            if result["first_ts"]:
                date_str = result["first_ts"].date().isoformat()
                session_active = result["session"]["active_minutes"]
                active_minutes_by_date[date_str] += session_active

        # Collect all dates from both sources
        all_trend_dates = sorted(set(
            list(bead_closures_by_date.keys()) +
            list(active_minutes_by_date.keys())
        ))

        velocity_trend_records = []
        for date_str in all_trend_dates:
            beads_closed = bead_closures_by_date.get(date_str, 0)
            active_min = round(active_minutes_by_date.get(date_str, 0), 1)
            active_hrs = round(active_min / 60.0, 2)
            beads_per_hour = round(beads_closed / active_hrs, 2) if active_hrs > 0 else None
            rec = {
                "record_type": "velocity_trend",
                "date": date_str,
                "beads_closed": beads_closed,
                "active_minutes": active_min,
                "active_hours": active_hrs,
                "beads_per_hour": beads_per_hour,
            }
            velocity_trend_records.append(rec)
            raw_out.write(json.dumps(rec) + "\n")

        # Compute overall velocity summary
        total_beads_closed = sum(r["beads_closed"] for r in velocity_trend_records)
        total_active_hrs = sum(r["active_hours"] for r in velocity_trend_records)
        beads_per_day_values = [r["beads_closed"] for r in velocity_trend_records if r["beads_closed"] > 0]
        active_hrs_per_day_values = [r["active_hours"] for r in velocity_trend_records if r["active_hours"] > 0]

        velocity_trend_summary = {
            "record_type": "velocity_trend_summary",
            "date_count": len(all_trend_dates),
            "total_beads_closed": total_beads_closed,
            "total_active_hours": round(total_active_hrs, 2),
            "overall_beads_per_hour": round(total_beads_closed / total_active_hrs, 2) if total_active_hrs > 0 else None,
            "median_beads_per_day": round(statistics.median(beads_per_day_values), 1) if beads_per_day_values else None,
            "mean_beads_per_day": round(statistics.mean(beads_per_day_values), 1) if beads_per_day_values else None,
            "median_active_hours_per_day": round(statistics.median(active_hrs_per_day_values), 2) if active_hrs_per_day_values else None,
            "mean_active_hours_per_day": round(statistics.mean(active_hrs_per_day_values), 2) if active_hrs_per_day_values else None,
            "records": velocity_trend_records,
        }
        raw_out.write(json.dumps(velocity_trend_summary) + "\n")
        print(f"  Velocity: {len(all_trend_dates)} dates, "
              f"{total_beads_closed} beads closed, "
              f"{round(total_active_hrs, 1)} active hours",
              file=sys.stderr)

        # --- S2: Orchestration analysis ---
        print("Computing orchestration analysis...", file=sys.stderr)
        orch_analysis = compute_orchestration_analysis(
            all_segments, all_tool_events, all_bash_commands_with_ts
        )
        orch_record = {"record_type": "orchestration_analysis", **orch_analysis}
        raw_out.write(json.dumps(orch_record) + "\n")

        # --- P5-S7: Permission prompt estimate ---
        print("Estimating permission prompt overhead...", file=sys.stderr)
        permission_prompt_data = compute_permission_prompt_estimate(
            jsonl_files, all_askuser_events
        )
        raw_out.write(json.dumps(permission_prompt_data) + "\n")
        print(f"  Permission prompts: {permission_prompt_data['total_triggering_bash_commands']} "
              f"triggering commands in {permission_prompt_data['sessions_with_triggers']} sessions, "
              f"est {permission_prompt_data['estimated_total_hours']} hours upper bound",
              file=sys.stderr)

        # --- S2: Headline metrics ---
        print("Computing headline metrics...", file=sys.stderr)
        total_cost = read_total_cost_from_file()
        closed_bead_count = count_closed_beads()

        # Compute active days (unique dates from session start timestamps)
        active_dates = set()
        for result in all_session_results:
            if result["first_ts"]:
                active_dates.add(result["first_ts"].date())
        active_days = len(active_dates)

        # Compute overhead ratio from proportional allocation
        total_bd_minutes = 0.0
        total_alloc_active = 0.0
        for pr in proportional_records:
            alloc = pr.get("allocation", {})
            if "bd" in alloc:
                total_bd_minutes += alloc["bd"]["allocated_minutes"]
            total_alloc_active += pr["total_active_minutes"]

        # Automation ratio (Agent/Task tool calls / total tool calls)
        global_tools = Counter()
        for s in all_sessions:
            for tool, count in s.get("tool_counts", {}).items():
                global_tools[tool] += count
        total_tool_calls = sum(global_tools.values())
        agent_task_calls = global_tools.get("Agent", 0) + global_tools.get("Task", 0)
        automation_ratio = agent_task_calls / total_tool_calls if total_tool_calls > 0 else 0

        # Estimation accuracy (already computed in section 13 — extract median ratio)
        estimate_ratios = []
        for bid, est_data in closed_bead_estimates.items():
            if bid in bead_attribution_windowed:
                bw = bead_attribution_windowed[bid]
                actual = bw["total_active_minutes"]
                estimated = est_data["estimated_minutes"]
                if estimated > 0:
                    estimate_ratios.append(actual / estimated)
        median_estimate_ratio = round(statistics.median(estimate_ratios), 2) if estimate_ratios else None

        dedup_active_hours = round(dedup_data["dedup_active_minutes"] / 60.0, 2)
        merged_wall_hours = round(dedup_data["merged_wall_clock_minutes"] / 60.0, 2)
        # Use JSONL-computed cost if available, fall back to cost-analysis.md
        effective_cost = round(project_cost_total, 2) if project_cost_total > 0 else total_cost
        cost_per_active_hour = round(effective_cost / dedup_active_hours, 2) if effective_cost and dedup_active_hours > 0 else None
        overhead_ratio = round(total_bd_minutes / dedup_data["dedup_active_minutes"], 4) if dedup_data["dedup_active_minutes"] > 0 else None
        beads_per_day = round(closed_bead_count / active_days, 1) if closed_bead_count and active_days > 0 else None
        active_min_per_bead = round(dedup_data["dedup_active_minutes"] / closed_bead_count, 1) if closed_bead_count and closed_bead_count > 0 else None

        # Phase skip rate: beads with "work" phase but no "brainstorm" or "deepen-plan"
        beads_with_work = 0
        beads_skipped_planning = 0
        for bid, bw in bead_attribution_windowed.items():
            phases_seen = set(bw["phases"].keys())
            if "work" in phases_seen:
                beads_with_work += 1
                if "brainstorm" not in phases_seen and "deepen-plan" not in phases_seen:
                    beads_skipped_planning += 1
        phase_skip_rate = round(beads_skipped_planning / beads_with_work, 4) if beads_with_work > 0 else None

        headline_record = {
            "record_type": "headline_metrics",
            "dedup_active_minutes": dedup_data["dedup_active_minutes"],
            "dedup_active_hours": dedup_active_hours,
            "merged_wall_clock_hours": merged_wall_hours,
            "total_cost_usd_ccusage": total_cost,
            "total_cost_usd_jsonl": round(project_cost_total, 2) if project_cost_total > 0 else None,
            "cost_per_active_hour": cost_per_active_hour,
            "overhead_ratio": overhead_ratio,
            "automation_ratio": round(automation_ratio, 4),
            "closed_bead_count": closed_bead_count,
            "active_days": active_days,
            "beads_per_day": beads_per_day,
            "active_min_per_bead": active_min_per_bead,
            "median_estimate_ratio": median_estimate_ratio,
            "phase_skip_rate": phase_skip_rate,
            "beads_with_work": beads_with_work,
            "beads_skipped_planning": beads_skipped_planning,
        }
        raw_out.write(json.dumps(headline_record) + "\n")

    print(f"\nProcessed {len(all_sessions)} sessions", file=sys.stderr)
    print(f"Found {len(all_phases)} phase observations", file=sys.stderr)
    print(f"Found {len(all_agents)} agent observations", file=sys.stderr)
    print(f"Found {len(all_segments)} segment observations", file=sys.stderr)
    print(f"Found {len(bead_attribution_old)} beads with old session-level attribution", file=sys.stderr)
    print(f"Found {len(bead_attribution_windowed)} beads with windowed attribution", file=sys.stderr)
    print(f"Found {len(concurrent_overlaps)} concurrent session pairs", file=sys.stderr)
    print(f"Found {len(all_askuser_events)} AskUserQuestion events", file=sys.stderr)
    print(f"Total parse errors: {total_errors}", file=sys.stderr)

    # --- Generate summary ---
    generate_summary(
        all_sessions, all_phases, all_agents, all_segments,
        bead_attribution_old, bead_attribution_windowed,
        closed_bead_estimates, concurrent_overlaps, phase_token_totals,
        dedup_data, proportional_records, askuser_record,
        orch_analysis, headline_record, project_cost_record,
        stats_timing_data, askuser_per_workflow_record,
        estimation_segment_data, compaction_cost_data,
        all_compaction_costs, velocity_trend_summary,
        permission_prompt_data,
    )
    print(f"\nWrote {RAW_OUTPUT}", file=sys.stderr)
    print(f"Wrote {SUMMARY_OUTPUT}", file=sys.stderr)


def generate_summary(sessions, phases, agents, segments, bead_attribution_old,
                     bead_attribution_windowed, closed_bead_estimates,
                     concurrent_overlaps, phase_token_totals,
                     dedup_data, proportional_records, askuser_record,
                     orch_analysis, headline_record, project_cost_record=None,
                     stats_timing_data=None, askuser_per_workflow=None,
                     estimation_segment_data=None, compaction_cost_data=None,
                     compaction_cost_details=None,
                     velocity_trend_data=None,
                     permission_prompt_data=None):
    """Generate the summary.md file."""
    lines = []
    lines.append("# Session Analysis Summary")
    lines.append("")
    lines.append(
        f"Generated from {len(sessions)} sessions, "
        f"{len(phases)} phase observations, "
        f"{len(agents)} agent observations, "
        f"{len(segments)} segment observations."
    )
    lines.append("")

    # =========================================
    # 1. SESSION HEALTH METRICS
    # =========================================
    lines.append("## 1. Session Health Metrics")
    lines.append("")

    durations = [
        s["total_duration_minutes"]
        for s in sessions
        if s["total_duration_minutes"] > 0
    ]
    dur_stats = compute_stats(durations)

    active_durations = [
        s["active_minutes"]
        for s in sessions
        if s["active_minutes"] > 0
    ]
    active_dur_stats = compute_stats(active_durations)

    idle_durations = [
        s["idle_minutes"]
        for s in sessions
        if s["idle_minutes"] > 0
    ]
    idle_dur_stats = compute_stats(idle_durations)

    entry_counts = [s["entry_count"] for s in sessions if s["entry_count"] > 0]
    entry_stats = compute_stats(entry_counts)

    user_msgs = [
        s["user_message_count"]
        for s in sessions
        if s["user_message_count"] > 0
    ]
    user_msg_stats = compute_stats(user_msgs)

    corrections = [s["correction_count"] for s in sessions]
    correction_stats = compute_stats(corrections)

    compactions = [s["compaction_count"] for s in sessions]
    sessions_with_compaction = sum(1 for c in compactions if c > 0)
    compaction_rate = (
        round(sessions_with_compaction / len(sessions) * 100, 1)
        if sessions
        else 0
    )

    git_commits = [s["git_commit_count"] for s in sessions]
    git_commit_stats = compute_stats(git_commits)

    lines.append("| Metric | N | Min | Median | Mean | Max | P90 |")
    lines.append("|--------|---|-----|--------|------|-----|-----|")
    lines.append(format_stats_row("Session wall-clock (min)", dur_stats))
    lines.append(format_stats_row("Session active time (min)", active_dur_stats))
    lines.append(format_stats_row("Session idle time (min)", idle_dur_stats))
    lines.append(format_stats_row("JSONL entries per session", entry_stats))
    lines.append(format_stats_row("User messages per session", user_msg_stats))
    lines.append(format_stats_row("Corrections per session", correction_stats))
    lines.append(format_stats_row("Git commits per session", git_commit_stats))
    lines.append("")
    lines.append(
        f"**Compaction rate:** {sessions_with_compaction}/{len(sessions)} "
        f"sessions ({compaction_rate}%)"
    )
    lines.append("")

    # Sessions with skill invocations
    sessions_with_skills = sum(
        1 for s in sessions if s["skill_invocation_count"] > 0
    )
    lines.append(
        f"**Sessions using workflow skills:** {sessions_with_skills}/{len(sessions)} "
        f"({round(sessions_with_skills/len(sessions)*100, 1) if sessions else 0}%)"
    )
    lines.append("")

    # =========================================
    # 2. PHASE TIMING STATISTICS
    # =========================================
    lines.append("## 2. Phase Timing Statistics")
    lines.append("")
    lines.append(
        "Wall-clock = skill invocation to next skill invocation (or end of session). "
        "Active = wall-clock minus idle gaps (>= 5 min). "
        "Idle threshold: 300s (99.6% of inter-entry gaps fall below this)."
    )
    lines.append("")

    # Group phases
    phase_durations = defaultdict(list)
    phase_active = defaultdict(list)
    phase_idle = defaultdict(list)
    for p in phases:
        if p.get("duration_minutes") is not None and p["duration_minutes"] > 0:
            phase_durations[p["phase"]].append(p["duration_minutes"])
            phase_active[p["phase"]].append(p.get("active_minutes", 0))
            phase_idle[p["phase"]].append(p.get("idle_minutes", 0))

    lines.append(
        "| Phase | N | Wall-clock Median | Active Median | Active Mean | Active P90 | Idle Median |"
    )
    lines.append(
        "|-------|---|-------------------|---------------|-------------|------------|-------------|"
    )

    # Sort by count descending
    for phase_name in sorted(
        phase_durations.keys(), key=lambda k: len(phase_durations[k]), reverse=True
    ):
        wc_stats = compute_stats(phase_durations[phase_name])
        act_stats = compute_stats(phase_active[phase_name])
        idle_stats = compute_stats(phase_idle[phase_name])

        wc_med = wc_stats.get("median", "-")
        act_med = act_stats.get("median", "-")
        act_mean = act_stats.get("mean", "-")
        act_p90 = act_stats.get("p90", "-")
        idle_med = idle_stats.get("median", "-")
        n = wc_stats["n"]

        lines.append(
            f"| {phase_name} | {n} | {wc_med} | {act_med} | {act_mean} | {act_p90} | {idle_med} |"
        )

    lines.append("")

    # Total phase count per type
    phase_counts = Counter(p["phase"] for p in phases)
    lines.append("**Phase invocation counts:**")
    lines.append("")
    for phase_name, count in phase_counts.most_common():
        lines.append(f"- {phase_name}: {count}")
    lines.append("")

    # =========================================
    # 2a. ACTIVE VS WALL-CLOCK COMPARISON
    # =========================================
    lines.append("## 2a. Active vs Wall-Clock Comparison")
    lines.append("")
    lines.append(
        "How much idle time inflates each phase. "
        "Active ratio = active median / wall-clock median."
    )
    lines.append("")

    lines.append(
        "| Phase | N | Wall-clock Median | Active Median | Idle Median | Active Ratio |"
    )
    lines.append(
        "|-------|---|-------------------|---------------|-------------|--------------|"
    )

    for phase_name in sorted(
        phase_durations.keys(), key=lambda k: len(phase_durations[k]), reverse=True
    ):
        wc_stats = compute_stats(phase_durations[phase_name])
        act_stats = compute_stats(phase_active[phase_name])
        idle_stats = compute_stats(phase_idle[phase_name])

        wc_med = wc_stats.get("median", 0)
        act_med = act_stats.get("median", 0)
        idle_med = idle_stats.get("median", 0)
        n = wc_stats["n"]

        if isinstance(wc_med, (int, float)) and wc_med > 0:
            ratio = round(act_med / wc_med * 100, 1) if isinstance(act_med, (int, float)) else "-"
        else:
            ratio = "-"

        ratio_str = f"{ratio}%" if isinstance(ratio, (int, float)) else ratio

        lines.append(
            f"| {phase_name} | {n} | {wc_med} | {act_med} | {idle_med} | {ratio_str} |"
        )

    lines.append("")

    # =========================================
    # 3. AGENT DURATION STATISTICS
    # =========================================
    lines.append("## 3. Agent/Task Duration Statistics")
    lines.append("")

    # Group by subagent_type
    agent_by_type = defaultdict(list)
    agent_by_type_wallclock = defaultdict(list)
    for a in agents:
        stype = a.get("subagent_type") or "unknown"
        if a.get("usage_duration_ms"):
            agent_by_type[stype].append(a["usage_duration_ms"] / 1000.0)  # to seconds
        if a.get("wall_clock_duration_ms"):
            agent_by_type_wallclock[stype].append(
                a["wall_clock_duration_ms"] / 1000.0
            )

    lines.append("### By subagent_type (usage-reported duration, seconds)")
    lines.append("")
    lines.append("| Subagent Type | N | Min (s) | Median | Mean | Max | P90 |")
    lines.append("|---------------|---|---------|--------|------|-----|-----|")

    for stype in sorted(
        agent_by_type.keys(),
        key=lambda k: len(agent_by_type[k]),
        reverse=True,
    ):
        stats = compute_stats(agent_by_type[stype])
        lines.append(format_stats_row(stype, stats))

    lines.append("")

    lines.append("### By subagent_type (wall-clock duration, seconds)")
    lines.append("")
    lines.append("| Subagent Type | N | Min (s) | Median | Mean | Max | P90 |")
    lines.append("|---------------|---|---------|--------|------|-----|-----|")

    for stype in sorted(
        agent_by_type_wallclock.keys(),
        key=lambda k: len(agent_by_type_wallclock[k]),
        reverse=True,
    ):
        stats = compute_stats(agent_by_type_wallclock[stype])
        lines.append(format_stats_row(stype, stats))

    lines.append("")

    # Token usage by subagent type
    agent_tokens = defaultdict(list)
    agent_tool_uses = defaultdict(list)
    for a in agents:
        stype = a.get("subagent_type") or "unknown"
        if a.get("usage_total_tokens"):
            agent_tokens[stype].append(a["usage_total_tokens"])
        if a.get("usage_tool_uses"):
            agent_tool_uses[stype].append(a["usage_tool_uses"])

    lines.append("### Token usage by subagent_type")
    lines.append("")
    lines.append("| Subagent Type | N | Min | Median | Mean | Max | P90 |")
    lines.append("|---------------|---|-----|--------|------|-----|-----|")

    for stype in sorted(
        agent_tokens.keys(),
        key=lambda k: len(agent_tokens[k]),
        reverse=True,
    ):
        stats = compute_stats(agent_tokens[stype])
        lines.append(format_stats_row(stype, stats))

    lines.append("")

    # =========================================
    # 4. TOOL CALL DISTRIBUTION
    # =========================================
    lines.append("## 4. Tool Call Distribution")
    lines.append("")

    # Global tool counts
    global_tools = Counter()
    for s in sessions:
        for tool, count in s.get("tool_counts", {}).items():
            global_tools[tool] += count

    total_tool_calls = sum(global_tools.values())
    lines.append(f"**Total tool calls across all sessions:** {total_tool_calls}")
    lines.append("")
    lines.append("| Tool | Count | % of Total |")
    lines.append("|------|-------|------------|")

    for tool, count in global_tools.most_common():
        pct = round(count / total_tool_calls * 100, 1) if total_tool_calls else 0
        lines.append(f"| {tool} | {count} | {pct}% |")

    lines.append("")

    # Tool distribution per phase
    lines.append("### Tool calls per phase")
    lines.append("")

    phase_tool_totals = defaultdict(Counter)
    for p in phases:
        phase_name = p["phase"]
        for tool, count in p.get("tool_counts", {}).items():
            phase_tool_totals[phase_name][tool] += count

    # Get all tool names used
    all_tools_in_phases = set()
    for tc in phase_tool_totals.values():
        all_tools_in_phases.update(tc.keys())
    all_tools_sorted = sorted(all_tools_in_phases)

    # Build header
    header = "| Phase | " + " | ".join(all_tools_sorted) + " | Total |"
    sep = "|-------|" + "|".join(["------"] * len(all_tools_sorted)) + "|-------|"
    lines.append(header)
    lines.append(sep)

    for phase_name in sorted(
        phase_tool_totals.keys(),
        key=lambda k: sum(phase_tool_totals[k].values()),
        reverse=True,
    ):
        tc = phase_tool_totals[phase_name]
        total = sum(tc.values())
        cells = [str(tc.get(t, 0)) for t in all_tools_sorted]
        lines.append(f"| {phase_name} | " + " | ".join(cells) + f" | {total} |")

    lines.append("")

    # =========================================
    # 5. AGENT DESCRIPTIONS (MOST COMMON)
    # =========================================
    lines.append("## 5. Most Common Agent Descriptions")
    lines.append("")

    desc_counter = Counter()
    for a in agents:
        desc = a.get("description", "")
        if desc:
            # Normalize: lowercase, strip trailing whitespace
            desc_counter[desc] += 1

    lines.append("| Description | Count |")
    lines.append("|-------------|-------|")
    for desc, count in desc_counter.most_common(25):
        # Truncate long descriptions
        display = desc[:80] + "..." if len(desc) > 80 else desc
        # Escape pipes
        display = display.replace("|", "\\|")
        lines.append(f"| {display} | {count} |")

    lines.append("")

    # =========================================
    # 6. PHASE SEQUENCE PATTERNS
    # =========================================
    lines.append("## 6. Phase Sequence Patterns")
    lines.append("")
    lines.append(
        "Most common phase sequences observed within sessions "
        "(consecutive skill invocations)."
    )
    lines.append("")

    # Extract phase sequences per session
    session_phases = defaultdict(list)
    for p in phases:
        session_phases[p["session_id"]].append(p["phase"])

    sequence_counter = Counter()
    for sid, phase_list in session_phases.items():
        if len(phase_list) < 2:
            continue
        # Record pairs
        for i in range(len(phase_list) - 1):
            pair = f"{phase_list[i]} -> {phase_list[i+1]}"
            sequence_counter[pair] += 1
        # Record full sequence
        full = " -> ".join(phase_list)
        sequence_counter[f"[full] {full}"] += 1

    lines.append("### Consecutive phase transitions")
    lines.append("")
    lines.append("| Transition | Count |")
    lines.append("|------------|-------|")
    for seq, count in sorted(
        [(k, v) for k, v in sequence_counter.items() if not k.startswith("[full]")],
        key=lambda x: x[1],
        reverse=True,
    )[:20]:
        lines.append(f"| {seq} | {count} |")

    lines.append("")
    lines.append("### Full session phase sequences (top 15)")
    lines.append("")
    lines.append("| Sequence | Count |")
    lines.append("|----------|-------|")
    for seq, count in sorted(
        [(k, v) for k, v in sequence_counter.items() if k.startswith("[full]")],
        key=lambda x: x[1],
        reverse=True,
    )[:15]:
        display = seq.replace("[full] ", "")
        lines.append(f"| {display} | {count} |")

    lines.append("")

    # =========================================
    # 7. SESSION DURATION DISTRIBUTION
    # =========================================
    lines.append("## 7. Session Duration Distribution")
    lines.append("")

    buckets = [
        (0, 5, "0-5 min"),
        (5, 15, "5-15 min"),
        (15, 30, "15-30 min"),
        (30, 60, "30-60 min"),
        (60, 120, "1-2 hours"),
        (120, 240, "2-4 hours"),
        (240, 480, "4-8 hours"),
        (480, float("inf"), "8+ hours"),
    ]

    bucket_counts = Counter()
    for d in durations:
        for lo, hi, label in buckets:
            if lo <= d < hi:
                bucket_counts[label] += 1
                break

    lines.append("| Duration Bucket | Sessions | % |")
    lines.append("|----------------|----------|---|")
    for lo, hi, label in buckets:
        count = bucket_counts.get(label, 0)
        pct = round(count / len(durations) * 100, 1) if durations else 0
        bar = "#" * int(pct / 2)  # Simple text bar
        lines.append(f"| {label} | {count} | {pct}% {bar} |")

    lines.append("")

    # =========================================
    # 8. RAW DATA SUMMARY
    # =========================================
    lines.append("## 8. Raw Data Reference")
    lines.append("")
    lines.append(
        f"- **Raw observations file:** `raw-observations.jsonl`"
    )
    lines.append(f"- **Total sessions:** {len(sessions)}")
    lines.append(f"- **Total phase observations:** {len(phases)}")
    lines.append(f"- **Total agent observations:** {len(agents)}")
    lines.append(f"- **Total segment observations:** {len(segments)}")

    # Count sessions with no activity
    empty_sessions = sum(
        1 for s in sessions if s["entry_count"] <= 2
    )
    lines.append(f"- **Near-empty sessions (<=2 entries):** {empty_sessions}")
    lines.append(f"- **Idle threshold:** {IDLE_THRESHOLD_SECONDS}s (5 minutes)")

    lines.append("")

    # =========================================
    # 9. NON-WORKFLOW ACTIVITY CATEGORIES
    # =========================================
    lines.append("## 9. Non-Workflow Activity Categories")
    lines.append("")
    lines.append(
        "Every session segment classified by dominant activity. "
        "Categories: coding (Edit+Write >= 30%), light-coding (Edit+Write >= 15%, "
        "subcats: orch-coding, interactive-dev, iterating, plain), "
        "exploration (Read+Grep+Glob >= 25%, merged from old research+exploration), "
        "configuration (config file patterns >= 30%), bead-management (bd cmds >= 30%), "
        "discussion (user msgs >= tools or > 2x tools), "
        "mixed (subcats: orchestration, interactive, agent-heavy, transition, still-mixed)."
    )
    lines.append("")

    # Group segments by category
    cat_active = defaultdict(list)
    cat_wall = defaultdict(list)
    cat_count = Counter()
    for seg in segments:
        cat = seg["category"]
        cat_count[cat] += 1
        if seg["active_minutes"] > 0:
            cat_active[cat].append(seg["active_minutes"])
        if seg["wall_clock_minutes"] > 0:
            cat_wall[cat].append(seg["wall_clock_minutes"])

    lines.append("| Category | N Segments | Active Median | Active Mean | Active P90 | Wall-clock Median |")
    lines.append("|----------|------------|---------------|-------------|------------|-------------------|")

    for cat in sorted(cat_count.keys(), key=lambda k: cat_count[k], reverse=True):
        n = cat_count[cat]
        act_stats = compute_stats(cat_active.get(cat, []))
        wc_stats = compute_stats(cat_wall.get(cat, []))
        act_med = act_stats.get("median", "-")
        act_mean = act_stats.get("mean", "-")
        act_p90 = act_stats.get("p90", "-")
        wc_med = wc_stats.get("median", "-")
        lines.append(f"| {cat} | {n} | {act_med} | {act_mean} | {act_p90} | {wc_med} |")

    lines.append("")

    # --- Subcategory timing breakdown ---
    # Collect subcategory stats for light-coding and mixed categories
    subcat_active = defaultdict(list)
    subcat_wall = defaultdict(list)
    subcat_count = Counter()
    subcat_total_active = defaultdict(float)
    for seg in segments:
        subcat = seg.get("subcategory")
        if subcat:
            parent = seg["category"]
            label = f"{parent}:{subcat}"
            subcat_count[label] += 1
            subcat_total_active[label] += seg["active_minutes"]
            if seg["active_minutes"] > 0:
                subcat_active[label].append(seg["active_minutes"])
            if seg["wall_clock_minutes"] > 0:
                subcat_wall[label].append(seg["wall_clock_minutes"])

    if subcat_count:
        lines.append("### Subcategory Timing Breakdown")
        lines.append("")
        lines.append(
            "Median, P90, and total active time for light-coding and mixed subcategories."
        )
        lines.append("")
        lines.append("| Subcategory | N | Active Median | Active P90 | Total Active Min |")
        lines.append("|-------------|---|---------------|------------|------------------|")

        for label in sorted(subcat_count.keys(), key=lambda k: subcat_total_active[k], reverse=True):
            n = subcat_count[label]
            act_stats = compute_stats(subcat_active.get(label, []))
            act_med = act_stats.get("median", "-")
            act_p90 = act_stats.get("p90", "-")
            total_act = round(subcat_total_active[label], 1)
            lines.append(f"| {label} | {n} | {act_med} | {act_p90} | {total_act} |")

        lines.append("")

    # Segment type breakdown
    seg_type_count = Counter(seg["segment_type"] for seg in segments)
    lines.append("**Segment type breakdown:**")
    lines.append("")
    for stype, count in seg_type_count.most_common():
        lines.append(f"- {stype}: {count}")
    lines.append("")

    # Sub-table for bead-management segments
    bm_segments = [seg for seg in segments if seg["category"] == "bead-management"]
    if bm_segments:
        lines.append("### Bead-Management Sub-Categories")
        lines.append("")
        lines.append(
            "BD subcommand distribution within bead-management segments. "
            "Creation = bd create. Triage = bd show/ready/list/search/blocked/sql. "
            "Updating = bd update/close/label."
        )
        lines.append("")

        # Aggregate bd categories across all bead-management segments
        bm_cat_totals = Counter()
        bm_cat_time = defaultdict(float)
        for seg in bm_segments:
            for cat, count in seg.get("bd_categories", {}).items():
                bm_cat_totals[cat] += count
                # Proportionally attribute active time
                total_bd = sum(seg.get("bd_subcommand_counts", {}).values())
                if total_bd > 0:
                    bm_cat_time[cat] += seg["active_minutes"] * count / total_bd

        lines.append("| BD Sub-Category | Command Count | Attributed Active Min |")
        lines.append("|-----------------|---------------|----------------------|")
        for cat in sorted(bm_cat_totals.keys(), key=lambda k: bm_cat_totals[k], reverse=True):
            lines.append(
                f"| {cat} | {bm_cat_totals[cat]} | {round(bm_cat_time[cat], 1)} |"
            )
        lines.append("")

        # Also show raw subcommand counts
        bm_subcmd_totals = Counter()
        for seg in bm_segments:
            for subcmd, count in seg.get("bd_subcommand_counts", {}).items():
                bm_subcmd_totals[subcmd] += count

        lines.append("**Raw bd subcommand counts:**")
        lines.append("")
        for subcmd, count in bm_subcmd_totals.most_common():
            lines.append(f"- `bd {subcmd}`: {count}")
        lines.append("")

    # =========================================
    # 10. CONCURRENT SESSION DETECTION (sub-item 1)
    # =========================================
    lines.append("## 10. Concurrent Session Detection")
    lines.append("")
    lines.append(
        "Sessions with overlapping [first_timestamp, last_timestamp] ranges. "
        "Concurrent sessions may double-count wall-clock time in aggregations."
    )
    lines.append("")

    if concurrent_overlaps:
        total_overlap_minutes = sum(o["overlap_minutes"] for o in concurrent_overlaps)
        unique_sessions_in_overlaps = set()
        for o in concurrent_overlaps:
            unique_sessions_in_overlaps.add(o["session_a"])
            unique_sessions_in_overlaps.add(o["session_b"])

        lines.append(f"**Overlapping session pairs:** {len(concurrent_overlaps)}")
        lines.append(f"**Unique sessions involved:** {len(unique_sessions_in_overlaps)}")
        lines.append(f"**Total overlapping time:** {round(total_overlap_minutes, 1)} min ({round(total_overlap_minutes/60, 1)} hrs)")
        lines.append("")

        # Show top 10 overlaps by duration
        sorted_overlaps = sorted(concurrent_overlaps, key=lambda x: x["overlap_minutes"], reverse=True)
        lines.append("### Top 10 overlaps by duration")
        lines.append("")
        lines.append("| Session A | Session B | Overlap Min |")
        lines.append("|-----------|-----------|-------------|")
        for o in sorted_overlaps[:10]:
            sid_a = o["session_a"][:12] + "..."
            sid_b = o["session_b"][:12] + "..."
            lines.append(f"| {sid_a} | {sid_b} | {o['overlap_minutes']} |")
        lines.append("")
    else:
        lines.append("*No concurrent sessions detected.*")
        lines.append("")

    # =========================================
    # 11. PER-BEAD TIME ATTRIBUTION (WINDOWED vs SESSION-LEVEL)
    # =========================================
    lines.append("## 11. Per-Bead Time Attribution (Windowed vs Session-Level)")
    lines.append("")
    lines.append(
        "**Session-level (old):** Full session time attributed to each bead mentioned. "
        "Overcounts 30-500x for multi-bead sessions.\n\n"
        "**Windowed (new):** Time window = 2 min before first bead reference to 2 min "
        "after last reference. Falls back to proportional splitting (session time / N beads) "
        "when only indirect references exist."
    )
    lines.append("")

    if bead_attribution_windowed:
        # Sort by windowed total_active_minutes descending
        sorted_beads_w = sorted(
            bead_attribution_windowed.items(),
            key=lambda x: x[1]["total_active_minutes"],
            reverse=True,
        )
        sorted_beads_old = sorted(
            bead_attribution_old.items(),
            key=lambda x: x[1]["total_active_minutes"],
            reverse=True,
        )

        # Build lookup for old attribution
        old_active_lookup = {bid: ba["total_active_minutes"] for bid, ba in bead_attribution_old.items()}

        lines.append("### Top 20 beads by windowed active time")
        lines.append("")
        lines.append("| Bead ID | Sessions | Windowed Min | Old Session Min | Reduction | Methods | Ref Types |")
        lines.append("|---------|----------|-------------|-----------------|-----------|---------|-----------|")

        for bid, bw in sorted_beads_w[:20]:
            sessions_str = str(len(bw["sessions"]))
            w_active = round(bw["total_active_minutes"], 1)
            o_active = round(old_active_lookup.get(bid, 0), 1)
            if o_active > 0:
                reduction = round((1 - w_active / o_active) * 100, 1)
                reduction_str = f"{reduction}%"
            else:
                reduction_str = "-"
            methods = ", ".join(f"{m}({c})" for m, c in bw["methods"].most_common())
            ref_types = ", ".join(f"{rt}({c})" for rt, c in bw["ref_types"].most_common())
            lines.append(f"| {bid} | {sessions_str} | {w_active} | {o_active} | {reduction_str} | {methods} | {ref_types} |")

        lines.append("")

        # Summary stats
        total_beads_tracked = len(bead_attribution_windowed)
        multi_session_beads = sum(1 for bw in bead_attribution_windowed.values() if len(bw["sessions"]) > 1)

        total_old_attributed = sum(ba["total_active_minutes"] for ba in bead_attribution_old.values())
        total_windowed_attributed = sum(bw["total_active_minutes"] for bw in bead_attribution_windowed.values())
        overall_reduction = round((1 - total_windowed_attributed / total_old_attributed) * 100, 1) if total_old_attributed > 0 else 0

        windowed_count = sum(1 for bw in bead_attribution_windowed.values() if bw["methods"].get("windowed", 0) > 0)
        proportional_count = sum(1 for bw in bead_attribution_windowed.values() if bw["methods"].get("proportional", 0) > 0 and bw["methods"].get("windowed", 0) == 0)

        lines.append(f"**Total beads with attribution:** {total_beads_tracked}")
        lines.append(f"**Beads spanning multiple sessions:** {multi_session_beads}")
        lines.append(f"**Total old session-level attributed time:** {round(total_old_attributed, 1)} min")
        lines.append(f"**Total windowed attributed time:** {round(total_windowed_attributed, 1)} min")
        lines.append(f"**Overall reduction:** {overall_reduction}%")
        lines.append(f"**Beads using windowed method:** {windowed_count}")
        lines.append(f"**Beads using proportional-only method:** {proportional_count}")
        lines.append("")

        # Show old top 10 for comparison
        lines.append("### Old session-level top 10 (for comparison)")
        lines.append("")
        lines.append("| Bead ID | Sessions | Old Active Min | Old Wall Min | Phases |")
        lines.append("|---------|----------|----------------|--------------|--------|")
        for bid, ba in sorted_beads_old[:10]:
            sessions_str = str(len(ba["sessions"]))
            active = round(ba["total_active_minutes"], 1)
            wall = round(ba["total_wall_clock_minutes"], 1)
            phase_list = ", ".join(
                f"{ph}({c})" for ph, c in ba["phases"].most_common(5)
            )
            lines.append(f"| {bid} | {sessions_str} | {active} | {wall} | {phase_list} |")
        lines.append("")
    else:
        lines.append("*No bead attribution data available (bd database not accessible).*")
        lines.append("")

    # =========================================
    # 12. TOKEN-PER-PHASE AGGREGATION (sub-item 5)
    # =========================================
    lines.append("## 12. Token-per-Phase Aggregation")
    lines.append("")
    lines.append(
        "Agent/Task token usage grouped by the workflow phase they executed within. "
        "Determined by matching agent dispatch timestamps to phase time ranges."
    )
    lines.append("")

    if phase_token_totals:
        total_tokens_all = sum(v["total_tokens"] for v in phase_token_totals.values())
        lines.append("| Phase | Agents | Total Tokens | % of Tokens | Total Duration (s) | Tokens/Agent |")
        lines.append("|-------|--------|-------------|-------------|--------------------|--------------| ")

        for phase in sorted(phase_token_totals.keys(), key=lambda k: phase_token_totals[k]["total_tokens"], reverse=True):
            data = phase_token_totals[phase]
            pct = round(data["total_tokens"] / total_tokens_all * 100, 1) if total_tokens_all > 0 else 0
            dur_s = round(data["total_duration_ms"] / 1000.0, 1)
            per_agent = round(data["total_tokens"] / data["agent_count"]) if data["agent_count"] > 0 else 0
            lines.append(
                f"| {phase} | {data['agent_count']} | {data['total_tokens']:,} | "
                f"{pct}% | {dur_s} | {per_agent:,} |"
            )

        lines.append("")
        lines.append(f"**Total agent tokens across all phases:** {total_tokens_all:,}")
        lines.append("")
    else:
        lines.append("*No token data available.*")
        lines.append("")

    # =========================================
    # 13. ESTIMATE VS ACTUAL (WINDOWED) (sub-item 6)
    # =========================================
    lines.append("## 13. Estimate vs Actual (Windowed Attribution)")
    lines.append("")
    lines.append(
        "Comparing `estimated_minutes` from the beads database with windowed "
        "`total_active_minutes` (not session-level). Ratio = actual / estimated "
        "(>1 means took longer than estimated)."
    )
    lines.append("")

    # Cross-reference using WINDOWED attribution
    estimate_vs_actual_w = []
    for bid, est_data in closed_bead_estimates.items():
        if bid in bead_attribution_windowed:
            bw = bead_attribution_windowed[bid]
            actual = bw["total_active_minutes"]
            estimated = est_data["estimated_minutes"]
            if estimated > 0:
                ratio = round(actual / estimated, 2)
            else:
                ratio = None
            estimate_vs_actual_w.append({
                "bead_id": bid,
                "title": est_data["title"],
                "estimated_min": estimated,
                "actual_windowed_min": round(actual, 1),
                "ratio": ratio,
            })

    # Also compute old session-level for comparison
    estimate_vs_actual_old = []
    for bid, est_data in closed_bead_estimates.items():
        if bid in bead_attribution_old:
            ba = bead_attribution_old[bid]
            actual = ba["total_active_minutes"]
            estimated = est_data["estimated_minutes"]
            if estimated > 0:
                ratio = round(actual / estimated, 2)
            else:
                ratio = None
            estimate_vs_actual_old.append({
                "bead_id": bid,
                "title": est_data["title"],
                "estimated_min": estimated,
                "actual_session_min": round(actual, 1),
                "ratio": ratio,
            })

    if estimate_vs_actual_w:
        estimate_vs_actual_w.sort(key=lambda x: x["ratio"] if x["ratio"] is not None else 0, reverse=True)

        # Build old lookup for side-by-side
        old_lookup = {}
        for item in estimate_vs_actual_old:
            old_lookup[item["bead_id"]] = item

        lines.append("| Bead ID | Title | Est | Windowed Actual | Old Session Actual | W-Ratio | O-Ratio |")
        lines.append("|---------|-------|-----|-----------------|--------------------|---------|---------| ")

        for item in estimate_vs_actual_w:
            title = item["title"][:40] + "..." if len(item["title"]) > 40 else item["title"]
            title = title.replace("|", "\\|")
            w_ratio_str = str(item["ratio"]) if item["ratio"] is not None else "-"
            old_item = old_lookup.get(item["bead_id"], {})
            o_actual = old_item.get("actual_session_min", "-")
            o_ratio = old_item.get("ratio", "-")
            o_ratio_str = str(o_ratio) if o_ratio is not None else "-"
            lines.append(
                f"| {item['bead_id']} | {title} | "
                f"{item['estimated_min']} | {item['actual_windowed_min']} | "
                f"{o_actual} | {w_ratio_str} | {o_ratio_str} |"
            )

        lines.append("")

        # Summary stats
        ratios_w = [x["ratio"] for x in estimate_vs_actual_w if x["ratio"] is not None]
        ratios_o = [x["ratio"] for x in estimate_vs_actual_old if x["ratio"] is not None]
        if ratios_w:
            mean_w = round(statistics.mean(ratios_w), 2)
            median_w = round(statistics.median(ratios_w), 2)
            mean_o = round(statistics.mean(ratios_o), 2) if ratios_o else "-"
            median_o = round(statistics.median(ratios_o), 2) if ratios_o else "-"

            lines.append(f"**Beads with both estimate and actual:** {len(estimate_vs_actual_w)}")
            lines.append(f"**Windowed — Mean ratio:** {mean_w} | **Median ratio:** {median_w}")
            lines.append(f"**Old session — Mean ratio:** {mean_o} | **Median ratio:** {median_o}")

            under_w = sum(1 for r in ratios_w if r > 1.0)
            over_w = sum(1 for r in ratios_w if r < 1.0)
            exact_w = sum(1 for r in ratios_w if r == 1.0)
            lines.append(
                f"**Windowed: Under-estimated (>1):** {under_w} | "
                f"**Over-estimated (<1):** {over_w} | **Exact:** {exact_w}"
            )
        lines.append("")
    else:
        lines.append("*No closed beads found with both estimates and windowed attribution data.*")
        lines.append("")

    # =========================================
    # 14. TIME ALLOCATION SUMMARY
    # =========================================
    lines.append("## 14. Time Allocation Summary")
    lines.append("")
    lines.append(
        "How total active time is distributed across workflow phases "
        "and non-workflow activity categories."
    )
    lines.append("")

    # Total active time
    total_active = sum(s["active_minutes"] for s in sessions)
    total_wall = sum(s["total_duration_minutes"] for s in sessions)
    lines.append(f"**Total active time across all sessions:** {round(total_active, 1)} min ({round(total_active/60, 1)} hrs)")
    lines.append(f"**Total wall-clock time across all sessions:** {round(total_wall, 1)} min ({round(total_wall/60, 1)} hrs)")
    lines.append("")

    # Breakdown by segment type + category
    lines.append("### By Activity Category (from segments)")
    lines.append("")

    cat_total_active = defaultdict(float)
    cat_total_wall = defaultdict(float)
    for seg in segments:
        cat = seg["category"]
        seg_type = seg["segment_type"]
        label = f"{cat} ({seg_type})" if seg_type != "full-session" else cat
        cat_total_active[label] += seg["active_minutes"]
        cat_total_wall[label] += seg["wall_clock_minutes"]

    # Also compute simpler rollups: workflow vs non-workflow
    workflow_active = sum(
        seg["active_minutes"] for seg in segments if seg["segment_type"] == "workflow-phase"
    )
    non_workflow_active = sum(
        seg["active_minutes"] for seg in segments
        if seg["segment_type"] in ("full-session", "pre-workflow")
    )

    lines.append(f"**Workflow phase active time:** {round(workflow_active, 1)} min ({round(workflow_active/60, 1)} hrs)")
    lines.append(f"**Non-workflow active time:** {round(non_workflow_active, 1)} min ({round(non_workflow_active/60, 1)} hrs)")
    lines.append("")

    lines.append("| Activity | Active Min | Wall-clock Min | % of Total Active |")
    lines.append("|----------|------------|----------------|-------------------|")

    total_seg_active = sum(cat_total_active.values())
    for label in sorted(cat_total_active.keys(), key=lambda k: cat_total_active[k], reverse=True):
        act = round(cat_total_active[label], 1)
        wall = round(cat_total_wall[label], 1)
        pct = round(act / total_seg_active * 100, 1) if total_seg_active > 0 else 0
        lines.append(f"| {label} | {act} | {wall} | {pct}% |")

    lines.append("")

    # Bead management total
    bm_total_active = sum(
        seg["active_minutes"] for seg in segments if seg["category"] == "bead-management"
    )
    bm_total_wall = sum(
        seg["wall_clock_minutes"] for seg in segments if seg["category"] == "bead-management"
    )
    lines.append(f"**Total bead-management active time:** {round(bm_total_active, 1)} min ({round(bm_total_active/60, 1)} hrs)")
    lines.append(f"**Total bead-management wall-clock time:** {round(bm_total_wall, 1)} min ({round(bm_total_wall/60, 1)} hrs)")
    lines.append("")

    # Simplified category rollup (collapsing segment types)
    lines.append("### Simplified Category Rollup")
    lines.append("")
    lines.append("Categories collapsed across all segment types.")
    lines.append("")

    simple_cat_active = defaultdict(float)
    simple_cat_wall = defaultdict(float)
    for seg in segments:
        simple_cat_active[seg["category"]] += seg["active_minutes"]
        simple_cat_wall[seg["category"]] += seg["wall_clock_minutes"]

    lines.append("| Category | Active Min | Active Hrs | % of Total |")
    lines.append("|----------|------------|------------|------------|")

    for cat in sorted(simple_cat_active.keys(), key=lambda k: simple_cat_active[k], reverse=True):
        act = round(simple_cat_active[cat], 1)
        hrs = round(act / 60, 1)
        pct = round(act / total_seg_active * 100, 1) if total_seg_active > 0 else 0
        lines.append(f"| {cat} | {act} | {hrs} | {pct}% |")

    lines.append("")

    # =========================================
    # 15. HEADLINE METRICS (S2)
    # =========================================
    lines.append("## 15. Headline Metrics")
    lines.append("")
    lines.append(
        "Key aggregate metrics computed with minute-level deduplication "
        "across concurrent sessions."
    )
    lines.append("")

    hl = headline_record
    lines.append("| Metric | Value |")
    lines.append("|--------|-------|")
    lines.append(f"| Deduplicated active hours | {hl.get('dedup_active_hours', '-')} |")
    lines.append(f"| True wall-clock hours (merged intervals) | {hl.get('merged_wall_clock_hours', '-')} |")
    if hl.get("total_cost_usd_jsonl"):
        lines.append(f"| Total cost (JSONL-computed) | ${hl['total_cost_usd_jsonl']:.2f} |")
    if hl.get("total_cost_usd_ccusage"):
        lines.append(f"| Total cost (ccusage, for comparison) | ${hl['total_cost_usd_ccusage']:.2f} |")
    if not hl.get("total_cost_usd_jsonl") and not hl.get("total_cost_usd_ccusage"):
        lines.append("| Total cost | (not available) |")
    if hl.get("cost_per_active_hour"):
        lines.append(f"| Cost per active hour | ${hl['cost_per_active_hour']:.2f} |")
    if hl.get("overhead_ratio") is not None:
        lines.append(f"| Overhead ratio (bd min / active min) | {round(hl['overhead_ratio'] * 100, 2)}% |")
    lines.append(f"| Automation ratio (Agent+Task / total tools) | {round(hl.get('automation_ratio', 0) * 100, 2)}% |")
    if hl.get("closed_bead_count"):
        lines.append(f"| Closed beads | {hl['closed_bead_count']} |")
    if hl.get("active_days"):
        lines.append(f"| Active days | {hl['active_days']} |")
    if hl.get("beads_per_day"):
        lines.append(f"| Beads per day | {hl['beads_per_day']} |")
    if hl.get("active_min_per_bead"):
        lines.append(f"| Active minutes per bead | {hl['active_min_per_bead']} |")
    if hl.get("median_estimate_ratio") is not None:
        lines.append(f"| Estimation accuracy (median actual/estimated) | {hl['median_estimate_ratio']} |")
    if hl.get("phase_skip_rate") is not None:
        lines.append(
            f"| Phase skip rate (work without brainstorm/deepen) | "
            f"{round(hl['phase_skip_rate'] * 100, 1)}% "
            f"({hl.get('beads_skipped_planning', 0)}/{hl.get('beads_with_work', 0)}) |"
        )
    lines.append("")

    # =========================================
    # 16. PROPORTIONAL TOOL-CALL ALLOCATION (S2)
    # =========================================
    lines.append("## 16. Proportional Tool-Call Allocation")
    lines.append("")
    lines.append(
        "For each activity bucket, tool calls are classified as: "
        "bd (bead-management), editing (Edit/Write), reading (Read/Grep/Glob), "
        "agent-dispatch (Agent/Task), user-dialogue (AskUserQuestion), other. "
        "Active time is allocated proportionally to each tool-call type."
    )
    lines.append("")

    if proportional_records:
        # Collect all bucket names across all records
        all_tool_buckets = set()
        for pr in proportional_records:
            all_tool_buckets.update(pr.get("allocation", {}).keys())
        all_tool_buckets = sorted(all_tool_buckets)

        header = "| Activity Bucket | Segments | Active Min | " + " | ".join(
            f"{b} %" for b in all_tool_buckets
        ) + " |"
        sep = "|-----------------|----------|------------|" + "|".join(
            ["--------"] * len(all_tool_buckets)
        ) + "|"
        lines.append(header)
        lines.append(sep)

        for pr in sorted(proportional_records, key=lambda x: x["total_active_minutes"], reverse=True):
            alloc = pr.get("allocation", {})
            cells = []
            for b in all_tool_buckets:
                if b in alloc:
                    cells.append(f"{round(alloc[b]['fraction'] * 100, 1)}%")
                else:
                    cells.append("-")
            lines.append(
                f"| {pr['bucket']} | {pr['segment_count']} | "
                f"{pr['total_active_minutes']} | " + " | ".join(cells) + " |"
            )

        lines.append("")

        # Also show allocated minutes
        lines.append("### Allocated minutes by tool-call type")
        lines.append("")
        header2 = "| Activity Bucket | " + " | ".join(
            f"{b} min" for b in all_tool_buckets
        ) + " |"
        sep2 = "|-----------------|" + "|".join(
            ["----------"] * len(all_tool_buckets)
        ) + "|"
        lines.append(header2)
        lines.append(sep2)

        for pr in sorted(proportional_records, key=lambda x: x["total_active_minutes"], reverse=True):
            alloc = pr.get("allocation", {})
            cells = []
            for b in all_tool_buckets:
                if b in alloc:
                    cells.append(str(alloc[b]["allocated_minutes"]))
                else:
                    cells.append("-")
            lines.append(f"| {pr['bucket']} | " + " | ".join(cells) + " |")

        lines.append("")
    else:
        lines.append("*No proportional allocation data available.*")
        lines.append("")

    # =========================================
    # 17. ASKUSERQUESTION CATEGORIZATION (S2)
    # =========================================
    lines.append("## 17. AskUserQuestion Categorization")
    lines.append("")
    lines.append(
        "AskUserQuestion tool calls categorized by question content. "
        "Wait time = gap from AskUserQuestion to next assistant message."
    )
    lines.append("")

    askuser_cats = askuser_record.get("categories", {})
    if askuser_cats:
        lines.append(f"**Total AskUserQuestion events:** {askuser_record.get('total_events', 0)}")
        lines.append("")
        lines.append("| Category | Count | Total Wait Min | Avg Wait Min |")
        lines.append("|----------|-------|----------------|--------------|")

        for cat in sorted(askuser_cats.keys(), key=lambda k: askuser_cats[k]["count"], reverse=True):
            data = askuser_cats[cat]
            lines.append(
                f"| {cat} | {data['count']} | "
                f"{data['total_wait_minutes']} | {data['avg_wait_minutes']} |"
            )

        lines.append("")
    else:
        lines.append("*No AskUserQuestion events found.*")
        lines.append("")

    # =========================================
    # 18. ORCHESTRATION OVERHEAD ANALYSIS (S2)
    # =========================================
    lines.append("## 18. Orchestration Overhead Analysis")
    lines.append("")
    lines.append(
        "For segments classified as orchestration or orch-coding: "
        "proportional split between bd commands (overhead) and productive "
        "tool calls (Edit, Write, Read, Grep, Glob, Agent, Task, non-bd Bash)."
    )
    lines.append("")

    if orch_analysis and orch_analysis.get("total_count", 0) > 0:
        lines.append("| Metric | Value |")
        lines.append("|--------|-------|")
        lines.append(f"| Total orchestration active time | {orch_analysis['total_active_minutes']} min |")
        lines.append(f"| BD commands | {orch_analysis['bd_count']} ({round(orch_analysis['bd_fraction'] * 100, 1)}%) |")
        lines.append(f"| Productive tool calls | {orch_analysis['productive_count']} ({round(orch_analysis['productive_fraction'] * 100, 1)}%) |")
        lines.append(f"| BD allocated time | {orch_analysis['bd_allocated_minutes']} min |")
        lines.append(f"| Productive allocated time | {orch_analysis['productive_allocated_minutes']} min |")
        lines.append("")
    else:
        lines.append("*No orchestration segments found.*")
        lines.append("")

    # =========================================
    # 19. PROJECT COST (P5-S1)
    # =========================================
    lines.append("## 19. Project Cost")
    lines.append("")
    lines.append(
        "Per-request cost computed from JSONL `message.usage` fields with "
        "model-specific rates. Covers all assistant responses across all sessions."
    )
    lines.append("")

    if project_cost_record and project_cost_record.get("total_cost_usd", 0) > 0:
        pc = project_cost_record
        ccusage_cost = headline_record.get("total_cost_usd_ccusage")

        lines.append("### Total")
        lines.append("")
        lines.append(f"**JSONL-computed cost: ${pc['total_cost_usd']:.2f}**")
        lines.append("")
        if ccusage_cost:
            delta = pc["total_cost_usd"] - ccusage_cost
            pct = (delta / ccusage_cost * 100) if ccusage_cost else 0
            lines.append(
                f"ccusage total (for comparison): ${ccusage_cost:.2f} "
                f"(delta: ${delta:+.2f}, {pct:+.1f}%)"
            )
            lines.append("")

        # Token totals
        tt = pc.get("token_totals", {})
        lines.append("### Token Totals")
        lines.append("")
        lines.append("| Token Type | Count | Cost Contribution |")
        lines.append("|-----------|-------|-------------------|")
        # Compute contribution per token type across all models (approximate using weighted average)
        # For a simpler approach, just show counts
        lines.append(f"| Input | {tt.get('input_tokens', 0):,} | — |")
        lines.append(f"| Cache creation | {tt.get('cache_creation_input_tokens', 0):,} | — |")
        lines.append(f"| Cache read | {tt.get('cache_read_input_tokens', 0):,} | — |")
        lines.append(f"| Output | {tt.get('output_tokens', 0):,} | — |")
        lines.append("")

        # Per-model breakdown
        lines.append("### Cost by Model")
        lines.append("")
        lines.append("| Model | Cost | % of Total |")
        lines.append("|-------|------|-----------|")
        for model, cost in pc.get("cost_by_model", {}).items():
            pct = (cost / pc["total_cost_usd"] * 100) if pc["total_cost_usd"] > 0 else 0
            lines.append(f"| {model} | ${cost:.2f} | {pct:.1f}% |")
        lines.append("")

        # Per-phase breakdown
        lines.append("### Cost by Phase")
        lines.append("")
        lines.append("| Phase | Cost | % of Total |")
        lines.append("|-------|------|-----------|")
        for phase, cost in pc.get("cost_by_phase", {}).items():
            pct = (cost / pc["total_cost_usd"] * 100) if pc["total_cost_usd"] > 0 else 0
            lines.append(f"| {phase} | ${cost:.2f} | {pct:.1f}% |")
        lines.append("")

        # Per-session cost stats
        session_costs = [s.get("session_cost_usd", 0) for s in sessions if s.get("session_cost_usd", 0) > 0]
        if session_costs:
            sc_stats = compute_stats(session_costs)
            lines.append("### Per-Session Cost Distribution")
            lines.append("")
            lines.append("| Metric | Value |")
            lines.append("|--------|-------|")
            lines.append(f"| Sessions with cost > $0 | {sc_stats['n']} |")
            lines.append(f"| Min | ${sc_stats['min']:.2f} |")
            lines.append(f"| Median | ${sc_stats['median']:.2f} |")
            lines.append(f"| Mean | ${sc_stats['mean']:.2f} |")
            lines.append(f"| Max | ${sc_stats['max']:.2f} |")
            if "p90" in sc_stats:
                lines.append(f"| P90 | ${sc_stats['p90']:.2f} |")
            lines.append("")
    else:
        lines.append("*No cost data available from JSONL.*")
        lines.append("")

    # =========================================
    # 20. STEP TIMING FROM STATS YAML (P5-S2)
    # =========================================
    lines.append("## 20. Step Timing from Stats YAML")
    lines.append("")
    lines.append(
        "Per-agent-dispatch duration data mined from `.workflows/stats/*.yaml`. "
        "Each entry represents one subagent dispatch with wall-clock duration. "
        "Durations shown in minutes."
    )
    lines.append("")

    if stats_timing_data and stats_timing_data.get("total_entries", 0) > 0:
        st = stats_timing_data
        lines.append(f"**Total dispatch entries:** {st['total_entries']}")
        lines.append("")

        # Per-command duration table
        lines.append("### Duration by Workflow Command")
        lines.append("")
        lines.append("| Command | N | Median | Mean | P90 | Min | Max | Total Min |")
        lines.append("|---------|---|--------|------|-----|-----|-----|-----------|")
        for cmd, stat in sorted(st["by_command"].items(), key=lambda x: x[1].get("total_duration_min", 0), reverse=True):
            p90 = stat.get("p90", "-")
            lines.append(
                f"| {cmd} | {stat['n']} | {stat.get('median', '-')} | "
                f"{stat.get('mean', '-')} | {p90} | "
                f"{stat.get('min', '-')} | {stat.get('max', '-')} | "
                f"{stat.get('total_duration_min', '-')} |"
            )
        lines.append("")

        # Per-agent duration table
        lines.append("### Duration by Agent Type")
        lines.append("")
        lines.append("| Agent | N | Median | Mean | P90 | Min | Max |")
        lines.append("|-------|---|--------|------|-----|-----|-----|")
        for agent, stat in sorted(st["by_agent"].items(), key=lambda x: x[1]["n"], reverse=True):
            if stat["n"] < 2:
                continue  # Skip single-occurrence agents for clarity
            p90 = stat.get("p90", "-")
            lines.append(
                f"| {agent} | {stat['n']} | {stat.get('median', '-')} | "
                f"{stat.get('mean', '-')} | {p90} | "
                f"{stat.get('min', '-')} | {stat.get('max', '-')} |"
            )
        lines.append("")

        # Estimate vs actual from stats
        if st["estimate_vs_actual"]:
            lines.append("### Estimate vs Actual (Stats Dispatch Time)")
            lines.append("")
            lines.append(
                "Compares bead estimated_minutes with total subagent dispatch duration. "
                "Note: dispatch time is agent wall-clock only — excludes orchestrator "
                "time, user wait, and inter-step gaps."
            )
            lines.append("")
            lines.append("| Bead | Est Min | Actual Dispatch Min | Ratio | Dispatches | Commands |")
            lines.append("|------|---------|---------------------|-------|------------|----------|")
            for eva in sorted(st["estimate_vs_actual"], key=lambda x: x.get("ratio") or 0, reverse=True):
                ratio_str = f"{eva['ratio']}x" if eva.get("ratio") is not None else "-"
                cmds = ", ".join(eva.get("commands", []))
                lines.append(
                    f"| {eva['bead']} | {eva['estimated_minutes']} | "
                    f"{eva['actual_dispatch_minutes']} | {ratio_str} | "
                    f"{eva['dispatch_count']} | {cmds} |"
                )
            lines.append("")

            # Summary stats for ratios
            ratios = [e["ratio"] for e in st["estimate_vs_actual"] if e.get("ratio") is not None]
            if ratios:
                ratio_stats = compute_stats(ratios)
                lines.append(
                    f"**Dispatch-to-estimate ratio:** "
                    f"median {ratio_stats.get('median', '-')}x, "
                    f"mean {ratio_stats.get('mean', '-')}x "
                    f"(N={ratio_stats['n']})"
                )
                lines.append("")
                lines.append(
                    "*Ratios < 1.0 mean dispatch time was less than estimated "
                    "(expected, since estimates cover full workflow including "
                    "orchestration and user interaction).*"
                )
                lines.append("")
    else:
        lines.append("*No stats YAML data available.*")
        lines.append("")

    # =========================================
    # 21. ASKUSERQUESTION PER WORKFLOW (P5-S3)
    # =========================================
    lines.append("## 21. AskUserQuestion by Workflow")
    lines.append("")
    lines.append(
        "AskUserQuestion events attributed to workflow phases by matching "
        "event timestamps against phase windows. Events outside any phase "
        "window are classified as non-workflow."
    )
    lines.append("")

    if askuser_per_workflow and askuser_per_workflow.get("total_events", 0) > 0:
        pw = askuser_per_workflow
        lines.append(f"**Total events:** {pw['total_events']}")
        lines.append(
            f"**Total confirmation events:** {pw['total_confirmation_events']}"
        )
        lines.append("")

        # All events by workflow table
        lines.append("### All AskUserQuestion Events by Workflow")
        lines.append("")
        lines.append("| Workflow | Count | % of Total | Total Wait Min | Avg Wait Min |")
        lines.append("|----------|-------|-----------|----------------|--------------|")

        all_wf = pw.get("all_by_workflow", {})
        for wf in sorted(all_wf.keys(), key=lambda k: all_wf[k]["count"], reverse=True):
            data = all_wf[wf]
            pct = round(data["count"] / pw["total_events"] * 100, 1) if pw["total_events"] > 0 else 0
            lines.append(
                f"| {wf} | {data['count']} | {pct}% | "
                f"{data['total_wait_minutes']} | {data['avg_wait_minutes']} |"
            )
        lines.append("")

        # Confirmation events by workflow table
        lines.append("### Confirmation Prompts by Workflow")
        lines.append("")
        total_confirm = pw["total_confirmation_events"]
        lines.append("| Workflow | Count | % of Confirmations | Total Wait Min | Avg Wait Min |")
        lines.append("|----------|-------|-------------------|----------------|--------------|")

        conf_wf = pw.get("confirmation_by_workflow", {})
        for wf in sorted(conf_wf.keys(), key=lambda k: conf_wf[k]["count"], reverse=True):
            data = conf_wf[wf]
            pct = round(data["count"] / total_confirm * 100, 1) if total_confirm > 0 else 0
            lines.append(
                f"| {wf} | {data['count']} | {pct}% | "
                f"{data['total_wait_minutes']} | {data['avg_wait_minutes']} |"
            )
        lines.append("")

        # Category breakdown per workflow (detailed)
        lines.append("### Category Breakdown per Workflow")
        lines.append("")
        cats_wf = pw.get("categories_by_workflow", {})
        # Collect all unique categories
        all_cats = sorted(set(
            cat for wf_cats in cats_wf.values() for cat in wf_cats.keys()
        ))
        if all_cats:
            header = "| Workflow | " + " | ".join(all_cats) + " | Total |"
            sep = "|----------|" + "|".join(["------"] * len(all_cats)) + "|-------|"
            lines.append(header)
            lines.append(sep)

            for wf in sorted(cats_wf.keys(), key=lambda k: sum(cats_wf[k].values()), reverse=True):
                wf_cats = cats_wf[wf]
                total = sum(wf_cats.values())
                cells = [str(wf_cats.get(cat, 0)) for cat in all_cats]
                lines.append(f"| {wf} | " + " | ".join(cells) + f" | {total} |")
            lines.append("")
    else:
        lines.append("*No AskUserQuestion per-workflow data available.*")
        lines.append("")

    # =========================================
    # 22. ESTIMATION ACCURACY SEGMENTATION (P5-S4)
    # =========================================
    lines.append("## 22. Estimation Accuracy by Segment")
    lines.append("")
    lines.append(
        "Estimation accuracy (actual/estimated ratio) segmented by bead type, "
        "priority, session count, and estimate size. Ratio < 1 means faster than "
        "estimated; > 1 means slower."
    )
    lines.append("")

    if estimation_segment_data and estimation_segment_data.get("bead_count", 0) > 0:
        segs = estimation_segment_data["segments"]
        overall = segs.get("overall", {})
        lines.append(
            f"**Beads analyzed:** {estimation_segment_data['bead_count']} "
            f"(overall median ratio: {overall.get('median_ratio', '-')}x, "
            f"mean: {overall.get('mean_ratio', '-')}x)"
        )
        lines.append("")

        # Helper to render a segment table
        def render_segment_table(title, seg_dict, label_header="Segment"):
            lines.append(f"### {title}")
            lines.append("")
            lines.append(
                f"| {label_header} | N | Median | Mean | Min | Max | Under-est | Over-est |"
            )
            lines.append(
                "|---------|---|--------|------|-----|-----|-----------|----------|"
            )
            for label, stats in seg_dict.items():
                if stats["n"] == 0:
                    continue
                lines.append(
                    f"| {label} | {stats['n']} | "
                    f"{stats['median_ratio']}x | {stats['mean_ratio']}x | "
                    f"{stats['min_ratio']}x | {stats['max_ratio']}x | "
                    f"{stats['under_estimated']} | {stats['over_estimated']} |"
                )
            lines.append("")

        render_segment_table("By Issue Type", segs.get("by_type", {}), "Type")
        render_segment_table("By Priority", segs.get("by_priority", {}), "Priority")
        render_segment_table(
            "By Session Count", segs.get("by_session_type", {}), "Sessions"
        )
        render_segment_table(
            "By Estimate Size", segs.get("by_estimate_bucket", {}), "Bucket"
        )

        # Per-bead detail table (sorted by ratio descending)
        lines.append("### Per-Bead Detail")
        lines.append("")
        lines.append(
            "| Bead | Type | Pri | Est | Actual | Ratio | Sessions | Bucket |"
        )
        lines.append(
            "|------|------|-----|-----|--------|-------|----------|--------|"
        )
        detail_records = sorted(
            estimation_segment_data["records"],
            key=lambda x: x["ratio"],
            reverse=True,
        )
        for rec in detail_records:
            title = rec["title"][:35] + "..." if len(rec["title"]) > 35 else rec["title"]
            title = title.replace("|", "\\|")
            pri = f"P{rec['priority']}" if rec["priority"] is not None else "-"
            lines.append(
                f"| {rec['bead_id']} | {rec['issue_type']} | {pri} | "
                f"{rec['estimated_minutes']} | {rec['actual_minutes']} | "
                f"{rec['ratio']}x | {rec['session_count']} | "
                f"{rec['estimate_bucket']} |"
            )
        lines.append("")
    else:
        lines.append("*No estimation segment data available.*")
        lines.append("")

    # =========================================
    # 23. COMPACTION COST (P5-S5)
    # =========================================
    lines.append("## 23. Compaction Cost")
    lines.append("")
    lines.append(
        "Cost per compaction event (token cost of the compaction request) "
        "and reorientation time (gap from compaction to first productive "
        "tool call — Edit/Write/Agent/Task, excluding Read/Grep/Glob)."
    )
    lines.append("")

    if compaction_cost_data and compaction_cost_data.get("event_count", 0) > 0:
        cd = compaction_cost_data
        lines.append(f"**Compaction events:** {cd['event_count']} "
                      f"across {cd['sessions_with_compaction']} sessions")
        lines.append("")

        # Cost summary table
        lines.append("### Token Cost per Compaction")
        lines.append("")
        lines.append("| Metric | Value |")
        lines.append("|--------|-------|")
        lines.append(f"| Total | ${cd['total_cost_usd']:.2f} |")
        lines.append(f"| Median | ${cd['median_cost_usd']:.4f} |")
        lines.append(f"| Mean | ${cd['mean_cost_usd']:.4f} |")
        lines.append(f"| Min | ${cd['min_cost_usd']:.4f} |")
        lines.append(f"| Max | ${cd['max_cost_usd']:.4f} |")
        lines.append("")

        # Reorientation time table
        if cd.get("reorientation_event_count", 0) > 0:
            lines.append("### Reorientation Time")
            lines.append("")
            lines.append(
                "Time from compaction to first productive tool call "
                "(Edit/Write/Agent/Task)."
            )
            lines.append("")
            lines.append("| Metric | Value |")
            lines.append("|--------|-------|")
            lines.append(
                f"| Events with productive follow-up | "
                f"{cd['reorientation_event_count']}/{cd['event_count']} |"
            )
            lines.append(
                f"| Median | {cd['median_reorientation_minutes']} min |"
            )
            lines.append(
                f"| Mean | {cd['mean_reorientation_minutes']} min |"
            )
            lines.append(
                f"| Max | {cd['max_reorientation_minutes']} min |"
            )
            lines.append(
                f"| Total | {cd['total_reorientation_minutes']} min |"
            )
            lines.append("")
        else:
            lines.append(
                "*No productive tool calls found after compaction events.*"
            )
            lines.append("")

        # Per-event detail table
        if compaction_cost_details:
            lines.append("### Per-Event Detail")
            lines.append("")
            lines.append(
                "| Session | Timestamp | Cost | Reorientation | Model |"
            )
            lines.append(
                "|---------|-----------|------|---------------|-------|"
            )
            for cc in sorted(compaction_cost_details, key=lambda x: x["timestamp"]):
                session_short = cc["session"][-8:] if len(cc["session"]) > 8 else cc["session"]
                ts_short = cc["timestamp"][:19] if len(cc["timestamp"]) > 19 else cc["timestamp"]
                reorient = (
                    f"{cc['reorientation_minutes']} min"
                    if cc["reorientation_minutes"] is not None
                    else "N/A"
                )
                model_short = cc["model"].split("-")[-1] if cc["model"] else "-"
                lines.append(
                    f"| ...{session_short} | {ts_short} | "
                    f"${cc['token_cost']:.4f} | {reorient} | {model_short} |"
                )
            lines.append("")
    else:
        lines.append("*No compaction events found.*")
        lines.append("")

    # =========================================
    # 24. VELOCITY TREND (P5-S6)
    # =========================================
    lines.append("## 24. Velocity Trend by Date")
    lines.append("")
    lines.append(
        "Daily velocity: bead closures and active hours per date. "
        "Active time is computed from session timestamps (sum of session "
        "active minutes bucketed by session start date). Bead closures "
        "come from the beads database `closed_at` field. Note: beads/hour "
        "can be skewed on individual dates because long sessions bucket "
        "to their start date while bead closures bucket to their close date."
    )
    lines.append("")

    if velocity_trend_data and velocity_trend_data.get("date_count", 0) > 0:
        vt = velocity_trend_data
        lines.append(
            f"**Date range:** {vt['date_count']} dates, "
            f"{vt['total_beads_closed']} beads closed, "
            f"{vt['total_active_hours']} active hours"
        )
        lines.append("")

        # Summary stats
        lines.append("### Velocity Summary")
        lines.append("")
        lines.append("| Metric | Value |")
        lines.append("|--------|-------|")
        lines.append(
            f"| Overall beads/hour | "
            f"{vt['overall_beads_per_hour']} |"
        )
        if vt.get("median_beads_per_day") is not None:
            lines.append(
                f"| Median beads/day | {vt['median_beads_per_day']} |"
            )
        if vt.get("mean_beads_per_day") is not None:
            lines.append(
                f"| Mean beads/day | {vt['mean_beads_per_day']} |"
            )
        if vt.get("median_active_hours_per_day") is not None:
            lines.append(
                f"| Median active hours/day | "
                f"{vt['median_active_hours_per_day']} |"
            )
        if vt.get("mean_active_hours_per_day") is not None:
            lines.append(
                f"| Mean active hours/day | "
                f"{vt['mean_active_hours_per_day']} |"
            )
        lines.append("")

        # Daily trend table
        lines.append("### Daily Trend")
        lines.append("")
        lines.append(
            "| Date | Beads Closed | Active Hours | Beads/Hour |"
        )
        lines.append(
            "|------|-------------|-------------|------------|"
        )
        for rec in vt.get("records", []):
            bph = (
                f"{rec['beads_per_hour']}"
                if rec.get("beads_per_hour") is not None
                else "-"
            )
            lines.append(
                f"| {rec['date']} | {rec['beads_closed']} | "
                f"{rec['active_hours']} | {bph} |"
            )
        lines.append("")
    else:
        lines.append("*No velocity trend data available.*")
        lines.append("")

    # --- Section 25: Permission Prompt Estimate ---
    lines.append("## 25. Permission Prompt Estimate")
    lines.append("")
    lines.append(
        "**Methodology caveat:** There is no JSONL signal for OS-level permission "
        "prompts. This section uses a proxy: count Bash tool calls in "
        '`permissionMode="default"` sessions that match known heuristic-triggering '
        "patterns (`$()`, `<<`, `{\"`) from the AGENTS.md Bash Generation Rules. "
        "The estimate multiplies the triggering-pattern count by the median user "
        "response time for confirmation AskUserQuestion events as an upper bound. "
        "True cost is likely 30-50% of this estimate because: (a) not every "
        "pattern-matching Bash call triggers a permission prompt (static rules "
        "suppress some heuristics), and (b) permission prompts are simpler yes/no "
        "confirmations that resolve faster than full AskUserQuestion interactions."
    )
    lines.append("")

    if permission_prompt_data:
        ppd = permission_prompt_data
        total_sessions = (
            ppd.get("sessions_with_default_mode", 0)
            + ppd.get("sessions_with_accept_edits", 0)
            + ppd.get("sessions_no_mode_field", 0)
        )
        lines.append("### Session Permission Modes")
        lines.append("")
        lines.append("| Mode | Sessions |")
        lines.append("|------|----------|")
        lines.append(
            f"| `default` | {ppd.get('sessions_with_default_mode', 0)} |"
        )
        lines.append(
            f"| `acceptEdits` | {ppd.get('sessions_with_accept_edits', 0)} |"
        )
        lines.append(
            f"| No mode field | {ppd.get('sessions_no_mode_field', 0)} |"
        )
        lines.append(f"| **Total** | **{total_sessions}** |")
        lines.append("")

        lines.append("### Triggering Patterns")
        lines.append("")
        lines.append(
            f"**Total triggering Bash commands:** "
            f"{ppd.get('total_triggering_bash_commands', 0)} "
            f"across {ppd.get('sessions_with_triggers', 0)} sessions"
        )
        lines.append("")

        pattern_counts = ppd.get("pattern_counts", {})
        if pattern_counts:
            lines.append("| Pattern | Count |")
            lines.append("|---------|-------|")
            for pattern_name, count in sorted(
                pattern_counts.items(), key=lambda x: -x[1]
            ):
                lines.append(f"| `{pattern_name}` | {count} |")
            lines.append("")

        lines.append("### Cost Estimate")
        lines.append("")
        lines.append(
            f"| Metric | Value |"
        )
        lines.append("|--------|-------|")
        lines.append(
            f"| Median confirmation wait (proxy) | "
            f"{ppd.get('median_confirmation_wait_min', 'N/A')} min |"
        )
        lines.append(
            f"| Estimated total wait (upper bound) | "
            f"{ppd.get('estimated_total_minutes', 'N/A')} min "
            f"({ppd.get('estimated_total_hours', 'N/A')} hours) |"
        )
        # Compute likely range (30-50% of upper bound)
        est_min = ppd.get("estimated_total_minutes", 0)
        if est_min and est_min > 0:
            low_min = round(est_min * 0.3, 1)
            high_min = round(est_min * 0.5, 1)
            low_hrs = round(low_min / 60.0, 2)
            high_hrs = round(high_min / 60.0, 2)
            lines.append(
                f"| Likely range (30-50% of upper bound) | "
                f"{low_min}-{high_min} min "
                f"({low_hrs}-{high_hrs} hours) |"
            )
        lines.append("")
    else:
        lines.append("*No permission prompt data available.*")
        lines.append("")

    with open(SUMMARY_OUTPUT, "w") as f:
        f.write("\n".join(lines))


if __name__ == "__main__":
    main()
