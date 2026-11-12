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

## Code navigation and editing

Prefer tilth over the host's generic read, search, find, edit, and diff tools for
source code. Built-in tools are fine for non-code (markdown, JSON, configs, logs) —
use `git diff` there, since `tilth_diff` is structural and shows nothing useful.

### tilth notes the tools don't document

- `scope` must be an existing directory, never a file. To restrict to one file, use
  an exact `glob`, or `tilth_read` if the file is known.
- Repo-wide search: `scope: "."` with an absolute `root`, especially in worktrees.
  Omitting `scope` searches wherever the tilth server was launched.
- "Invalid scope" or fallback warning = failed narrowing. Retry with a valid
  directory `scope` or exact `glob`.
- Comma-separated queries are for symbol searches only. Terms needing different
  `kind`s (e.g. a class name and an error string) are separate calls.
- `tilth_deps` only before signature changes, renamed/removed exports, or behaviour
  changes callers rely on. `tilth_grok` only when the task is understanding one
  symbol structurally.
- `tilth_write` refuses paths outside the project root (e.g. scratchpad) — use
  built-in Write there.
- Edit rejected because file changed: re-anchor from the echoed hashlines and retry;
  don't fall back to built-in Edit.
- After a subagent or external process edits a file, `tilth_read` can serve stale
  content indefinitely. Verify with `tilth_diff` / `git diff` before relying on it.

### LSP

Default to tilth. Use the LSP when name matching isn't trustworthy: references to
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
