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
sandbox runs `shim+env` only. That still enforces the command allowlist and
the network stubs — `rm -rf ~` fails (rm is not allowlisted), `curl evil.com`
fails (stub) — but it **cannot** stop an allowlisted interpreter from writing
to world-writable paths: `python3 -c 'open("/tmp/x","w")'` will succeed.
If you need full containment, run the redshirt on a userns-capable kernel;
check the result file's `sandbox: layers active:` line to see which stack a
task actually ran under.

## Verifying

`sandbox.sh` announces its active layers on stderr for every task, and the
announcement is captured into the outbox result. `tests/test-sandbox.sh`
exercises: allowlisted success, `rm -rf ~` refusal, network-stub refusal,
and (where namespaces exist) read-only enforcement outside the workdir.
