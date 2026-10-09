# Result: final-001

node: verify3
at: 2026-10-09T06:23:50Z

## output

```
sandbox: allowlisted command 'claude' not found on this machine
sandbox: WARNING: kernel namespaces unavailable — running DEGRADED (shim+env only).
sandbox: degraded mode stops naive commands only: PATH-based 'rm' is not
sandbox: allowlisted (exit 127) and PATH-based 'curl' hits the stub (exit 126),
sandbox: but a task that resets PATH or uses absolute paths
sandbox: (/bin/rm, /usr/bin/curl) BYPASSES both. Pass RS_STRICT=1
sandbox: (--strict at install) to fail closed instead. layers: shim+env
sandbox: (workdir: /home/ubuntu/.redshirt/work/tasks/verify3/outbox/.task-final-001)
sh: 1: date: not found
proof written to persistent location
```

exit: 0
