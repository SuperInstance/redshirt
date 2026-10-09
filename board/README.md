# Captain's board

Renders the live redshirt fleet from the heartbeat commits in this repo.
The zero agent writes tasks blind — the board is how the captain sees
which shirts are alive, what they're chewing, and how much life is left
in their timebox.

## Generate

```bash
python3 board/generate-board.py --out BOARD.md
```

Options:

| flag | default | meaning |
| --- | --- | --- |
| `--repo` | `https://github.com/SuperInstance/redshirt` | repo URL or local path to read heartbeats from |
| `--out` | `BOARD.md` | markdown file to write |
| `--stale-min` | `15` | heartbeat age under this → `ALIVE` |
| `--dead-min` | `60` | heartbeat age under this → `STALE`, older → `DEAD` |

Reads only stdlib Python 3. Exits 0 even when the fleet is empty — an
empty fleet is the true state, not an error.

## Cron (every 5 minutes)

Regenerate and push the board on a schedule:

```cron
*/5 * * * * cd /path/to/redshirt && python3 board/generate-board.py --out BOARD.md && git add BOARD.md && git commit -qm "board: refresh" && git push -q
```

Only push when `BOARD.md` changed — wrap the commit in
`git diff --quiet BOARD.md ||` if you want a quiet log.

## Heartbeat format the board reads

Heartbeat commits are `heartbeat <name>`, each carrying
`tasks/<name>/heartbeat.md`:

```markdown
---
node: alpha
last: 2026-10-08T21:05:00Z
started: 1728435900
hours: 4
task: haul-nets
---
alive
```

- `last`: ISO-8601 UTC of this beat
- `started`/`hours`: epoch + hours defining the timebox; the board shows
  remaining time, or `expired`
- `task`: current task label

The old plain `timestamp alive` format is tolerated (task shows
`unknown`, timebox shows `unknown`).
