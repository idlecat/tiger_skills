---
name: deep-codebase-review
description: Perform a deep, whole-repository engineering review covering bugs, readability, reusability, testability, test coverage, performance, and best practices — and derive standing rules from the project's own bug-fix history to prevent repeat bugs. Use when asked to "review the whole codebase", "review everything carefully", "audit the codebase", or "how do we avoid bugs like the ones we fixed".
---

# Deep Codebase Review

A whole-repo review, not a diff review. The goal is twofold:

1. A prioritized findings report (bugs, maintainability, tests, performance, practices).
2. A set of **standing rules** derived from the project's *past fixed bugs* so the same
   class of bug doesn't come back.

## Workflow

### 1. Scope and inventory

- Confirm scope is the whole repo (ask if unclear).
- Inventory: file tree, line counts per file (`wc -l`, sorted), test files, CI config,
  config/data files.
- Read the project's own docs (`CLAUDE.md`, `README`, `docs/`) first — they encode the
  project's principles (e.g. "configuration over hardcoding"). Judge code against
  *those* principles, not generic ones.

### 2. Run the test suite and checks first

- Run the full test suite and any lint/compile/startup checks the project documents.
- Note failures, warnings, and **leak/resource warnings** — these are findings too.
- Find out how the runtime reports errors before trusting "all passed". In some engines
  (e.g. Godot/GDScript) a script error prints and the function just stops — the suite
  keeps going and still exits 0. Grep the test output for the error markers
  (`SCRIPT ERROR`, `Traceback`, `panic`, ...); errors in a passing run are findings, and a
  suite that can't fail on them is a test-infrastructure finding (fix: hook the logger and
  count errors, or fail CI on the marker).
- If tests pass, say so in the report; it calibrates severity of what follows.

### 3. Mine the bug-fix history

- `git log --oneline` (50+ commits) and read the messages of bug-fix commits.
- Group past fixes into **bug classes** (e.g. "bad config failed silently",
  "check-then-pay drift", "logic compared display text", "per-tick full scans",
  "private cross-module calls").
- Each class becomes a candidate *enforcement rule* (see step 7). This is what makes
  the review specific to this repo instead of generic advice.

### 4. Read the core files in full

- Read the largest/most central modules completely (in a big codebase, prioritize by
  a mix of size and centrality: the sim core, the equivalent of controllers/executors,
  data schemas, save/load, and the trust boundaries).
- Skim peripheral files (UI, art, generated) unless a finding points there.
- Read the test file(s) enough to know **what is covered and what isn't** — coverage
  gaps are findings.

### 5. Check systematically, adapted to the project's architecture

General categories (from the base review discipline):

1. **Correctness**: off-by-one, inverted conditions, copy-paste, stale assumptions,
   broken invariants that hold only by coincidence (e.g. "this is safe today because
   no config entry uses that key" — flag it).
2. **Trust boundaries**: any input from outside (LLM output, user data files, saves,
   network) — is it validated/clamped/whitelisted at the boundary?
3. **Performance**: allocations and quadratic scans in per-tick/per-frame paths,
   full-collection loops where an index exists, unbounded growth.
4. **State & consistency**: duplicated representations of one fact (display text vs
   logic field, two literals that must stay coupled), caches and their invalidation.
5. **Error handling**: silently swallowed failures (especially config/data parse
   errors), ignored return values.
6. **Tests**: missing tests for new behavior, tests that could scan the source to
   *enforce* rules (grep-based tests are cheap and effective), fuzz tests for
   boundary parsers.
7. **Readability/reuse**: fused/stale comments, dead code, magic numbers that violate
   the project's own "configuration over hardcoding" principle.

Project-specific heuristics for game/sim codebases like this one:

- Coupled time windows / thresholds written as literals in multiple files.
- Prices/costs paid through different code paths (central `spend()` vs direct mutation).
- Comments that state rules ("X is consumed by Y") — rules in comments belong in data.
- Entity field cleanup on death/removal (stale flags, cached indices).
- Save/load round-trip fidelity for exotic values (INF, empty containers, cycles).

### 6. Verify before claiming

- Trace suspected bugs through actual call paths; cite `file:line`.
- **Check reachability before claiming a crash.** "Missing key X crashes Y" is only a bug
  if malformed data can actually reach Y: follow the data from its entry point (loader,
  validator, sanitizer, defaults filled in on load) to the use site. If a loader already
  fills defaults or a validator rejects it, it is not a finding (at most a note that the
  use site relies on that loader).
- Distinguish **confirmed bugs** from **latent invariants** (safe now, breakable later)
  and from **suspensions of the project's own stated principles**.
- Prefer short, targeted runs over guesses when a finding hinges on behaviour or size:
  a minimal repro script for a suspected bug (and the same script against the code
  before the fix, to show it fails there), a micro-benchmark before calling something a
  hot path (measure what actually dominates — an obvious full scan may not be the cost),
  an object/memory count across repeated runs before rating a leak. Keep them in a scratch
  location, bounded by a timeout, and delete them afterwards; don't start servers or
  long-lived processes. Report the measured numbers with the finding.

### 7. Report format

```markdown
# Code Review: whole codebase (<project>)

### Summary
2–4 sentences: overall health, test status, headline risks.

### Findings
#### N. [High|Medium|Low] <title> — `file:line`
- Problem / Impact / Fix (+ Evidence for confirmed bugs)

### Positives
Short, concrete — what to keep doing.

### Avoiding the bugs already fixed — practices to enforce
A table: past bug (from git history) → bug class → enforcement
(rule, test, invariant, or scan). Each rule must be actionable, ideally
automatable as a test or invariant check.

### Suggested next steps
Ordered, small first.
```

Severity: High = likely production bug/data loss; Medium = real problem under
certain conditions or latent invariant; Low = polish/maintainability.

### 8. Review-only unless asked

Do not modify code unless explicitly asked to apply fixes. If asked, list every
change made.

## Guidelines

- Judge against the project's documented conventions first; an odd pattern that
  matches the codebase's established style is usually not a finding.
- Prefer findings that are *specific to this repo* (invariant drift, boundary gaps,
  history-derived classes) over generic advice.
- Every finding cites `file:line`; every enforcement rule says how it would be
  checked automatically.
- Be honest about confidence; say when tests pass and no high-severity bug was found.
