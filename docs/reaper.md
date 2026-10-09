# The reaper: proper death (task 003)

Two gaps, both closed:

## 1. The scavenger — stale claims get requeued

Claims are no longer empty `.claimed` marker files. Claiming a task writes
`inbox/<task>.md.claimed` containing:

```
name=<node>
claimed_at=<epoch>
heartbeat=<epoch>
```

The claim is created atomically (`noclobber`, so exactly one shirt wins a
race), and the owning shirt refreshes `heartbeat` every 30s while the task
runs. `reaper.sh` runs at the top of every poll cycle — and standalone, by
the zero agent or any other shirt — and requeues any task whose claim
heartbeat is older than `REAP_AFTER` (default 300s, `--reap-after` at
install): the claim file is deleted, the task becomes claimable again, and
the event lands in `outbox/reaped.log`.

A long task is never mistaken for a dead shirt: the heartbeat pumper runs
for exactly as long as the task process does.

## 2. Self-burial — no corpse

`redshirt.sh` installs an `EXIT` trap: on timebox expiry *or any other exit*,
`bury()` kills the shirt's children (wake daemon, heartbeat pumpers) and
`rm -rf`s `$HOME/.redshirt` — workdir, repo clone, config, logs. The results
were already pushed to git; the node itself leaves literally nothing.

(The external killswitch, task 008, performs the same burial after SIGKILL,
for the case where the EXIT trap never runs.)

## Verifying

- `tests/test-reaper.sh`: builds a fake inbox with a fresh claim, a stale
  claim (heartbeat 1000s old), and an unclaimed task; asserts only the stale
  one is requeued and `reaped.log` records it.
- `tests/demo-killswitch.sh` ends with a burial check: after the deadline,
  `~/.redshirt` does not exist.
- Live drill: kill a shirt mid-task (`kill -9` the poller pid); within one
  poll cycle the next `reaper.sh` pass requeues the task and another shirt
  (or the same node reinstalled) picks it up. Let a shirt expire naturally
  and confirm `ls ~/.redshirt` → no such directory.
