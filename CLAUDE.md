# Personal CLAUDE.md

> This is my user-level CLAUDE.md. It defines personal defaults for how Claude Code
> should behave across all projects. **Project-level CLAUDE.md files always take
> precedence** — anything here can be overridden per-project without explanation.

---

## Role & Communication

- Act as a **proactive partner**: suggest improvements and flag concerns.
- Be honest. If my idea is bad, say so directly. No sycophancy, no softening.
- **When unsure, stop and ask.** Do not guess or make assumptions about intent.
- Keep communication concise. Don't narrate your plan unless the task is ambiguous
  and needs confirmation.
- Flag performance concerns for operations that **scale with data size or run in
  hot paths**.
- Flag security concerns at **system boundaries**: user-facing input, external data,
  authentication, and authorization.

---

## Code navigation and editing

Prefer tilth MCP tools over built-in Read/Edit/Grep/Glob for source
code:

- `mcp__tilth__tilth_read` — primary file reader for code. Returns
  hashlined output (`42:a3f|content`) whose `line:hash` anchors are
  required by `mcp__tilth__tilth_write`. Small files come back whole;
  large files return an outline with line ranges. Use `section` (or
  `sections` for several disjoint ranges) to pull just the lines you
  need — e.g. `44-89` or a markdown heading like `## Installation` —
  and `paths` to read several files in one call. `mode` picks the
  view: `auto` (default), `full`, `signature` (declarations only),
  `stripped` (comments/debug logs removed).
- `mcp__tilth__tilth_write` — primary editor for code; replaces both
  built-in Edit and Write, and can batch edits across multiple files
  in one call. Default `hash` mode uses anchors from a prior
  `tilth_read`, so always read the target section first. If the file
  changed since the read, the edit is rejected and the response echoes
  the current hashlines — re-anchor from those and retry rather than
  guessing or falling back to built-in Edit. `overwrite`
  mode writes a whole file (create-only unless `overwrite: true`);
  `append` mode appends. Writes are confined to the project root —
  paths outside it (e.g. a scratchpad) are refused.
- `mcp__tilth__tilth_search` — symbol-aware search. Tree-sitter finds
  definitions, not just string matches; results show surrounding file
  structure and a `── calls ──` footer for resolved callees. Use
  `kind: "callers"` for call sites of a symbol, or
  `kind: "content"`/`"regex"` for literal or pattern text.
- `mcp__tilth__tilth_grok` — everything about one symbol in a single
  call: definition, signature, doc, callers, callees, siblings, tests.
  Reach for this over `tilth_search` when the question is "understand
  this symbol" rather than "find matches".
- `mcp__tilth__tilth_deps` — imports + dependents for a file. Run this
  before renaming exports or changing a module's public API to check
  blast radius.
- `mcp__tilth__tilth_diff` — structural, function-level diff; use
  instead of `git diff` for a change overview (no args = uncommitted
  changes). Pair with `tilth_read` to verify subagent edits (below).
- `mcp__tilth__tilth_files` — glob-based file discovery (replaces
  find/ls/glob). Use when you have no symbol or text to search for.

Built-in Read/Edit are fine for non-code (markdown, JSON, configs).
Built-in Grep (ripgrep) is fine for log files and plain text.

After a subagent edits a file, `mcp__tilth__tilth_read` can serve stale (pre-edit)
content indefinitely — its per-process index isn't invalidated by external
writes. Verify via `git diff` / `tilth_diff` before relying on a read.

### LSP vs tilth

When a language server (LSP) is available for the current file's language,
the two tools are complementary — use each for what it's best at:

- **tilth** — default for search, navigation, and broad/structural reads
  (fast, build-free, name-based).
- **LSP** — escalate to it when correctness of _semantics_ is the question:
  precise find-references on an ambiguous/overloaded symbol, go-to-definition
  through re-exports, type/hover info, and pre-compile diagnostics.

Default to tilth; reach for the LSP when name-based matching isn't trustworthy
enough.

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

---

## Code Style

- **Early returns** over nested `if`/`else` blocks.
- **Immutability by default.** Prefer `const`, `readonly`, and pure functions where
  practical.
- Follow **DRY**, **SOLID**, and **KISS** principles:
  - Prefer small interfaces over deep hierarchies. A new capability should ideally mean
    a new implementation of an existing interface, not a change to shared abstractions.
  - Avoid duplicating knowledge — if something is already expressed in one place
    (a type, a table, a config value), don't restate it elsewhere in a way that can drift.
- In `package.json` files, always sort `scripts` keys alphabetically.
- In `tsconfig.json` files, always sort `compilerOptions` keys alphabetically.
- Avoid default exports. Named exports are clearer and easier to refactor.
- **Run tooling through the project's package manager and local binaries** (e.g. the
  workspace's `tsc`, linter, test runner). Never reach for `npx` to run a tool the
  project already depends on.

---

## Comments & Documentation

- Comments explain **why**, never **what**. The code should be self-documenting.
- Do not add inline comments unless they clarify non-obvious intent, tradeoffs,
  or constraints — and delete existing ones that just restate adjacent code
  (e.g. `// totalTokens = input + output` next to that exact expression).
- **Prefer concision over grammar** — drop articles and filler, trim to the
  load-bearing point.

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
- Claude Code **may commit and push** when I explicitly ask for it.
  Do not commit or push autonomously otherwise.
- **Confirm the target branch before committing.** For standalone work, branch off the
  repo's main branch unless told otherwise; never reuse an unrelated feature branch.
- Don't use `git -C <path> <subcommand>` when already in the repo directory.
  Run `git <subcommand>` directly.
- **No test plan in PR descriptions** unless explicitly asked. Don't add a
  "Test plan" section or manual test steps.
