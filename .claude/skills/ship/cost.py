#!/usr/bin/env python3
"""Cost and time breakdown for one /ship run, from Claude Code's local transcripts.

Usage: cost.py <session-id> [project-dir]

session-id: the UUID in any task-notification output path
  (/private/tmp/claude-<uid>/<project-slug>/<session-id>/tasks/<task>.output).
project-dir: defaults to the transcript dir for the current working directory, under
  $CLAUDE_CONFIG_DIR (or ~/.claude); if the session isn't there, any project dir holding it.

Unreadable transcript lines (partial or still being written) are skipped, noted on stderr.

Prices are API list prices per million tokens, checked 2026-09-24. Cache writes are
priced at the 1-hour TTL (2x input), which is what Claude Code uses.
"""
import glob
import json
import os
import sys
from datetime import datetime

# model prefix -> (input, output, cache_read, cache_write_1h) in $/MTok
PRICES = {
    "claude-opus-5-5": (4.0, 20.0, 0.20, 8.0),
    "claude-sonnet-5-5": (2.0, 10.0, 0.20, 4.0),
    "claude-sonnet-5": (2.0, 10.0, 0.20, 4.0),  # cache read assumed at 10% of input
    "claude-haiku-5-5": (0.10, 0.50, 0.01, 0.20),  # prompts up to 100K; see LONG_PROMPT_PRICES
    "claude-haiku-4-5": (1.0, 5.0, 0.10, 2.0),
    "claude-fable-5-1": (10.0, 50.0, 0.25, 20.0),
}


# model prefix -> (prompt-token threshold, prices above it). The tier is per call, by its whole prompt.
LONG_PROMPT_PRICES = {
    "claude-haiku-5-5": (100_000, (0.50, 2.50, 0.05, 1.00)),
}


def price_for(model, prompt_tokens=0):
    for prefix, (threshold, p) in LONG_PROMPT_PRICES.items():
        if model.startswith(prefix) and prompt_tokens > threshold:
            return p
    for prefix, p in PRICES.items():
        if model.startswith(prefix):
            return p
    return None


def parse_ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def load(path):
    # A transcript still being written, or cut off mid-write, can hold partial lines
    records, bad = [], []
    with open(path) as f:
        for n, line in enumerate(f, 1):
            if not line.strip():
                continue
            try:
                d = json.loads(line)
            except ValueError:
                bad.append(n)
                continue
            if isinstance(d, dict):
                records.append(d)
    if bad:
        print(f"skipped {len(bad)} unreadable line(s) in {path}: {', '.join(map(str, bad))}", file=sys.stderr)
    return records


def summarise(records):
    messages = {}
    first = last = None
    for d in records:
        ts = d.get("timestamp")
        if ts:
            first = first or ts
            last = ts
        m = d.get("message") or {}
        if d.get("type") == "assistant" and m.get("usage") and m.get("id"):
            messages[m["id"]] = m  # streamed chunks repeat the id; keep the last
    by_model = {}
    for m in messages.values():
        u = m["usage"]
        model = m.get("model", "?")
        agg = by_model.setdefault(model, {"calls": 0, "in": 0, "out": 0, "cr": 0, "cw": 0, "ctx": 0, "usd": 0.0})
        agg["calls"] += 1
        agg["in"] += u.get("input_tokens", 0) or 0
        agg["out"] += u.get("output_tokens", 0) or 0
        agg["cr"] += u.get("cache_read_input_tokens", 0) or 0
        agg["cw"] += u.get("cache_creation_input_tokens", 0) or 0
        ctx = (u.get("cache_read_input_tokens", 0) or 0) + (u.get("cache_creation_input_tokens", 0) or 0) + (u.get("input_tokens", 0) or 0)
        agg["ctx"] = max(agg["ctx"], ctx)
        p = price_for(model, ctx)
        if p is None:
            agg["usd"] = None
        elif agg["usd"] is not None:
            agg["usd"] += (
                (u.get("input_tokens", 0) or 0) * p[0]
                + (u.get("output_tokens", 0) or 0) * p[1]
                + (u.get("cache_read_input_tokens", 0) or 0) * p[2]
                + (u.get("cache_creation_input_tokens", 0) or 0) * p[3]
            ) / 1e6
    minutes = (parse_ts(last) - parse_ts(first)).total_seconds() / 60 if first and last else 0
    return by_model, minutes


def cost(model, a):
    return a["usd"]


def short_model(model):
    for name in ("opus", "sonnet", "haiku", "fable"):
        if name in model:
            return name.capitalize()
    return model


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    session = sys.argv[1]
    # A session started under CLAUDE_CONFIG_DIR keeps its transcripts there, not in ~/.claude
    config_dir = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    project = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        config_dir, "projects", os.getcwd().replace("/", "-").replace(".", "-"))
    main_path = os.path.join(project, session + ".jsonl")
    if not os.path.exists(main_path) and len(sys.argv) <= 2:
        # Run from elsewhere than the session's start dir; session ids are unique across projects
        found = glob.glob(os.path.join(glob.escape(config_dir), "projects", "*", glob.escape(session) + ".jsonl"))
        if len(found) == 1:
            main_path = found[0]
            project = os.path.dirname(main_path)
    if not os.path.exists(main_path):
        sys.exit(f"transcript not found: {main_path}")

    rows = [("Orchestrator", load(main_path))]
    sub_dir = os.path.join(project, session, "subagents")
    if os.path.isdir(sub_dir):
        subs = []
        for f in os.listdir(sub_dir):
            if not f.endswith(".jsonl"):
                continue
            path = os.path.join(sub_dir, f)
            label = f[:-6]
            meta = path[:-6] + ".meta.json"
            if os.path.exists(meta):
                md = json.load(open(meta))
                label = f"{md.get('description', label)} ({md.get('agentType', '?')})"
            records = load(path)
            started = next((d["timestamp"] for d in records if d.get("timestamp")), "")
            subs.append((started, label, records))
        rows += [(label, records) for _, label, records in sorted(subs, key=lambda s: s[:2])]

    table = [("Part", "Model", "Calls", "Largest context", "Duration", "Approx. cost")]
    total = 0.0
    total_calls = 0
    unknown = False
    for label, records in rows:
        by_model, minutes = summarise(records)
        for model, a in by_model.items():
            c = cost(model, a)
            if c is None:
                unknown = True
                cost_s = "?"
            else:
                total += c
                cost_s = f"${c:.2f}"
            total_calls += a["calls"]
            table.append((label, short_model(model), str(a["calls"]), f"{a['ctx'] // 1000}k", f"{minutes:.0f} min", cost_s))
    table.append(("**Total**", "", str(total_calls), "", "", f"**${total:.2f}**{' + unpriced' if unknown else ''}"))
    widths = [max(len(r[i]) for r in table) for i in range(len(table[0]))]
    lines = ["| " + " | ".join(c.ljust(w) for c, w in zip(r, widths)) + " |" for r in table]
    lines.insert(1, "| " + " | ".join("-" * w for w in widths) + " |")
    print("\n".join(lines))
    print("\nAPI-equivalent list prices; your plan bills quota, not dollars.")


if __name__ == "__main__":
    main()
