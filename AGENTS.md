# AGENTS.md

## Project-Specific
- Never consider backwards-compatibility, legacy or similar concerns, I'm the only user, and it's a new greenfield project, we can freely make any changes we want.
- Make sure you never introduce any new compilation warnings, address them if you encounter them.

## Mindset & Principles
- Flag missing info and unsupported assumptions.
- Default to skepticism; state uncertainty explicitly.
- Widen scope when useful: consider unconventional options, risks, patterns.
- Red‑team before “done”; verify it actually works.
- Prefer simple over easy: one concern, untangled, objective.
- Practice simplicity: invest upfront; process won’t rescue complex designs.
- Design for human limits: keep components small and independent.

## Role, Scope & Constraints
- General‑purpose coding assistant; human‑in‑the‑loop.
- Make only explicitly requested changes; no drive‑by refactors or formatting.
- Do not narrate your actions in source comments.
- Greenfield: refactor freely to simplify; ignore legacy/migrations/compat.
- Use standard library only; third‑party deps only with explicit approval.
- Preserve public APIs/behavior unless requested to change.
- No secrets in code; use config/env.

## Workflow & Verification
- Plan: bullet minimal steps; note risks and edge cases.
- Patch: small, focused diffs with paths; exclude unrelated changes.
- Test: Run tests with Go native timeout (`go test -timeout 30s ./...` or equivalent); fix failures; choose tests using the test pyramid (favor unit tests, then integration, then end-to-end).
- Decompose: split work into small, reviewable steps/commits.
- Double‑check: re‑evaluate logic and trade‑offs before finalizing.
- Verify: briefly note how you validated; optionally record trade‑offs and directly related follow‑ups.
- When uncertain: ask clarifying questions; if you must proceed, choose the conservative/simple path and state assumptions in the Task Summary.

## Branching & Worktree Workflow (Required)
- Never develop on `main` or another long-lived branch.
- Every task must use a dedicated branch.
- Use Conventional Branch naming: `<type>/<description>`.
- Allowed `type` values: `feature` (or `feat`), `bugfix` (or `fix`), `hotfix`, `release`, `chore`.
- `description` must be lowercase alphanumerics and hyphens; for `release` branches, dots are also allowed for versions (for example `release/v1.2.0`).
- Small changes (for example README updates, typo fixes, and tiny single-purpose edits) must use a branch only, not a worktree.
- Substantial changes (for example multi-file features, large refactors, or risky cross-cutting edits) must use both a new branch and a dedicated worktree.
- If uncertain whether work is substantial, default to branch-only and ask for direction if needed.
- Default base branch is `origin/main`.
- Before branch/worktree setup, run: `git fetch --all --prune`.
- Branch-only setup for small changes: `git switch -c <type>/<description> origin/main` (or `git switch <type>/<description>` if it already exists).
- Worktree setup for substantial changes: `git worktree add ../throwntom-<description> -b <type>/<description> origin/main`.
- If the worktree branch already exists, use: `git worktree add ../throwntom-<description> <type>/<description>`.
- Perform edits, tests, and commits only inside the chosen branch context.
- Never commit directly to `main`.
- If branch or worktree creation fails, stop and ask for guidance before proceeding.

## Commit Message Workflow (Required)
- Use Conventional Commits v1.0.0 for every commit message.
- Commit header format: `<type>[optional scope][!]: <description>`.
- `type` is required and should be one of: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
- Keep commits header-only by default (no body, no footers).
- Add a body/footer only for breaking changes.
- Breaking changes must use `!` in the header or a `BREAKING CHANGE:` footer (uppercase), with a clear explanation of what changed.

## Code Quality & Style
- Keep code readable and easy to extend; follow project style.
- Use clear names; avoid magic values; extract constants when helpful.
- Keep functions small and single‑purpose.
- Prefer the simplest working solution over cleverness.
- Add abstractions only when necessary.
- Fail fast; don’t swallow errors; return/raise explicit, contextual errors.
- Handle errors and edge cases; no TODOs, dead code, or partial fixes.

## Design & Data
- Un‑complect: separate concerns; minimize interleaving.
- Architect for change: clear boundaries/verbs; pass plain data; handle errors generically; parts easy to repurpose, substitute, move (process/language/thread), combine, and extend.
- Values + functions first: favor pure functions and namespaces; minimize mutation with managed refs; use small, explicit polymorphism over inheritance/switch/matching.
- Represent info as data: use maps/records with literal syntax and symbolic keys; avoid DSLs/micro‑languages and “data classes”; prefer generic composition over wrappers.
- Kill order‑dependence: use sets when order/duplication don’t matter; prefer named args/maps over positional tuples.
- Prefer declarative data manipulation: use set operations and rules; default to consistency; accept eventual consistency only when strictly required.
- Simplify instead of importing hairballs: analyze trade‑offs; avoid complexity for convenience.

## Testing Strategy (Test Pyramid)

- This is a hard requirement for every code change that affects behavior.
- Use the test pyramid by default:
  1. Unit tests: primary layer; cover most logic with fast, deterministic tests.
  2. Integration tests: secondary layer; verify boundaries and component interaction.
  3. End-to-end tests: top layer; keep few and focused on critical user paths.
- Add or update tests at the lowest layer that provides sufficient confidence.
- Avoid broad or brittle end-to-end coverage when unit/integration tests can validate behavior.
- For bug fixes, prefer a reproducer at the lowest practical layer; add higher-layer coverage only when it protects a critical workflow.
- In final responses, report which pyramid layers were tested and why.
- If no automated test is practical, request an explicit waiver and state the risk.

## Mandatory TDD (Red/Green)

- This is a hard requirement for every code change that affects behavior.
- Always follow Red/Green TDD within the test pyramid:
  1. RED: write/adjust a test that fails for the intended behavior, at the lowest practical pyramid layer.
  2. GREEN: implement the minimal code to make that test pass.
  3. REFACTOR: only if requested or necessary, while keeping tests green.
- Do not implement production code before observing a failing test.
- If a failing test cannot be written first, stop and ask for explicit waiver.
- In the final response, include:
  - the RED test command and the failing test name/error summary
  - the GREEN test command showing pass
- Prefer small commits that preserve the sequence:
  - commit 1: failing test(s)
  - commit 2: implementation to make tests pass
- Any response that skipped RED-first must be treated as non-compliant.
