# Wake trigger (task 002)

The redshirt kept its pull posture but killed the nap. `wake.sh` runs as a
child of the poller and long-polls the repo's commits API for the inbox path:

```
GET https://api.github.com/repos/<owner>/<repo>/commits?path=tasks/<name>/inbox&per_page=1
```

with `If-None-Match` / ETag conditional requests every 5 seconds. When the
inbox path changes, the daemon touches `$WORKDIR/.wake`; the poller's sleep
loop (`wait_with_wake`) notices within ~2s and starts the cycle immediately.
Task lands in the repo → shirt starts within **~5 seconds** instead of ~60.

## Why this mechanism

- **Outbound-only.** It is pure client-initiated HTTPS. There is no webhook
  receiver, no inbound port, no new path from the cloud into the box — the
  threat model of "the cloud can reach the node" does not change.
- **No extra infrastructure.** No message bus, no relay server to run.
- **Rate-limit safe.** Conditional requests that return `304 Not Modified`
  do not count against the GitHub API rate limit, so 5s polling is
  sustainable even unauthenticated. `GITHUB_TOKEN` in the environment is
  honoured for private repos / higher limits.

A true server-push long-poll was considered; GitHub offers none for repo
content, and adding our own relay would violate the "no new inbound path"
constraint that motivated the task.

## Failure mode: degrade to polling, never to silence

If the API becomes unreachable, the daemon logs the failure, keeps retrying
every 5s, and after 12 consecutive failures backs off to 60s between
attempts — while the poller keeps its plain 60s cycle regardless. If the
`wake.sh` process itself dies, the poller never notices: `wait_with_wake`
simply never sees a `.wake` file and sleeps the full interval. The trigger
is a latency optimisation, not a liveness dependency.

Disable with `--no-wake` at install time.

## Verifying

`tests/test-wake.sh` runs the daemon against a mock commits API (python3
http.server with ETag semantics): it asserts the daemon stays quiet on 304s,
fires `.wake` within ~7s of a simulated inbox change, and survives the mock
server dying (keeps running, logs the degradation).
