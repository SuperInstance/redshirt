# redshirt

Disposable remote appendage for a git agent. Install on any machine with one
command. It polls a git repo for tasks, executes them, pushes results back.
Then it dies when the timebox expires.

The inverse of fleet-session: instead of pushing commands to the node, the
node pulls tasks from git.

## Install

```bash
curl -sSL https://raw.githubusercontent.com/SuperInstance/redshirt/main/install.sh | bash -s <name> <hours>
```

Example: `bash -s hp-laptop 4` — runs for 4 hours, then stops.

## How it works

1. Installer clones this repo, writes config (`~/.redshirt/config`).
2. `redshirt.sh` loops: `git pull`, check `tasks/<name>/inbox/` for new `.md` files.
3. Each task file has either:
   - `run: <shell command>` — executed, output captured.
   - `claude: <prompt>` — run via `claude -p`, output captured (needs `claude login`).
4. Result written to `tasks/<name>/outbox/<task>.result.md`, `git push`.
5. Task file moved to `tasks/<name>/done/`.
6. After `<hours>`, the loop exits. The red shirt dies. No residue except the repo.

## Task format

```markdown
# task-slug

claude: Write a haiku about a fishing boat.
# or
run: echo hello && uname -a
```

## Why "red shirt"

Star Trek: the disposable crew member who beams down, does the job, doesn't
come back. The node is expendable. The git repo is the ledger. The zero agent
never touches the machine directly.

## The install ceremony

Installation is the permission grant, so the installer does not say yes
blind. Before anything is written, `install.sh` probes this machine —
what it can reach (network), where it can write (filesystem scope), what
credentials are visible (names only, never values), and what spend
authority it could inherit — prints it in plain words on one page, and
pauses for an explicit witnessed yes: you type the node name. A receipt
lands in `~/.redshirt/grant-receipt.md`.

Non-interactive installs: `REDSHIRT_ASSUME_YES=1` skips the prompt only
when stdin is not a terminal. Setting it is itself the grant.

## The captain's board

Fleet state (live nodes, current tasks, timebox remaining, heartbeat age)
is rendered from the heartbeat commits in this repo by the
`SuperInstance/muse-workspace` `fleet-board/` generator. Heartbeats are
`tasks/<name>/heartbeat.md` with machine-readable frontmatter
(node, last, started, hours, task).
