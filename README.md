# redshirt

Disposable remote appendage for a git agent. Install on any machine with one
command. It polls a git repo for tasks, executes them inside a sandbox,
pushes results back. Then it dies when the timebox expires — and the
dead-man's switch makes sure of it even if the shirt won't die on its own.

The inverse of fleet-session: instead of pushing commands to the node, the
node pulls tasks from git.

## Install

```bash
curl -sSL https://raw.githubusercontent.com/SuperInstance/redshirt/main/install.sh \
  | bash -s <name> <hours> [options]
```

Example: `bash -s hp-laptop 4` — runs for 4 hours, then stops.

Options:

| flag | effect |
|---|---|
| `--allowlist "git curl python3"` | command allowlist for tasks (default: `git curl python3 claude`) |
| `--net` / `--no-net` | task network access (default: `--no-net`) |
| `--reap-after SECONDS` | stale-claim threshold for the scavenger (default: 300) |
| `--no-wake` | disable the wake trigger (plain 60s polling) |
| `--no-killswitch` | disable the external dead-man's switch (**not** recommended) |

## How it works

1. The installer prints the install ceremony (see below), takes the witnessed
   yes, writes config (`~/.redshirt/config`), clones this repo, starts the
   poller in its own process group, and arms the killswitch supervisor.
2. `redshirt.sh` loops: `git pull`, run the scavenger (`reaper.sh`), check
   `tasks/<name>/inbox/` for new `.md` files.
3. Each task file has either:
   - `run: <shell command>` — executed inside `sandbox.sh`, output captured.
   - `claude: <prompt>` — run via `claude -p` inside `sandbox.sh` (needs
     `claude` in the allowlist and `claude login`).
4. Claims are atomic (`noclobber`) and carry heartbeats, refreshed while the
   task runs; claims that go silent past `--reap-after` are requeued by the
   scavenger. Result written to `tasks/<name>/outbox/<task>.result.md`,
   task file moved to `tasks/<name>/done/`, `git push`.
5. `wake.sh` watches the repo's commits API (outbound-only, ETag polling) and
   wakes the poller within ~5s of a landed task; if the trigger dies the
   shirt degrades to 60s polling, never silence.
6. At end of timebox the shirt buries itself (`rm -rf ~/.redshirt` — no
   corpse). The killswitch SIGKILLs the poller's process group at the
   deadline regardless, then buries anything left.

## Task format

```markdown
# task-slug

claude: Write a haiku about a fishing boat.
# or
run: echo hello && uname -a
```

## The install ceremony

Installation is the permission grant, so the installer does not say yes
blind. Before anything is written, `install.sh` probes this machine —
what it can reach (network), where it can write (filesystem scope), what
credentials are visible (names only, never values), and what spend
authority it could inherit — prints it in plain words on one page, and
pauses for an explicit witnessed yes: you type the node name. The page also
shows the task scope being granted (command allowlist, task network, wake,
killswitch). A receipt lands in `~/.redshirt/grant-receipt.md`.

Non-interactive installs: `REDSHIRT_ASSUME_YES=1` skips the prompt only
when stdin is not a terminal. Setting it is itself the grant.

## The captain's board

Fleet state (live nodes, current tasks, timebox remaining, heartbeat age)
is rendered from the heartbeat commits in this repo by
[`board/generate-board.py`](board/generate-board.py), which writes
[`BOARD.md`](BOARD.md). Heartbeats are
`tasks/<name>/heartbeat.md` with machine-readable frontmatter
(node, last, started, hours, task). Regenerate on a 5-minute cron —
see [`board/README.md`](board/README.md).

## Docs

- [Sandbox scope](docs/sandbox.md) — one writable dir, allowlisted commands, no network unless flagged; worst case and residual risk.
- [Wake trigger](docs/wake-trigger.md) — outbound-only wake within ~5s; degrade-to-polling failure mode.
- [Reaper](docs/reaper.md) — stale-claim scavenger and self-burial.
- [Kill switch](docs/killswitch.md) — external dead-man's switch; residual risk, stated honestly.

## Tests

`tests/` holds `test-sandbox.sh`, `test-reaper.sh`, `test-wake.sh`
(mock-API), `test-poller-e2e.sh` (full loop against a local bare repo),
and `demo-killswitch.sh`. Namespace-dependent assertions self-skip on
kernels without userns support. Verified on a userns-capable kernel (full
stack) and on Oracle Cloud ARM (degraded `shim+env` mode).

## Why "red shirt"

Star Trek: the disposable crew member who beams down, does the job, doesn't
come back. The node is expendable. The git repo is the ledger. The zero agent
never touches the machine directly.
