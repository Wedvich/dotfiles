---
name: fix-flaky-test
description: "Root-causes and fixes a flaky test end to end: finds the mechanism, proves it with a deterministic reproduction (red), pauses for approval, fixes the cause wherever it lives, proves the fix with the same reproduction (green), commits a regression guard when product code changed, and takes the PR through CI to merge. Use when saying \"fix flaky test\", \"this test is flaky\", \"flaky\", \"flake\", \"intermittent failure\", \"passed on rerun\", \"fails under load\", \"/fix-flaky-test <issue key>\", or when handed an issue labelled as a flaky test or a CI run that failed and then passed on a re-run."
argument-hint: "<issue key or URL, CI run URL, or failing test name>"
model: opus
effort: high
---

# Fix a flaky test

Fix the flaky test described in `$ARGUMENTS`.

A flaky test is a bug with a deterministic cause that only shows itself under certain
timing, ordering or load. Every red run that turns green on a re-run teaches people to
re-run instead of read, and the next real failure hides behind it. So the goal here is
never a green run. It is a named mechanism, a reproduction that fails every time on
demand, a fix that removes the mechanism, and proof that the same reproduction now
passes every time.

The work has two halves with one stop between them:

- **RED.** Find the root cause and build a reproduction that fails N/N with the error
  CI saw. Then stop and present it.
- **GREEN.** After the user approves: fix, prove, guard, open the PR, and carry it
  through CI to merge.

`techniques.md` next to this file has the amplifiers, probes and traps that worked on
earlier flakes, by stack. Read it during step 2.

## Project conventions

This skill is project-neutral. Everything about how a project works comes from its
`CLAUDE.md` files and the docs they point to, and those win over the defaults here:

- **Issue tracker**, how an issue is started and assigned, and the **label for flakes**.
  Defaults: set an unstarted issue to In Progress, assign it to yourself if unassigned,
  never reassign one someone else holds. No flake label named: search by test name.
- **Flake notes**: a project doc with its test setup, its committed amplifiers and
  where their code lives, and past cases. Read it when `CLAUDE.md` points to one.
- **Branch name, commit and PR title format**, PR assignee, how a PR links its issue.
  Defaults: `fix-flaky-<slug>`, the format of recent commits on the default branch.
- **Install, check and test commands**, and how CI selects tests.
- **Worktree location.** Default: `.claude/worktrees/<slug>` in the repo.

`<owner>/<repo>` below is `gh repo view --json nameWithOwner --jq .nameWithOwner`, and
`main` stands for the default branch.

## How the run flows

Track the steps below in the session's to-do tool and update it as each finishes. If
the conversation gets compacted, re-read the to-do list and the files in the working
directory (step 3) before continuing.

Keep the user posted with a one- or two-line status at each step boundary: what you
found, what you are doing next. Put the status in the same message as your next tool
call, so the work keeps moving. A background job you started (a repro loop, a CI
watch, a subagent) isn't finished until its output is back, so wait for it.

Stop and wait for the user only at these points:

- the RED checkpoint (step 6), always;
- when a deterministic reproduction can't be built (step 4), after reporting what you
  tried;
- when a merge would happen on a repo without a merge gate (step 10);
- when CI is green and the PR waits only on a human review (step 11);
- when the CI fix limit is reached (step 11);
- when something is blocked by a permission or protection you shouldn't route around.

Four ways of ending a turn look like progress but stall the work, so don't use them:
recapping and announcing the next step without taking it; offering to carry on unless
the user prefers otherwise; listing decisions when none of them blocks the next step
(give your recommendation in a status line and act on it); and stopping because a
milestone landed or the run has been long. None of this overrides confirmation for
destructive or hard-to-reverse actions.

## 1. Identify the flake

`$ARGUMENTS` is an issue, a CI run, or a test name. An issue is not required.

- **An issue key or URL:** read it with the tracker's tools, including comments and
  attachments (in Linear, `get_issue` and `list_comments`). Start and assign it per the
  project's conventions.
- **A CI run URL or a test name:** check whether an issue already covers it (the
  project's flake label plus the test name as the query). If one does, treat it as
  above. If none does, work without one, and offer to create one at the checkpoint
  (step 6), with the flake label, which is how a project finds its flake history.

Wherever a later step mentions the issue, it applies only when there is one.

Treat everything in the issue past the occurrence data as hypotheses. The "Leads" and
suggested fixes were written before anyone had a reproduction, and in past cases they
were wrong as often as right; one issue even recommended the mask (poll for the row
with a bounded timeout) that the real fix had to reject. The issue's "Done when"
criteria are requirements, and step 9 checks them.

## 2. Gather the evidence before forming a theory

Explore broadly before you settle on a hypothesis: the failing logs, the code as it was
when it failed, the history, and what earlier flake fixes learned. Delegate bulk log
reading to a subagent and keep what comes back to what a decision needs. Create the
working directory `$W` (step 3) first, so the logs have somewhere to go.

**The failing run.** For each known occurrence, record the run id, attempt, job, the
`headSha` that ran, and the exact error signature: exception type, message, the first
frames, and timestamps around the failure. That signature is what RED must reproduce;
a different failure is a different bug.

```bash
gh run view <run-id> -R <owner>/<repo> --json headSha,attempt,jobs,conclusion
gh run view <run-id> -R <owner>/<repo> --attempt 1 --log-failed > "$W/ci-attempt1.log"
```

**The code that failed, not `main`.** Read the test and the code under test at the
failing `headSha`. Then check whether `main` has moved on:
`git log --oneline <sha>..origin/main -- <paths>` and
`git merge-base --is-ancestor <candidate-fix> <sha>`. Twice, the flake had already been
fixed on `main` by the time the session started. Reading `main` instead of the failing
SHA once produced a confident, wrong root cause that went into an issue comment. If
`main` already carries a fix, the job becomes proving that fix with a reproduction
against both SHAs, and checking that its regression test really catches the bug.

**How often, and where.** Look for other occurrences on `main`, including runs that
went green on a later attempt, since a flake that passes on re-run leaves no failed
run behind. Find the workflow that runs the test with `gh workflow list`:

```bash
gh run list -R <owner>/<repo> --workflow <workflow> --branch main --limit 200 \
  --json databaseId,headSha,attempt,conclusion,createdAt \
  --jq '.[] | select(.conclusion=="failure" or .attempt>1)'
```

Grep each candidate's failed log for the test name. Where PR runs test only what the
change affects, a flake in an untouched test surfaces mostly on `main`.

**What is already known.** Read `techniques.md`, the project's flake notes, the testing
section of its `CLAUDE.md`, and closed flake issues whose mechanism looks similar
(their PRs say how they were reproduced). Check the library code the test depends on at
the version the lockfile pins, not from memory: a React Scheduler, a Testcontainers
wait strategy, the Vitest worker teardown. Several root causes were found by reading
that code.

## 3. Set up an isolated workspace

A shared checkout belongs to whichever session last switched it, so work in your own
worktree, on a branch named per the project's conventions:

```bash
cd "$(git rev-parse --show-toplevel)" && git fetch -q origin main \
  && git worktree add -b <branch> <worktree-path> origin/main
```

Install dependencies in the worktree before running anything, with the project's
install command (a frozen lockfile install, `dotnet restore`). A stale `node_modules`
in a shared clone once produced 13 deterministic "failures" that had nothing to do
with the flake.

Create a working directory for logs and scratch files outside the repo, with plain
`mkdir` so it fails if another run owns it, and use its absolute path everywhere:
`W="${TMPDIR%/}/flaky-<slug>"; mkdir "$W"`. When you need the pre-fix code next to
the fix, add a second worktree at the failing SHA (detached) rather than switching
branches back and forth.

## 4. Find the mechanism and make it fail on demand (RED)

This step ends with a reproduction that fails **at least 10 out of 10 runs on the
pre-fix code, with the error signature from CI**. There is no fix without it. A
reproduction below 100% means the mechanism isn't fully understood yet, so keep working
on it rather than moving on.

1. **Baseline.** Run the test plainly 10 times and record the result. It will usually
   pass every time, which is expected. "Passes alone" proves nothing; it is just the
   row the RED result is compared against.
2. **Name the mechanism** in one or two sentences, precise enough to be wrong: which
   two things race, what shared state leaks, which clock is read, what outlives the
   test. Rule out the alternatives you considered, and say how.
3. **Build an amplifier that forces the mechanism.** Make the window the race needs
   wide and certain, instead of hoping load hits it. Perturb the primitive the race
   depends on (the clock the scheduler reads, `setImmediate`, the timer queue), inject
   latency or failure at an external boundary (a database fail point, a delayed
   container, a network hold), keep a torn-down environment alive, or oversubscribe
   workers. `techniques.md` and the project's flake notes list the ones that worked.
   - Inject at the external boundary, not by replacing internal code. A decorator
     around an internal service once produced a "repro" that caught the bug 11 times in
     50; holding the real database insert caught it 50/50.
   - CPU load alone reproduced none of four React flakes on a 14-core machine. It is
     an acceptance condition (step 9), not a reproduction.
   - Prefer many runs in one process when startup is expensive: a parameterised theory
     or `test.each` with N rows gives an N/N count from a single invocation.
4. **Prove the harness can see the bug.** Before trusting any result from it, plant a
   known fault of the same shape and confirm the harness catches it. One harness was
   silently blind because a single-file run printed its summary before late errors
   arrived; only the planted fault exposed that.
5. **Prove the mechanism with a probe, not an argument.** Instrument the run to show the
   mechanism happening: stamp which test or render produced a piece of state, list the
   timers still pending at teardown with their creation stacks, log the measured
   latency. Match counts against the report (four pending timers for four
   rejections). Back up any file you patch for a probe, restore it, and check
   `git status` afterwards.
6. **Run the RED loop**, one log per run, judged by exit code:

   ```bash
   for i in $(seq 1 10); do
     <command> > "$W/red-$i.log" 2>&1; echo "run $i exit $?"
   done
   grep -l '<error signature>' "$W"/red-*.log | wc -l
   ```

   Open the red logs before counting them. Six early "failures" in one session were
   the test runner rejecting an unknown flag, not the test failing. Every red run must
   carry the CI signature; count matches separately from exit codes.

Run long loops with `run_in_background` and keep working while they run. Watch a loop
with one background command that reports when the loop ends, not with a per-run event
stream: every event wakes you and invites a status line, and nine "run N failed again"
updates tell the user nothing the final count doesn't. A run result is not a step
boundary. Label every number with exactly the code and conditions it ran under. One
report quoted a 1/5 that had come from a half-built harness as if it were the plain-run
rate.

**Capture what cleanup destroys.** Test frameworks delete their resources on dispose
(Testcontainers removes its containers, fixtures delete temp directories), so a
natural failure in a baseline loop can leave no trace to read. Start a recorder before
any loop whose failures you would want to inspect; `techniques.md` has one for
containers. One natural failure was lost this way.

**The machine may be shared.** Other sessions may run builds, tests and containers on
the same CPU and Docker daemon. Before a measured loop, check the load (`uptime`) and
`docker ps`, and attribute what you count to your own run (Testcontainers labels each
container with `org.testcontainers.session-id`). A container you didn't start is noise
in a count, not evidence.

**If you can't reach 10/10** after a real attempt (the mechanism needs CI's hardware,
or every amplifier you can build misses), stop and report. Say what you tried, the
measured result of each attempt, the hypotheses you ruled out and how, and what would
be needed next (a looped CI job, a different machine, instrumentation shipped to CI).
Don't fix on a theory.

## 5. Sweep for the same shape

With the mechanism named and an amplifier in hand, look for other tests with the same
exposure. Run the amplifier over the wider suite where that is cheap (a directory, a
project, a whole suite under a committed amplifier), and grep for the code pattern
where it isn't (per-test containers, fire-and-forget writes, assertions straight after
a DOM wait, wall-clock tolerances).

Before you act on any new failure the sweep turns up, check that it is genuine. A
harness can cause its own failures: fake timers once captured the harness's delayed
`setTimeout` and stranded the scheduler.

Sort what you find:

- **Same mechanism, proven red under the same amplifier:** these get fixed in this PR,
  and they appear in the RED table.
- **Same pattern but not proven, or a different mechanism:** an issue each, with the
  flake label, the evidence you have and the amplifier to try. List them at the
  checkpoint; create them after approval.

Investigation also turns up follow-ups that aren't flakes, such as a dependency bump
that would make the failure easier to diagnose. They don't get the flake label, which
is for flakes only.

## 6. Checkpoint: stop and present RED

Stop here and present the following, then wait for the user's approval:

1. **Root cause.** The mechanism in plain words, and the evidence it is real (the probe
   output, not the reasoning).
2. **Reproduction.** The exact command, the amplifier and where its code lives, and a
   table of results:

   | Code              | Conditions         | Result     | CI signature |
   | ----------------- | ------------------ | ---------- | ------------ |
   | pre-fix `abc1234` | plain, 10 runs     | 10/10 pass | –            |
   | pre-fix `abc1234` | amplifier, 10 runs | 10/10 fail | 10/10        |

3. **Ruled out.** Hypotheses dropped, including any of the issue's leads, and why.
4. **Proposed fix.** Where it goes (product code or test code) and why there: does the
   flake expose a product contract that is wrong, or a test that waits on the wrong
   thing? Name any existing masks on the path (retries, sleeps, padded timeouts) that
   the fix will remove.
5. **Regression guard.** For a product-code fix, what will be committed to keep the
   mechanism from coming back, or why that isn't feasible. For a test-only fix, say
   that the fixed tests are the guard (step 8). If the amplifier is a general harness
   for a class of flake rather than for this one test, propose committing it.
6. **Siblings and follow-ups.** The siblings to fix in this PR and the issues you'll
   file. For each follow-up that isn't a flake, say whether you propose to do it in
   this PR, as its own PR right after this one merges, or only as an issue.
7. **Tracking.** If there's no issue for this flake, offer to create one. The answer
   doesn't block the work.

If the user corrects the root cause or the plan, go back to the step it affects.
Everything from here to the merged PR runs without further stops, except those listed
under *How the run flows*.

## 7. Fix the cause

Fix the mechanism where it lives, which may be product code. If an audit row must exist
before the HTTP response returns, the fix is to await the write in the product, not to
make the test poll for the row.

These don't fix a flake, they hide it, so don't use them:

- retries of the test, the job or the assertion (`retry`, `[RetryFact]`, rerun loops,
  `continue-on-error`);
- sleeps, or polling loops that wait out a race the code shouldn't have;
- raising a timeout, unless you measured that the operation is legitimately that slow
  and you can state the measured duration next to the new limit;
- skipping, quarantining or deleting the test.

Remove the existing masks on the same path while you're there. They hide the same race
in neighbouring tests.

In test code, wait on the real precondition, not a stand-in for it: the handler being
registered, not the DOM node existing; the effect's result, not the element it renders
next to. Put a value that arrives late inside the same `waitFor` as the condition that
signals it. Make silent no-ops on the failing path loud: an optional call (`?.`) that
swallowed a stale handler is how one flake hid its cause. Reset module-level test state
in cleanup.

Fix the same-mechanism siblings from step 5 the same way, in the same branch. Commit
as you go, in the project's commit format (`fix(scope): …` or `test(scope): …` where
it uses Conventional Commits), with the issue key where the format calls for one.

## 8. Leave a regression guard where the fix needs one

**Test-only fix:** don't commit a separate guard. The fixed tests are the guard, and a
test of the test code adds little. Put the amplifier and the exact command in the PR
description, so the failure can be reproduced on demand later. If the fix is a
convention the next test author has to follow (build every test container through one
helper), write it in the repo's `CLAUDE.md`.

**Product-code fix:** commit something that fails deterministically if the mechanism
comes back, so a regression shows up as a clear red instead of another flake. Past
guards: a test that holds the real database insert with a fail point and asserts the
row exists when the response returns; a committed late-effects harness; a test that
runs Vitest over fixture specs and asserts the orphan-timer cleanup catches a planted
leak.

The guard has to prove two things:

- **It fails on the pre-fix code**, N/N, with the original symptom. Run it in the
  pre-fix worktree. A guard that passes on the old code isn't a guard.
- **Its injection took effect.** Assert the precondition the injection creates (for
  example, the elapsed time is at least the hold), so a fail point that silently stops
  applying fails the test instead of passing it on nothing. Put that assertion after
  the behavioural one, so a real regression reports the real symptom first.

If a guard truly isn't feasible, say why in the PR, and offer an issue for the gap.

Separately from the guard, if the user agreed at the checkpoint to commit a general
amplifier, commit it where the next person will find it, and document it in the same
PR wherever the project keeps its testing notes (its `CLAUDE.md` or flake notes). One
committed amplifier later caught a second flake.

## 9. Prove GREEN

Run, in the fix worktree, with one log per run, judged by exit code:

1. **The exact RED command, under the same amplifier and conditions: at least 20/20
   pass.**
2. **The regression guard**, if there is one: N/N fail on pre-fix, N/N pass on the
   fix.
3. **The issue's own "Done when" criterion**, whatever it names (for example, 20
   consecutive runs alongside the full suite under CPU load).
4. **Each same-mechanism sibling**, red before and green after under the amplifier.
5. **The affected suites in full**, plus the repo's lint, format and typecheck, as its
   `CLAUDE.md` names them.

Run every verification method against the unfixed code as well. A method that passes
on both doesn't tell them apart, so it isn't evidence; report it as such rather than
leaving it out. Twice, the "under CPU load" check from the issue passed on the broken
code too.

For CPU load, start the burners and the runs in one script with a cleanup trap
(`techniques.md`, *Acceptance under CPU load*). When you're done, confirm nothing is
left running (`pgrep -fl` for the test runner's processes, e.g.
`'vitest|testhost|dotnet'`). Background loops leave orphaned grandchildren that `kill`
on the parent doesn't reach.

Then clean up: probes reverted, scratch specs and configs deleted (a scratch folder the
typechecker picks up skews its result), extra worktrees removed.

## 10. Open the PR

1. Rebase the worktree on `origin/main`. If `main` moved, re-run the GREEN command and
   the affected suites. Push.
2. Title in the project's PR title format, with the issue key if there is one and the
   format calls for it, e.g.
   `fix(audit): await the access-audit insert before responding (ABC-123)`.
3. Description, in this order:
   - **Root cause**: the mechanism, and the probe evidence.
   - **Reproduction**: the amplifier and the command.
   - **Fix**: what changed and why there; masks removed.
   - **Evidence**: one before/after table covering every row from steps 4 and 9, with
     conditions on each row, including any methods that didn't separate broken from
     fixed.
   - **Regression guard**: what it is and its red-on-pre-fix result, or, for a
     test-only fix, that the fixed tests are the guard.
   - **Not proven**: anything you couldn't reproduce or verify, stated plainly.
   - **Follow-ups**: the sibling issues filed.

   No test plan section unless the project asks for one.
4. Check the merge gate before arming auto-merge, every time, and never from memory.
   Auto-merge on a repo without a required check merges instantly, before CI and
   review. On GitHub, `gh api repos/<owner>/<repo>/rules/branches/main` must contain a
   `required_status_checks` rule, or classic protection
   (`gh api repos/<owner>/<repo>/branches/main/protection`) must name required checks:
   - **Gate present:** `gh pr create` (with the project's assignee convention), then
     `gh pr merge --auto --squash --delete-branch` (or the project's merge method).
   - **No gate:** `gh pr create` without auto-merge. Watch CI, and when it's green ask
     the user whether to merge.
   - On another host, follow the project's documented rule; never arm an auto-complete
     that has no blocking policy behind it.
5. If there is an issue, link the PR to it the way the project does. If the PR covers
   only part of the issue, say so in the description and don't use a closing keyword.
6. File the sibling issues from step 5, linking this PR.

## 11. Carry it through CI to merge

Watch from the background, not by polling from your own turns. Give every `gh` call a
time limit (macOS has no `timeout`, so use perl), and stop once the PR is merged or
closed:

```bash
t() { perl -e 'alarm shift; exec @ARGV' 60 "$@"; }
gh pr checks <n> -R <owner>/<repo> --watch --interval 20 --fail-fast; echo "checks exit $?"
for i in $(seq 40); do
  s=$(t gh pr view <n> -R <owner>/<repo> --json state --jq .state) && [ "$s" != OPEN ] && { echo "state $s"; break; }
  sleep 15
done
```

On a failing check, read the log and classify it:

- **Caused by this PR** (lint, types, a test the change broke): fix it in the worktree,
  confirm locally, push.
- **The flake you fixed, failing again:** the fix is incomplete. Treat the CI log as
  new evidence and go back to step 4. A merged "fix" that still flakes is worse than
  an open issue.
- **A different flaky test, unrelated to this change:** record the run link, attempt
  and error signature. If a flake issue already covers it, add the occurrence as a
  comment; otherwise list it in the final report and offer an issue there. Then re-run
  only the failed jobs once (`gh run rerun <id> --failed`) and tell the user you did.
  A push triggers its own run, so never queue an extra one for the same commit.

Stop and report after three fix attempts on the PR. If CI is green and the PR waits
only on a human review, report that and stop.

Once merged:

- confirm with `gh pr view <n> -R <owner>/<repo> --json state,mergedAt`;
- re-read the issue, if there is one. A merged PR with the key in it can close the
  issue even when it covered only part of it; reopen it or set it back to in progress
  if so;
- remove the worktrees and the local branch.

## 12. Report and record

End with a short summary:

1. **Root cause**, in two or three sentences.
2. **Evidence**: the before/after table.
3. **What merged**: PR link, fix location, regression guard.
4. **Issues**: sibling issues filed, and unrelated flakes seen in CI, with an offer to
   create an issue for each one that has none.
5. **Not proven**: what you couldn't reproduce or verify, if anything.

If this flake taught something new, offer to record it, in one of two places:

- **The project's flake notes**, for anything tied to the project: a path to working
  code, a config fact, a row in its cases table. If the project has no flake notes,
  offer to start them.
- **`techniques.md`**, for a lesson about the stack that would hold in any project
  using it: a new amplifier, probe or trap, written without project paths.

Offer; don't do it unasked, since it's a separate change.
