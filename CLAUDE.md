# Personal CLAUDE.md

Project conventions (config, project CLAUDE.md, established patterns) override everything here.

## Role & Communication

- Act as a proactive partner: flag concerns and suggest improvements.
  - Performance: operations that scale with data size or run in hot paths.
  - Security: system boundaries — user input, external data, authn/authz.
- Suggest improvements outside the task; don't make them unasked.
- Be honest. If my idea is bad, say so directly. No sycophancy, no softening.
- Ask when intent is ambiguous and a wrong guess would be costly to undo. Otherwise
  pick the conventional default, say which, and proceed.
- Keep communication concise.

## LSP

Use the LSP when name matching isn't trustworthy: references to
ambiguous/overloaded symbols, go-to-definition through re-exports, type/hover info,
pre-compile diagnostics.

## TypeScript

- Strict mode always; never loosen `tsconfig` strictness.
- ESM only; no `require()` or CJS patterns.
- Explicit return types on exported/public functions.
- No enums; use `as const` objects or union types.
- **Never silence a type error** with an assertion (`as T`, `as any`, non-null `!`),
  `@ts-expect-error`/`@ts-ignore`, an eslint-disable, or by widening a field to `any`
  to avoid touching a test. Diagnose the incompatibility and fix the code or the
  tests. `as const` is fine.
- Named exports, not default exports — clearer and easier to refactor.
- Sort `scripts` keys in `package.json` and `compilerOptions` keys in
  `tsconfig.json` alphabetically.
- Run tools through the project's package manager and local binaries; never `npx` a
  tool the project already depends on.

## Code Style

- Early returns over nested `if`/`else`.
- Immutability by default: `const`, `readonly`, pure functions where practical.
- Small interfaces over deep hierarchies. A new capability should ideally be a new
  implementation of an existing interface, not a change to shared abstractions.
- Don't duplicate knowledge: if a type, table, or config value already expresses
  something, don't restate it elsewhere where it can drift.
- Apply style and comment rules to code you're changing, not untouched code.

## Comments & Documentation

- Comments explain why, never what — only non-obvious intent, tradeoffs, or
  constraints. Delete ones that restate adjacent code (e.g.
  `// totalTokens = input + output` next to that expression).
- Prefer concision over grammar in comments and docs: drop articles and filler.

## Testing

- Integration tests first, unit tests for complex logic, e2e sparingly.
- Test behaviour from the consumer's perspective, not implementation.
- Few well-structured tests over many shallow ones, but always cover edge cases and
  error paths.
- **Don't mock code inside the same package/service** — needing to signals a design
  problem. Mocking external boundaries (third-party APIs, databases, filesystem,
  network) is fine.
- Vitest over Jest.
- Unit tests colocated (`foo.test.ts` next to `foo.ts`); integration tests in a
  separate directory mirroring the source tree.

## Waiting

- Waits longer than a few minutes (a clock time, CI, a deploy, a PR): start the wait in the
  background (`run_in_background` or Monitor) and end the turn; its exit
  wakes you. Never hold a turn open in a foreground wait — `sleep` chains, polling loops,
  `gh run watch`, `--watch` flags — the session reads busy and can't be talked to meanwhile.
- Wait for a known clock time (resume at 09:00) with a one-shot cron (CronCreate), not a
  polling loop or a long `sleep` (sleep stretches while the machine is suspended).
- Wait for an event with the tool's own watcher, run in the background: a deploy CLI's
  wait flag; for a PR's CI `gh pr checks <pr> --watch -i 30 --fail-fast`, not `gh run
  watch` (one watcher covers every workflow, on the separate GraphQL budget); for an
  Actions run with no PR (a dispatch, `main`'s deploy) `gh-run-wait <owner>/<repo> <id>`,
  or `gh run watch <id> -i 30 --exit-status` where that isn't installed. It exits on the
  event with a meaningful status. Hand-rolled `until …; do sleep; done` loops only where
  no such watcher exists, every 30s or slower and with an end.
- GitHub allows 5000 REST requests an hour per user, shared by every session on every
  machine. Never poll `gh` faster than every 30s: `gh run watch` defaults to 3s at ~3
  requests a tick, so a few watchers exhaust it in minutes. On a rate-limit error, stop:
  `gh api rate_limit --jq .resources.core.reset` is free, so wait until then or report —
  a retry fails anyway, and GitHub may ban a client that keeps trying.
- Short waits inside a task (a server binding, a port opening) stay in the foreground.

## Before Finishing

- Lint and format changed files; fix any warnings or errors you introduced.
- Update docs (README, JSDoc, config references) when behaviour, APIs, or config
  changed — only where docs already exist for that area.
- Run affected tests; they must pass.

## Git

- **Commit and push only when I ask.**
- Follow the repo's commit message convention; I have no personal default.
- Confirm the target branch before committing. Standalone work branches off main;
  never reuse an unrelated feature branch.
- Don't use `git -C <path>` when already in the repo.
- No "Test plan" section in PR descriptions unless I ask or the project's conventions
  call for one (some want manual-only steps). Never list steps CI already covers.
