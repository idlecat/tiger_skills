---
name: code-review
description: >-
  Perform a thorough, structured code review of changed files, commits, PRs, or
  the whole repository. Use when the user asks to "review", "review my changes",
  "review this PR/commit/diff", or "check for bugs" in code. Produces a
  prioritized findings report covering correctness, security, performance,
  concurrency, error handling, and code quality.
---

# Code Review

## When to use

Use this skill when the user asks to review code — whether it's the current
working tree, a specific commit/PR, a diff, or a set of files. Do not confuse
it with "explain the code" requests; this skill is about finding problems and
improving the code, not just summarizing it.

## Workflow

### 1. Determine review scope

Ask if not clear, otherwise infer from the request:

- **Working tree**: uncommitted changes (`git diff`, `git diff --cached`)
- **Commit / PR**: `git show <sha>`, or diff between two refs
- **Files**: review only the named files
- **Whole repo**: review the current state of the codebase

For git-based review, gather context first:

```bash
git status                 # what changed
git log --oneline -10      # recent history context
git diff HEAD              # all uncommitted changes
```

### 2. Read the code, not just the diff

- Read each changed file **in full** (not only hunks) so you understand
  surrounding functions, imports, and data flow.
- Trace the callers and callees of changed functions to catch integration
  breakage the diff alone won't reveal.
- For larger changes, read related files (schemas, configs, tests, docs).

### 3. Check for these problem categories

Go through changed code systematically:

1. **Correctness & logic**
   - Off-by-one errors, inverted conditions, wrong operators
   - Mismatched types, implicit conversions, null/undefined/None handling
   - Broken invariants, stale assumptions about inputs
   - Copy-paste bugs, hardcoded values that should be config

2. **Security**
   - Injection (SQL, command, XSS, path traversal, regex DoS)
   - Secrets hardcoded or logged
   - Unvalidated/untrusted input reaching dangerous sinks
   - Insecure auth/authorization checks, missing CSRF, weak crypto

3. **Performance & resource use**
   - N+1 queries, repeated work in loops, accidental O(n²)
   - Unbounded growth (caches, lists, connections)
   - Missing resource cleanup (open files, connections, subscriptions)
   - Synchronous blocking work in async/event-loop code

4. **Concurrency & state**
   - Race conditions, non-atomic check-then-act
   - Shared mutable state, missing locks
   - Thread/process safety, reentrancy

5. **Error handling**
   - Swallowed exceptions, bare `except`, ignored error return values
   - Missing validation of inputs / boundary conditions
   - Error messages that don't help debugging

6. **API & contract changes**
   - Breaking changes to function signatures, endpoints, or data formats
   - Callers not updated, docs out of sync

7. **Code quality & maintainability**
   - Dead code, duplicate logic, overly complex functions
   - Naming, readability, missing tests for new behavior
   - Style violations that differ from the project's established patterns

### 4. Verify before you claim

- If you suspect a bug, **trace the actual code path** and confirm with
  evidence (specific lines, values, control flow).
- If a fix is proposed, check it is correct — don't suggest a change that
  would break something else.
- If unsure about expected behavior, read the tests or ask the user.

### 5. Write the report

Output a structured review report:

```markdown
## Code Review: <scope>

### Summary
<2-4 sentences: overall health of the change, headline risks>

### Findings

#### 1. [High] <short title> — `<file>:<line>`
- **Problem**: ...
- **Impact**: ...
- **Fix**: ...
- **Evidence**: code path traced / tests / etc.

#### 2. [Medium] ...

#### 3. [Low] ...

### Positives
<What's done well — keep it short, concrete>

### Suggested next steps
<Optional: tests to add, follow-ups, things to double-check>
```

Prioritize by severity:

| Severity | Meaning |
|----------|---------|
| **High** | Bug, security issue, data loss, or crash likely in production |
| **Medium** | Real problem under certain conditions; likely to bite later |
| **Low** | Style, polish, minor maintainability |

## Guidelines

- **Be concrete**: cite `file:line` for every finding. Vague feedback ("this
  could be better") is not a review.
- **Be honest about confidence**: distinguish confirmed bugs from
  "worth checking" suspicions. Run/test code when feasible to confirm.
- **Be kind**: lead with the most important issues, acknowledge what's good,
  and phrase suggestions as suggestions, not demands.
- **Respect project conventions**: a pattern that looks odd but matches the
  codebase's established style is usually not worth flagging.
- **Don't fix silently**: if the user wants fixes applied, make the edits
  yourself, but clearly list what you changed. If asked only for review,
  do not modify code.
