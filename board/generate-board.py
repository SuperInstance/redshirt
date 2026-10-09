#!/usr/bin/env python3
"""Captain's board: render fleet state from redshirt heartbeat commits.

The zero agent writes tasks blind — it cannot see which shirts are alive,
what they're chewing, or how much life they have left. The heartbeats are
already commits; this script renders them into a glanceable board.

Usage:
    python3 generate-board.py [--repo URL-OR-PATH] [--out BOARD.md]
                             [--stale-min 15] [--dead-min 60]

Heartbeat commits are `heartbeat <name>` (newest first). Each carries
`tasks/<name>/heartbeat.md` with machine-readable frontmatter
(node, last, started, hours, task). The old plain `timestamp alive`
format is tolerated. Statuses:

    ALIVE — heartbeat age <= --stale-min
    STALE — heartbeat age <= --dead-min
    DEAD  — heartbeat age > --dead-min

Exit 0 on success (even when the fleet is empty — an empty fleet is the
true state, not an error).
"""
import argparse
import datetime as dt
import os
import re
import subprocess
import sys
import tempfile

FRONTMATTER_KEYS = ("node", "last", "started", "hours", "task")
HEARTBEAT_RE = re.compile(r"^heartbeat\s+(\S+)\s*$", re.IGNORECASE)


def sh(cmd, cwd=None):
    return subprocess.run(
        cmd, cwd=cwd, check=True, capture_output=True, text=True
    ).stdout


def ensure_repo(source, cache_dir):
    """Return a local git dir tracking `source` (URL or local path)."""
    if os.path.isdir(os.path.join(source, ".git")):
        return source
    os.makedirs(cache_dir, exist_ok=True)
    mirror = os.path.join(cache_dir, "redshirt.git")
    if not os.path.isdir(mirror):
        sh(["git", "clone", "--quiet", source, mirror])
    else:
        sh(["git", "-C", mirror, "fetch", "--quiet", "origin"])
    return mirror


def parse_last(value, fallback_epoch):
    """ISO-8601 `last` -> aware datetime; falls back to commit time."""
    if value:
        try:
            parsed = dt.datetime.fromisoformat(
                value.strip().replace("Z", "+00:00")
            )
            if parsed.tzinfo is None:
                parsed = parsed.replace(tzinfo=dt.timezone.utc)
            return parsed
        except ValueError:
            pass
    return dt.datetime.fromtimestamp(fallback_epoch, dt.timezone.utc)


def fmt_age(seconds):
    seconds = max(0, int(seconds))
    if seconds < 60:
        return f"{seconds}s"
    if seconds < 3600:
        return f"{seconds // 60}m"
    if seconds < 86400:
        return f"{seconds // 3600}h{(seconds % 3600) // 60:02d}m"
    return f"{seconds // 86400}d"


def parse_heartbeat(text):
    """Return frontmatter dict; tolerate legacy `<timestamp> alive`."""
    data = {}
    body = text
    m = re.match(r"\s*---\s*\n(.*?)\n---\s*\n?", text, re.DOTALL)
    if m:
        body = text[m.end():]
        for line in m.group(1).splitlines():
            if ":" in line:
                k, v = line.split(":", 1)
                if k.strip() in FRONTMATTER_KEYS:
                    data[k.strip()] = v.strip()
    if not data:
        # legacy: "2026-10-08T20:20:00Z alive"
        m = re.match(r"\s*(\S+)\s+alive\s*", body)
        if m:
            data["last"] = m.group(1)
    return data


def collect_nodes(repo):
    """Newest-first `heartbeat <name>` commits -> one record per node."""
    log = sh(
        ["git", "-C", repo, "log", "--all", "--format=%H|%ct|%s",
         "--date-order", "--no-merges"]
    )
    nodes = {}
    for line in log.splitlines():
        try:
            sha, ctime, subject = line.split("|", 2)
        except ValueError:
            continue
        m = HEARTBEAT_RE.match(subject.strip())
        if not m:
            continue
        name = m.group(1)
        if ".." in name or name in nodes:
            continue  # first (newest) beat wins; reject path escapes
        try:
            hb = sh(["git", "-C", repo, "show",
                     f"{sha}:tasks/{name}/heartbeat.md"])
        except subprocess.CalledProcessError:
            continue  # heartbeat file not present in that commit
        data = parse_heartbeat(hb)
        nodes[name] = {
            "name": name,
            "task": data.get("task", "unknown"),
            "last": parse_last(data.get("last"), int(ctime)),
            "commit_epoch": int(ctime),
            "started": data.get("started"),
            "hours": data.get("hours"),
        }
    return nodes


def timebox_remaining(node, now):
    try:
        started = int(float(node["started"]))
        hours = float(node["hours"])
    except (TypeError, ValueError):
        return "unknown"
    end = started + hours * 3600
    delta = end - now.timestamp()
    if delta <= 0:
        return "expired"
    return fmt_age(delta)


def render(nodes, stale_min, dead_min):
    now = dt.datetime.now(dt.timezone.utc)
    rows = []
    for name in sorted(nodes):
        n = nodes[name]
        age = (now - n["last"]).total_seconds()
        age = max(0, age)
        if age <= stale_min * 60:
            status = "ALIVE"
        elif age <= dead_min * 60:
            status = "STALE"
        else:
            status = "DEAD"
        rows.append({
            "node": name,
            "task": n["task"] or "none",
            "remaining": timebox_remaining(n, now),
            "age": fmt_age(age),
            "status": status,
        })

    lines = [
        "# Captain's Board — redshirt fleet",
        "",
        f"_Generated {now.strftime('%Y-%m-%d %H:%M:%S UTC')} from heartbeat "
        "commits in `SuperInstance/redshirt`._",
        "",
        "**Statuses:** `ALIVE` beat within 15 min · `STALE` beat within "
        "60 min · `DEAD` older than 60 min. A fleet you cannot see is a "
        "fleet you cannot prune.",
        "",
    ]
    if not rows:
        lines += [
            "## Fleet status: EMPTY",
            "",
            "No `heartbeat <name>` commits exist in the repo yet. No shirts "
            "have beaten, so there is nothing to prune. The moment a node "
            "pushes its first heartbeat, the next board run will show it.",
            "",
        ]
    else:
        lines += [
            "| node | current task | timebox remaining | heartbeat age | status |",
            "| --- | --- | --- | --- | --- |",
        ]
        for r in rows:
            lines.append(
                f"| `{r['node']}` | {r['task']} | {r['remaining']} | "
                f"{r['age']} | **{r['status']}** |"
            )
        lines.append("")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo",
                    default="https://github.com/SuperInstance/redshirt",
                    help="repo URL or local path to read heartbeats from")
    ap.add_argument("--out", default="BOARD.md",
                    help="markdown file to write")
    ap.add_argument("--stale-min", type=int, default=15)
    ap.add_argument("--dead-min", type=int, default=60)
    ap.add_argument("--cache-dir",
                    default=os.path.join(tempfile.gettempdir(),
                                         "redshirt-board"))
    args = ap.parse_args()

    repo = ensure_repo(args.repo, args.cache_dir)
    nodes = collect_nodes(repo)
    board = render(nodes, args.stale_min, args.dead_min)
    with open(args.out, "w") as f:
        f.write(board + "\n")
    print(f"wrote {args.out}: {len(nodes)} node(s)")


if __name__ == "__main__":
    main()
