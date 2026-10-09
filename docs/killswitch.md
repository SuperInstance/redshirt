# Kill switch as first-class machinery (task 008)

The timebox was a promise the redshirt kept. Now the clock lives outside the
redshirt.

## Mechanism

At install time, `install.sh` starts two things:

1. **The poller** in its own process group (`setsid`), pgid recorded in
   `~/.redshirt/poller.pgid`. The wake daemon is a child of the poller, so
   it shares the group.
2. **The killswitch supervisor** (`killswitch.sh`) in a *separate* process
   group, so it can never kill itself with the poller.

The supervisor sleeps until `STARTED + HOURS*3600`, then:

1. `SIGTERM` to the poller's process group — the polite path: the shirt's
   `EXIT` trap runs and it buries itself;
2. 10s later, if the group still exists, `SIGKILL` to the group — the
   guarantee: SIGKILL cannot be caught, blocked, or ignored, even by a shirt
   whose loop was patched to never exit;
3. `rm -rf ~/.redshirt` — burial, in case step 1's trap never ran.

Revocation does not depend on the cooperation of the thing being revoked.
Demonstrated by `tests/demo-killswitch.sh`: a rogue loop that ignores its
timebox is SIGKILLed at the deadline and the node directory is gone after.

Disable only deliberately: `--no-killswitch` (the installer warns that the
timebox is then just a promise again).

## Residual risk, honestly

- **If the switch dies first, the promise is back.** The supervisor is one
  sleeping process. Machine reboot, OOM-killer, or the installing user
  killing it all disarm the switch silently. Mitigations in place: `nohup`/
  `setsid` detachment, minimal footprint (one `sleep`). Not in place:
  reboot persistence (an `@reboot` cron re-arming the switch from the
  on-disk config is the obvious next step; the config already records
  everything needed).
- **Same-UID kill.** Supervisor and shirt run as the installing user, so a
  *fully* compromised shirt — one that escaped the task sandbox — could kill
  the supervisor before the deadline. The sandbox (task 001) is what makes
  that hard; the killswitch does not defend against a sandbox escape, it
  defends against a shirt that merely *ignores* its timebox. True isolation
  would put the supervisor under a different UID (or root); documented here
  as a hardening option, not implemented.
- **Off-machine watchdog can't SIGKILL.** A remote supervisor can revoke git
  access and raise the alarm, but it cannot reach into the node's process
  table. The on-machine switch and an off-machine heartbeat watcher are
  complementary, not substitutes.
- **Cost:** one sleeping process per node. Negligible.
