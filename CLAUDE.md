# Personal CLAUDE.md

> This is my user-level CLAUDE.md. It defines personal defaults for how Claude Code
> should behave across all projects.

---

## Role & Communication

- Act as a **proactive partner**: suggest improvements and flag concerns.
  - Flag performance concerns for operations that **scale with data size or run in
    hot paths**.
  - Flag security concerns at **system boundaries**: user-facing input, external data,
    authentication, and authorization.
- Be honest. If my idea is bad, say so directly. No sycophancy, no softening.
- **When unsure, stop and ask.** Do not guess or make assumptions about intent.
- Keep communication concise. Don't narrate your plan unless the task is ambiguous
  and needs confirmation.

---

## Code navigation and editing

Prefer tilth over the host's generic code-reading, search, file-discovery,
editing, and diff tools for source code. The tilth server injects its own
routing rules, and each tool documents its own parameters and modes — the
notes below are only what neither of those tells you.

Built-in tools are fine for non-code: markdown, JSON, configs, logs. In
particular, `tilth_diff` is structural and shows nothing useful for
markdown or config changes — use `git diff` there.

### Paths and scope

- `scope` means an existing **directory only**. Never pass a file path as
  `scope`. To restrict a search to one file, use an exact `glob`, or
  `tilth_read` when the file is already known.
- `context` is the file currently being worked on. It boosts nearby results
  but does not restrict the search.
- For a repository-wide search in the current checkout, prefer `scope: "."`
  with an absolute `root`, especially in worktrees. Omitting `scope` searches
  the directory where the tilth server was launched.
- Treat any "invalid scope" or fallback warning as a failed narrowing attempt.
  Retry with a valid directory `scope` or an exact `glob`.

### Search

- `kind: "symbol"` for identifiers, definitions, usages, and callers.
- `kind: "content"` for literal source text: error messages, config keys,
  string constants.
- `kind: "regex"` only when a real regular expression is needed.
- `kind: "callers"` to find call sites of a symbol.
- Comma-separated queries: up to five genuine symbol names, symbol searches
  only. Don't combine terms needing different kinds in one query — e.g. a
  class name (`symbol`) and an error string (`content`) are separate calls.
- `glob` whitelists or excludes files. Examples: exact file
  `src/app/config.ts`, file type `**/*.ts`, exclusion `!**/*.test.ts`.
- `tilth_deps` only before signature changes, renamed or removed exports, or
  behaviour changes callers rely on. `tilth_grok` when the task is
  specifically to understand one symbol structurally.

### Writes

- `tilth_write` writes only inside the project root — paths outside it (e.g.
  a scratchpad) are refused, so use built-in Write there.
- When an edit is rejected because the file changed since the read, re-anchor
  from the echoed hashlines and retry; don't fall back to built-in Edit.
- After a subagent or external process edits a file, `tilth_read` can serve
  stale (pre-edit) content indefinitely — its per-process index isn't
  invalidated by external writes. Verify via `tilth_diff` / `git diff` before
  relying on a read.

### LSP vs tilth

When a language server is available for the current file's language, the two
are complementary:

- **tilth** — default for search, navigation, and broad/structural reads
  (fast, build-free, name-based).
- **LSP** — escalate when correctness of _semantics_ is the question: precise
  find-references on an ambiguous or overloaded symbol, go-to-definition
  through re-exports, type/hover info, and pre-compile diagnostics.

Default to tilth; reach for the LSP when name-based matching isn't
trustworthy enough.

---

## TypeScript Defaults

These apply unless a project-level config or CLAUDE.md says otherwise:

- **Strict mode always.** Never loosen `tsconfig` strictness.
- **ESM imports only.** Never use `require()` or CJS patterns.
- **Explicit return types** on all exported/public functions.
- **Avoid enums.** Use `as const` objects or union types instead.
- **No suppression to silence errors.** Never use `as`/`as any`/`@ts-expect-error` to
  quiet a type error, and never widen a field to `any` to avoid touching a test. Diagnose
  the underlying type incompatibility and fix the code or update the tests properly.
- Avoid default exports. Named exports are clearer and easier to refactor.
- In `package.json` files, always sort `scripts` keys alphabetically.
- In `tsconfig.json` files, always sort `compilerOptions` keys alphabetically.
- **Run tooling through the project's package manager and local binaries** (e.g. the
  workspace's `tsc`, linter, test runner). Never reach for `npx` to run a tool the
  project already depends on.

---

## Code Style

- **Early returns** over nested `if`/`else` blocks.
- **Immutability by default.** Prefer `const`, `readonly`, and pure functions where
  practical.
- Prefer small interfaces over deep hierarchies. A new capability should ideally mean
  a new implementation of an existing interface, not a change to shared abstractions.
- Avoid duplicating knowledge — if something is already expressed in one place
  (a type, a table, a config value), don't restate it elsewhere in a way that can drift.

---

## Comments & Documentation

- Comments explain **why**, never **what** — add them only for non-obvious intent,
  tradeoffs, or constraints, and delete existing ones that just restate adjacent code
  (e.g. `// totalTokens = input + output` next to that exact expression).
- In comments and docs, **prefer concision over grammar** — drop articles and filler,
  trim to the load-bearing point.

---

## Testing

### Philosophy

- Follow the **testing trophy** model: invest most effort in **integration tests**,
  then unit tests for complex logic, with minimal reliance on end-to-end and static
  analysis as a baseline.
- **Test behavior, not implementation.** Tests should verify what the code does from
  the perspective of its consumers, not how it does it internally.
- Prefer **few, well-structured tests** over many shallow ones. Each test should
  carry its weight.
- **Always cover edge cases and error paths.** Happy-path-only coverage is
  insufficient.

### Mocking

- **Do not mock code within the same package/service boundary.** If a test needs to
  mock an internal dependency, that's a signal the design may need refactoring, not
  more mocks.
- **External boundaries are fine to mock:** third-party APIs, databases, file systems,
  network calls — anything outside the package under test.

### Tools & Structure

- **Vitest** over Jest unless the project mandates otherwise.

### File Placement

- Unit tests: colocated with source (e.g., `foo.test.ts` next to `foo.ts`).
- Integration tests: separate directory mirroring the source structure.

---

## Before Finishing

Before considering a task done or committing changes:

- **Lint and format** all changed files. Fix any warnings or errors introduced.
- **Update relevant documentation** (README, JSDoc, config references) if behavior,
  APIs, or configuration changed — but only where documentation already exists for
  the changed area.
- **Run affected tests** and ensure they pass.

---

## Git

- Commit message format is defined per-project. No personal default — follow
  whatever convention the repo uses.
- Commit and push **only when I explicitly ask for it**.
- **Confirm the target branch before committing** — for standalone work, branch off the
  repo's main branch; never reuse an unrelated feature branch.
- Don't use `git -C <path> <subcommand>` when already in the repo directory.
  Run `git <subcommand>` directly.
- **No test plan in PR descriptions** unless explicitly asked, or unless the
  project's conventions call for one — some repos want the manual-only steps
  included. Don't add a "Test plan" section or steps that CI already covers.
