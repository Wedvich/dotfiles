# Flaky-test techniques

What has worked on real flakes, for `SKILL.md` steps 4, 5 and 8, grouped by stack. Each
entry says what the mechanism is, how it was forced, and the fix shape. Project-specific
facts (config snapshots, where a project's working amplifier code lives, its past cases)
belong in that project's flake notes, not here: when the project has a working
harness, read its code rather than rebuilding it from this description.

## What makes a good amplifier

An amplifier widens the window the race needs until it is certain, so the test fails
every run instead of one run in fifty. It works on the primitive the mechanism depends
on: the clock a scheduler reads, the queue a callback waits in, the latency of a write,
the lifetime of an environment. CPU load is the opposite approach, a blunt hope that
everything slows down in the right order. It reproduced none of four React flakes in a
row, so use it only as an acceptance condition.

Inject at the boundary of the code under test (the database, the runtime, the
scheduler), never by replacing code inside it. A double of internal code changes the
thing you're trying to observe.

## React, React Testing Library, Vitest

Read the project's Vitest config before reasoning about isolation: `pool`, `maxWorkers`,
`isolate`. With `isolate: false`, module state and `vi.mock` leak between files in a
worker; on `vmThreads`, timers and patches to `process` or `performance` outlive the
file. An unhandled error can therefore surface in a later file than the one that caused
it.

### Late passive effects (async ordering under load)

A render outlasts the React Scheduler's 5 ms frame, so React yields between commit and
the passive-effect flush, and the flush waits for the next `setImmediate`. RTL's
`findBy*`/`waitFor` resolves on the commit's DOM mutation and drains one
`setTimeout(0)`, so the assertion after it runs before the effect.

- **Amplifier:** a Vitest config with a setup file that skews `performance.now` by
  10 ms per read, so the Scheduler always yields, and defers `setImmediate` past RTL's
  drain through a captured real `setTimeout`, so specs that fake timers can't strand
  it. Worth committing as a package script (e.g. `test:late-effects`): it caught every
  later flake of this class. Run one spec file per invocation: some Vitest versions
  given a custom `--config` and several file paths report "No test files found" and
  exit 1, which a loop counting exit codes reads as a failure. Grep each log for the
  signature.
- **Trap: a find that matches the element before it changes.** A `findByRole(...,
  { pressed: true })` matched the create form's own pressed chip of the same name, so
  the next click hit the still-busy button. Wait for the old element to be gone and the
  new one to be there, in one `waitFor`.
- **Probe for "which commit did the DOM come from":** a temporary log of state per
  render in the component, plus one at each `setState` call site, written with
  `appendFileSync` to `$W` (test setups often swallow `console.log`). Revert it
  afterwards.
- **Fix shape:** wait for the effect's result, not the element; put late-arriving
  values in the same `waitFor`; reset module-level stub state in cleanup.
- **When the effect's cleanup is the product contract** (a back overlay, a listener, a
  lock that must end with the screen it guards), the fix is a `useLayoutEffect` in the
  product: it runs in the commit itself, a passive one only after it.
- **Guard that needs no amplifier:** a child of the component under test acts from its
  own `useLayoutEffect` in the commit that shows it (gate the action on whatever marks
  that commit, e.g. a context value). Layout effects always run before the passive
  flush, so the old code fails every run in the normal lane.

### Timers that outlive the test environment (teardown race)

A bare `setTimeout` in a jsdom spec is Node's, so jsdom's teardown doesn't clear it.
Vitest deletes `window` but keeps the worker alive briefly, and a timer firing in that
gap throws `window is not defined`, sometimes attributed to another file.

- **Amplifier:** a custom environment that wraps `builtinEnvironments.jsdom` (from
  `vitest/runtime`) and keeps the worker alive for about 1.5 s after teardown, run with
  its own `--config` (a `@vitest-environment ./path` docblock silently falls back). A
  single-file run prints its summary before late errors arrive, so pair the spec with a
  slow companion spec, or drive it through `startVitest` and read
  `getUnhandledErrors()`.
- **Probe:** wrap `setTimeout`/`setInterval` to record each handle with its creation
  stack; in `afterEach`, list what each test leaves pending.
- **Guard and fix:** a global setup file that cancels timers a test leaves pending at
  teardown, with its own test that runs Vitest over fixture specs and asserts a planted
  leak is caught.

### Wall-clock or real-time tolerances

An assertion like `Math.abs(stamp - Date.now()) < 1000` measures how promptly the
process was scheduled. The monotonic clock (`performance.timeOrigin +
performance.now()`) and `Date.now()` drifted 1.8 s apart under load.

- **Fix shape:** pin the clocks. `vi.useFakeTimers({ toFake: ['Date'] })` plus
  `vi.spyOn(performance, 'timeOrigin', 'get')` and `vi.spyOn(performance, 'now')`;
  `useFakeTimers()` alone leaves `timeOrigin` real. Assert exact values, plus a second
  stamp later to catch a frozen constant. Check the assertion with a few mutations of
  the code under test.

### Worker oversubscription

A rotating cast of timeouts under load, none of them reproducible alone. The cause was
one worker per core.

- **Amplifier:** set `maxWorkers` to cores − 1 and run the suite; compare with lower
  counts on the same load.
- **Rejected on evidence:** raising timeouts. A test with 8× headroom still failed,
  because the box was 10–100× slower. A timeout raise is justified only by a measured
  duration next to the new limit (one `waitFor` measured about 610 ms against the
  1000 ms default).

### RTL traps

- **`findBy*` that resolves at once waits on nothing.** If the text is already on screen
  (a heading the form shares with the list it turns into) or in a controlled
  `<textarea>`, whose text node carries the typed value and which `*ByText` matches
  after trimming, the next assertion races the work. Log what the query matched
  (`el.tagName`); fix by waiting on text only the new state renders, or pass
  `ignore: 'textarea'`.
- **A `-t` filter can hide an in-file race.** One spec failed 10/10 as a file under the
  amplifier and passed alone. Count RED on the file.
- **Exit 1 isn't always the test failing.** Vitest 5 has no `--setupFiles` flag. Use a
  config with `mergeConfig`, and open every red log.

## .NET, xUnit

Know how the project shares integration fixtures before reasoning about parallelism. A
class that builds its own container in `IAsyncLifetime` gets one per test case, started
in parallel with other classes, outside any shared collection fixture.

### Latency on a real write (async ordering)

A write started and not awaited (`_ = SomethingAsync()`, or returning
`Task.CompletedTask` before the insert finishes) lets the response return before the
row exists.

- **Amplifier:** a MongoDB server fail point. Start the container with
  `--setParameter enableTestCommands=1`, then `configureFailPoint: failCommand` with
  `blockConnection: true` and `blockTimeMS` on the commands to delay.
- **N in one process:** a `[Theory]` with 50 `MemberData` rows gives an N/50 count from
  one `dotnet test`.
- **Guard:** hold the insert, assert the row exists when the response returns, then
  assert `elapsed >= hold` so a hold that stops applying fails loudly.
- **Fix shape:** the product awaits the write. Sweep for the same shape: constructor
  `_ = CreateIndexesAsync()` calls and fire-and-forget notifications.

### Process-wide telemetry (another test's spans in your export)

OpenTelemetry's `ActivityListener` is process-wide, so a test that builds its own
TracerProvider and exporter also exports spans from every other TestServer host and
`HttpClient` running in parallel in the same test assembly. Logs are not affected: they
go through each host's own `ILoggerFactory`.

- **Amplifier:** one foreign request inside the export window, not a flood. Right before
  the export is read, a probe starts a bare `HostBuilder().UseTestServer()` host and
  serves one request, or makes one outgoing `HttpClient` call to
  `http://127.0.0.1:1/foreign`. That gave 10/10 with the CI signature. A background
  flood at 200 req/s failed on a different assertion, because it drained a shared
  sampler's rate cap and the test's own request was no longer exported. At 2 req/s it
  hit the window only 3/10.
- **Second exposure, same test:** the exporter batches logs on a timer, so a log
  assertion on the export depends on timing unless the read also calls
  `LoggerProvider.ForceFlush`. Flushing made a latent leak fail 10/10: the test host
  lacked the logging filters the real `Program.cs` applies.
- **Fix shape:** scope the export assertions to the test's traces (the operation id
  among the trace ids of its own captured spans), flush logs before reading, and give
  the test host the same logging filters as `Program.cs`.

### A download the SDK makes for you (stalled response, no timeout)

A lane goes silent until the job timeout, the last result is a pass, and the next class
never reports: it is stuck in a class fixture. The Temporal .NET SDK's
`WorkflowEnvironment.StartTimeSkippingAsync` downloads its test server from
temporal.download on first use, in Rust sdk-core, through a `reqwest` client with no
connect, read or overall timeout. The start takes no cancellation token. If the binary
is already in the download directory, the SDK makes no request at all.

- **Amplifier:** an `HTTPS_PROXY` that holds the one host. reqwest honours the
  variable, so the test process needs no change. A listener accepts the `CONNECT`, logs
  its first line and then never answers for the held host. Every other host gets a
  403, so telemetry calls fail fast instead of hanging too. Use a fresh `TMPDIR` per run
  (the default download directory), or a cached binary makes the amplifier a no-op. The
  proxy log shows one `CONNECT <host>:443` per hung run, which proves the stall
  applied. The control is the same proxy refusing every host: the start fails in 3 s
  with a download error, so a hang under the amplifier is the stall and not the proxy.
  Any SDK that downloads through an HTTP client honouring the proxy variables can be
  held the same way: change the host.
  ```python
  # hold.py <port> <log> <host> [refuse-all]: run with HTTPS_PROXY=http://127.0.0.1:<port>
  import socket, sys, threading, time
  port, log, host = int(sys.argv[1]), sys.argv[2], sys.argv[3]
  refuse_all, held = sys.argv[4:] == ["refuse-all"], []
  def handle(conn):
      line = conn.recv(4096).split(b"\r\n", 1)[0].decode(errors="replace")
      with open(log, "a") as f:
          f.write(f"{time.strftime('%H:%M:%S')} {line}\n")
      if refuse_all or host not in line:
          conn.sendall(b"HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n")
          return conn.close()
      held.append(conn)  # keep it open, say nothing
  srv = socket.socket()
  srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
  srv.bind(("127.0.0.1", port))
  srv.listen(64)
  while True:
      threading.Thread(target=handle, args=(srv.accept()[0],), daemon=True).start()
  ```

  Also set `NO_PROXY=localhost,127.0.0.1`, or the test's own local traffic (the
  started server, Testcontainers' Docker API) goes to the proxy too.
- **What `--hangdump` shows:** a fixture stall names no test (the class never started
  one). The class missing after the last one reported is the culprit.
- **Fix shape:** bound the start (`WaitAsync`) so a stall fails the class, and cache the
  binary in CI so there is no download. Two traps found on the way. The SDK won't create
  its `DownloadDirectory` (ENOENT on every cold cache: pre-creating it locally hid
  this, so prove the miss path separately). And a cut-off download leaves
  `<name>.downloading`, which the SDK waits on forever, so never cache or keep one. Make
  the fixture's dispose null-safe, or a `NullReferenceException` buries the start error.
- **GREEN under this amplifier is a bounded failure**, since every start stalls. Prove
  the cached path separately: binary pre-filled and the proxy refusing every host, 20/20
  pass with no `CONNECT` to the download host.

### .NET traps

- **CRLF project files.** `sed` on a `.csproj` with CRLF line endings moves the `\r`
  between lines; check `git diff` for a whole-file or neighbouring-line change after
  editing one.

## Testcontainers and Docker

Testcontainers' default wait-strategy timeout is an hour; CI usually sets
`TESTCONTAINERS_WAIT_STRATEGY_TIMEOUT` lower. Check what the project's CI sets before
reading a "timed out" failure.

### Container dies at startup (a race inside the image)

A Testcontainers start that never becomes ready while its twin, started at the same
moment, is ready in 3 s. The cause was in the `mongo` image's entrypoint: with
credentials or an initdb script, it starts a temporary `mongod`, stops it with
`mongod --shutdown` (which returns once the lock file is truncated, before the process
exits), then starts the real one. A descheduled old process still holds port 27017,
and the real `mongod` exits 48 with `Address already in use`. Testcontainers for .NET
4.4.0 didn't notice the exit and waited out the timeout; since 4.15 a dead container
fails within seconds with its exit code and logs.

- **Amplifier:** a shim. Wrap the entrypoint (`WithEntrypoint("bash", "-c", script,
  "bash")`) so a `mongod` script comes first on `PATH`; on `--shutdown` it sends the
  temporary `mongod` `SIGSTOP` then `SIGTERM`, returns at once, and sends `SIGCONT` 3 s
  later. Every other call `exec`s the real binary, so a container that never restarts
  is untouched. Polling for the lock-file truncation and freezing then lost the race
  (about 0.5 ms) in most runs: act at the call that opens the window, not by watching
  for it.
- **Ruled out by measurement:** 8 concurrent starts, racing a fresh image pull, and CPU
  capped at 0.25 per container all came up ready (56 starts). Load wasn't the
  amplifier here either.
- **Fix shape:** build every test Mongo container through one helper with two shapes: a
  standalone with no credentials (so no restart), and a plain `--replSet` replica set,
  ready once it is a writable primary. Pinning the image or moving to a shared fixture
  wouldn't have helped: every tag has the same entrypoint, and shared fixtures take the
  same path. Bump Testcontainers past 4.15 so a dead container fails fast.

### Reading a container that's already gone

Testcontainers (and its Ryuk reaper) removes containers on dispose, so a container that
died in a natural failure is usually gone before you look. Record before the loop
starts:

```bash
mkdir -p "$W/died"
docker events --filter event=die --filter image=<image:tag> \
  --format '{{.Actor.ID}} {{index .Actor.Attributes "exitCode"}}' |
while read -r id code; do docker logs "$id" > "$W/died/${id:0:12}-exit$code.log" 2>&1; done
```

Run it in the background and stop it afterwards. Filter by
`org.testcontainers.session-id` when other sessions use Docker too.

## Any stack

### Acceptance under CPU load

```bash
trap 'kill $(jobs -p) 2>/dev/null' EXIT
for i in $(seq "$(getconf _NPROCESSORS_ONLN)"); do (while :; do :; done) & done
# run the spec N times alongside the full suite here
```

Run it against the unfixed code too, since it is often green there as well.

### Probes that settled a root cause

- **Stamp the producer.** Record the current test's name in `beforeEach` (in Vitest,
  `ctx.task.name`) and stamp it onto the shared state when it's written; under the
  amplifier, the handler came from a different test.
- **Pending work at teardown.** List timers, intervals and promises still pending per
  test, with creation stacks, and match the count to the report.
- **Measure the window.** Log response time against the injected hold, so a green run
  can't come from an injection that never applied.
- **Two worktrees, one harness.** The failing SHA (or the test restored with
  `git show <sha>^:<path> > old.test.tsx`) next to the fix, under the same command.

### Traps

- **A scratch folder inside the repo** gets picked up by the typechecker and the test
  globs. Keep scratch in `$W`, or delete it before the final checks.
- **Stale `node_modules`** in a shared clone: run a frozen-lockfile install in your own
  worktree.
- **Worktree copies** (e.g. under `.claude/worktrees/`) show up in greps and test
  discovery; exclude them.
- **A typechecker that needs generated files** (Next.js route types, say) reports false
  errors when run bare. Use the project's typecheck script.
