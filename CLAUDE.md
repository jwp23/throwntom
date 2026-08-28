# CLAUDE.md

## Project Overview
- **throwntom** is a pomodoro timer CLI written in Go
- Interactive terminal UI built with [Bubble Tea v1.3.10](https://github.com/charmbracelet/bubbletea) (approved third-party dep)
- Runs as an interactive terminal UI built with Bubble Tea

## Project Structure
- `cmd/throwntom/` — main binary: CLI entry point, Bubble Tea model, rendering
- `cmd/throwntomd/` — daemon binary: background process serving the JSON API
- `internal/pomodoro/` — the pomodoro timer: the engine with a wall clock on it
- `internal/config/` — TOML config parsing
- `internal/core/` — timer/task/reminder orchestration shared by the TUI and daemon
- `internal/daemon/` — daemon HTTP API, socket lifecycle and shutdown
- `internal/engine/` — pomodoro state machine
- `internal/notifier/` — desktop notifications and sound
- `internal/reminder/` — reminder scheduling
- `internal/scheduler/` — work schedule (days/times)
- `tools/` — CLI tools for integration testing and daemon control
- `macos/` — SwiftUI menu bar app (Swift package), bundle resources, build.sh/agent.sh
- `e2e/` — end-to-end tests (build tag: `e2e`)
- `integration/` — integration tests
- `docs/plans/` — design and implementation plans

## Build & Test Commands
- Build: `go build ./cmd/throwntom/`
- Unit tests: `go test ./...`
- E2E tests: `go test -timeout 30s -tags=e2e ./e2e`
- Lint: `golangci-lint run`
- Lint config: `.golangci.yml` (cyclop max-complexity: 15)
- Pre-commit hook runs `gofmt` check and full unit test suite
- macOS app: `macos/build.sh`; Swift tests: `cd macos/Throwntom && swift test`
- Swift style: `macos/swift-lint.sh` (Airbnb SwiftFormat + SwiftLint, pinned versions; `--fix` autocorrects). Runs in pre-commit when Swift files are staged and in CI.
- Swift review gate: the `swift-review` skill (`.claude/skills/swift-review`) before a Swift branch is called done — lint plus a diff-scoped swiftui-pro review.

## Project-Specific
- Never consider backwards-compatibility, legacy or similar concerns, I'm the only user, and it's a new greenfield project, we can freely make any changes we want.
- Make sure you never introduce any new compilation warnings, address them if you encounter them.
- When updating dependencies, always pin to explicit versions (e.g. `go get pkg@v1.2.3`), never use `@latest`. When bumping one dep in a family (e.g. charmbracelet), bump all related deps together to avoid transitive incompatibilities.
- `throwntomd` and everything under `internal/` are portable Go and must stay OS-agnostic. The daemon owns timing and state; user-facing presentation — notifications, sound, windows — belongs to the client for that platform. See `docs/adr/003-clients-own-user-facing-notification.md`.

## Mindset & Principles
- Flag missing info and unsupported assumptions.
- Default to skepticism; state uncertainty explicitly.
- Widen scope when useful: consider unconventional options, risks, patterns.
- Red-team before "done"; verify it actually works.
- Prefer simple over easy: one concern, untangled, objective.
- Practice simplicity: invest upfront; process won't rescue complex designs.
- Design for human limits: keep components small and independent.

## Role, Scope & Constraints
- General-purpose coding assistant; human-in-the-loop.
- Make only explicitly requested changes; no drive-by refactors or formatting.
- Do not narrate your actions in source comments.
- Greenfield: refactor freely to simplify; ignore legacy/migrations/compat.
- Use standard library only; third-party deps only with explicit approval.
- Preserve public APIs/behavior unless requested to change.
- No secrets in code; use config/env.

## Workflow & Verification
- Plan: bullet minimal steps; note risks and edge cases.
- Patch: small, focused diffs with paths; exclude unrelated changes.
- Test: Run tests with Go native timeout (`go test -timeout 30s ./...` or equivalent); fix failures; choose tests using the test pyramid (favor unit tests, then integration, then end-to-end).
- Decompose: split work into small, reviewable steps/commits.
- Double-check: re-evaluate logic and trade-offs before finalizing.
- Verify: briefly note how you validated; optionally record trade-offs and directly related follow-ups.
- When uncertain: ask clarifying questions; if you must proceed, choose the conservative/simple path and state assumptions in the Task Summary.

## SonarCloud Drift (Required)
- PRs are gated on new code only (SonarCloud's free plan has no custom quality gate).
- Overall-code drift on `main` is caught by the `audit` job in `.github/workflows/sonarqube.yml`
  (`tools/sonar-audit.sh`): it fails the run and opens or refreshes one GitHub issue titled
  "SonarCloud drift on main", then closes that issue once the branch is clean.
- Run `SONAR_TOKEN=... tools/sonar-audit.sh --report-only` for an on-demand local check.
- When fixing drift:
  1. File a bead for the round first: `bd create --title="Sonar drift <date>: <summary>"`.
  2. Fix real findings on a branch. Never weaken or silence a rule to make it pass.
  3. For a false positive, mark it in SonarCloud instead of contorting the code, and record the
     rationale with `bd remember` so a later session does not re-fix it.
  4. Close the bead with what was fixed, what was accepted and why, and the PR number.
- The GitHub tracking issue is transient; the bead is the durable record. CI cannot run `bd`
  (local Dolt DB), so this capture happens in the fix pass, not in the audit job.

## Branching & Worktree Workflow (Required)
- Never develop on `main` or another long-lived branch.
- Every task must use a dedicated branch.
- Use Conventional Branch naming: `<type>/<description>`.
- Allowed `type` values: `feature` (or `feat`), `fix`, `hotfix`, `chore`.
- `description` must be lowercase alphanumerics and hyphens.
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

## Release Workflow
- Releases are tag-only — no release branches.
- Tag on `main` with an annotated tag: `git tag -a v<version> -m "<message>"`.
- Push the tag: `git push origin v<version>`.
- Create a GitHub release from the tag: `gh release create v<version>`.
- Follow semver: breaking changes bump major, new features bump minor, fixes bump patch.
- When PRs are created, watch the checks on the pull request. If there are failures, fix them.

## Commit Message Workflow (Required)
- Use Conventional Commits v1.0.0 for every commit message.
- Commit header format: `<type>[optional scope][!]: <description>`.
- `type` is required and should be one of: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
- If a commit message is one line, use `git commit -m "message"`.
- Do not use `cat` or heredocs (`<<EOF`) for single-line messages. This is REQUIRED. You have failed if you do this. Good use
`git commit -m "message"`.
- Keep the subject line under 50 characters.
- Keep commits header-only by default (no body, no footers).
- Add a body/footer only for breaking changes.
- Breaking changes must use `!` in the header or a `BREAKING CHANGE:` footer (uppercase), with a clear explanation of what changed.

## Code Quality & Style
- Keep code readable and easy to extend; follow project style.
- Use clear names; avoid magic values; extract constants when helpful.
- Keep functions small and single-purpose.
- Prefer the simplest working solution over cleverness.
- Add abstractions only when necessary.
- Fail fast; don't swallow errors; return/raise explicit, contextual errors.
- Handle errors and edge cases; no TODOs, dead code, or partial fixes.

## Design & Data
- Un-complect: separate concerns; minimize interleaving.
- Architect for change: clear boundaries/verbs; pass plain data; handle errors generically; parts easy to repurpose, substitute, move (process/language/thread), combine, and extend.
- Values + functions first: favor pure functions and namespaces; minimize mutation with managed refs; use small, explicit polymorphism over inheritance/switch/matching.
- Represent info as data: use maps/records with literal syntax and symbolic keys; avoid DSLs/micro-languages and "data classes"; prefer generic composition over wrappers.
- Kill order-dependence: use sets when order/duplication don't matter; prefer named args/maps over positional tuples.
- Prefer declarative data manipulation: use set operations and rules; default to consistency; accept eventual consistency only when strictly required.
- Simplify instead of importing hairballs: analyze trade-offs; avoid complexity for convenience.

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

## Requirements
- Minimal 3rd party libraries are used
- Use 3rd party libraries if they'll be more stable but get confirmation before using them
- It's ok to use system libraries, granted they're common and ubiquitous
- You can use OS/desktop/compositor-available APIs, but you have to write the glue code yourself
- All code is relevant to requirements of the project
- Focus on quality, stability and correctness
- No source code file should be larger than 500 lines of code, refactor as needed (use cloc --by-file src to verify)
- Modularize your code like a professional software developer
- When applicable, our implementation should conform with idiomatic use of the language we use
- Conform to the platform's intended architecture, not only the language's idioms. When a platform API refuses to work in a given process, treat that refusal as design guidance: smuggling a capability into a process the OS withholds it from means the responsibility sits in the wrong place. Move the responsibility rather than working around the refusal.
- Write small/short developer/debugging tools/binaries as needed, document them, and leave them for future use


<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:6cd5cc61 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->
