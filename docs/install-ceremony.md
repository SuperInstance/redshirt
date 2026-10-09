# The install ceremony (task 007)

Installation IS the permission grant, but an installer that says yes blind
is a rubber stamp. SSH shows you the host fingerprint before the yes — the
install ceremony is the one-page equivalent for a redshirt node.

## What happens

Before anything is written or started, `install.sh` probes the machine the
node will inherit and prints the result as one page in plain words:

- **NETWORK** — can it reach github.com? the open internet beyond github?
  is the installer source itself fetchable? does DNS resolve? any proxy
  variables set? local and public addresses.
- **FILESYSTEM** — which user, which home directory, is home writable, how
  much disk is free, root or not. The install scope is stated: `~/.redshirt/`
  only.
- **TASK SCOPE** — the blinders this node installs with: command allowlist,
  task network on/off, stale-claim reaping, wake trigger, killswitch state.
- **CREDENTIALS** — what the node can see: ssh private key *names* in
  `~/.ssh`, secret-like environment variable *names*, git identity, gh auth
  status, claude CLI presence. **Names only — values are never printed,
  logged, or transmitted.** The probe that enumerates a capability must not
  itself leak it.
- **SPEND AUTHORITY** — cloud metadata (link-local endpoint answering means
  this VM carries a provider identity), cloud CLIs with working credentials,
  paid API keys present in the environment. Detected-only, stated as such.

The page closes with the honest caveat: the probes are read-only and
best-effort — a few seconds of detection, not a full audit. If in doubt,
assume more, not less.

## The witnessed yes

Then a designed surface, not a prompt you can sleep through:

> This is the permission. There is no second prompt.
> Type the node name to witness the grant [hp-laptop]:

You type the node name, exactly. A mismatch aborts and nothing is installed.
The typed name is the witness — there is a human in the transcript, not just
a keypress. A receipt lands in `~/.redshirt/grant-receipt.md` (who, when,
node, timebox, public IP).

## Non-interactive installs

`REDSHIRT_ASSUME_YES=1` skips the prompt **only when stdin is not a
terminal**. Setting it is itself the grant — you are on record in your shell
history. If stdin is not a terminal and the variable is unset, the installer
refuses and exits 1 rather than guessing. There is no quiet default to yes.
