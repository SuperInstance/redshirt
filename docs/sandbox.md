# Sandbox scope (task 001)

The redshirt used to run tasks with the whole shell of the installing user.
Now every task command executes inside `sandbox.sh`, which enforces three
blinders:

1. **One writable directory.** The task runs with cwd inside its own task dir
   under the outbox (`$OUTBOX/.task-<slug>`), with `HOME` and `TMPDIR`
   pointed there too — so `~` never means the installer's home. On kernels
   with unprivileged user namespaces, a mount namespace additionally remounts
   everything read-only except that directory: `rm -rf /` outside the workdir
   fails with "Read-only file system".
2. **Allowlisted commands.** The task sees a shim `PATH` containing symlinks
   only to allowlisted commands (configurable per install, default
   `git curl python3 claude`; `sh` is always present because the harness runs
   `run:` lines via `sh -c`). Anything else — `rm`, `dd`, `sudo` — fails with
   "command not found" (exit 127). Failures land in the outbox result file
   with the exit code, so a blocked task is visible, not silent.
3. **No network unless flagged.** Default installs set `NET_OK=0`: with
   namespaces, the task gets its own network namespace (loopback only); without
   them, `curl`/`wget`/`ssh`/`scp`/`nc` resolve to stubs that exit 126 with
   "network access is DISABLED for this redshirt". Pass `--net` at install
   time to allow it.

## Worst case, stated plainly

A compromised redshirt task can only touch its own task folder — **on a
kernel with unprivileged user namespaces** (full layer stack:
`shim+env+mountns+netns`). The sandbox auto-detects namespace support and
degrades loudly otherwise.

## Residual risk (degraded mode)

On kernels where `unshare` is blocked (some hardened VMs/containers), the
sandbox runs `shim+env` only — and the shim layer must be understood for
what it is: it stops **naive** commands, not a determined one. Verified by
probe on 2026-10-08 (degraded mode forced by hiding `unshare` from PATH):

- `rm -rf ~` fails loudly (exit 127, "not found") — `rm` is not allowlisted.
- `curl evil.com` fails loudly (exit 126, "network access is DISABLED") —
  the stub intercepts PATH-based lookups.
- **But** a task that resets PATH or uses absolute paths bypasses both:
  `/bin/rm -f /tmp/canary` **deleted the file** (exit 0), and
  `/usr/bin/curl http://127.0.0.1:18711/` returned **HTTP 200** despite
  `NET_OK=0`. Without namespaces there is no way to stop same-uid `sh -c`
  from doing this — the shim is a policy hint, not containment.

In full `shim+env+mountns+netns` mode the same probes are contained: PATH
resets and absolute paths still run (e.g. `PATH=/usr/bin rm -rf ~/pwned`
exits 0) but can only touch the workdir — `HOME` is the task folder, outside
writes fail with "Read-only file system", and absolute-path `curl` dies in
the netns.

## Fail closed: --strict

`install.sh --strict` (config `STRICT=1`, passed as `RS_STRICT`) makes the
sandbox refuse to run at all when namespaces are unavailable (exit 126,
loud on stderr, captured into the outbox result) instead of running
degraded. Default is `--no-strict`: degraded runs with the loud warning
above, because some hosts genuinely lack userns and the redshirt is still
useful there — but the operator has seen the residual risk stated plainly
in the install ceremony ("strict sandbox" line) before witnessing the
grant.

## Verifying

`sandbox.sh` announces its active layers on stderr for every task, and the
announcement is captured into the outbox result. `tests/test-sandbox.sh`
exercises: allowlisted success, `rm -rf ~` refusal, network-stub refusal,
and (where namespaces exist) read-only enforcement outside the workdir.
