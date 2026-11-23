---
name: incremental-review
description: >-
  Review a git repository incrementally: only the commits and changes since the
  last review, instead of re-reviewing everything. Tracks a per-branch baseline
  inside the repo (.git) so repeated "review since last time" runs stay cheap
  and focused. Use when asked to "review new changes", "review what changed
  since last review", "catch up on review", or to review a repo in batches.
---

# Incremental Review

Review only what changed since the last review run. State is stored per branch
in `.git/incremental-review/<safe-branch>.state` so it never pollutes the
working tree or needs a commit.

## When to use

- "Review the new commits since last time"
- "Review what I changed since your last review"
- First run on a repo (reviews from the first commit or a given base)
- Re-review of a branch after new work lands on it

Do **not** use for reviewing a specific PR/commit in isolation — that's the
plain `code-review` skill. This skill is about a *continuing* review history.

## Workflow

### 1. Establish scope

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD)
SAFE=$(echo "$BRANCH" | tr '/' '_')
STATE=".git/incremental-review/${SAFE}.state"
HEAD=$(git rev-parse HEAD)
BASE=""   # resolved below
```

- If `$STATE` exists: `BASE=$(cat "$STATE")`. Verify the baseline is still an
  ancestor of HEAD (`git merge-base --is-ancestor "$BASE" "$HEAD"`). If not
  (rebase/force-push), fall back to `git merge-base "$BASE" "$HEAD"` or ask the
  user which base to use, and say clearly that history was rewritten.
- If `$STATE` does not exist (first run): use the oldest reasonable base, e.g.
  `git rev-list --max-parents=0 HEAD` (root commit) for a full first review, or
  `origin/<branch>` / a tag / a commit the user names. Say which base was used.
- If the user names an explicit base this run, use it instead of the state file
  (but still update the state afterward).

Scope to review = commits in `git log --oneline BASE..HEAD` **plus** uncommitted
changes (`git diff`, `git diff --cached`) if present.

### 2. Review the delta

For each commit/changed area, follow the full review methodology of the
`code-review` skill (correctness, security, performance, concurrency, error
handling, API/contract changes, quality). Read changed files in full and trace
callers/callees.

Extra duties specific to incremental review:

- **Cross-commit effects**: a change may be correct alone but conflict with an
  earlier commit in the same batch — check the combined diff
  (`git diff BASE..HEAD`) for interactions, not just commit-by-commit diffs.
- **Previously reported issues**: check whether commits in this batch fixed or
  re-broke anything. If findings recur, call that out ("third occurrence of X
  pattern — consider a lint rule").
- **Baseline assumptions**: changes to files whose *old* code was reviewed last
  time only need review of the new hunks; changes to never-reviewed files need
  the surrounding context reviewed too.

### 3. Write the report

Same structured format as the `code-review` skill (Summary, prioritized
findings with `file:line`, Positives, Next steps), plus an increment header:

```markdown
## Incremental Review: <repo name>
**Base:** <short-sha> (<subject, abbreviated>) → **HEAD:** <short-sha>
**Scope:** N commits, M files changed (+A/−D)
```

### 4. Update the baseline

**Only after the report is delivered** (and only if the review ran to
completion, not on error or user interruption):

```bash
mkdir -p .git/incremental-review
echo "$HEAD" > "$STATE"
```

If uncommitted changes were reviewed but the user may keep working, say so and
leave the baseline at `HEAD`; they'll be re-reviewed as part of the next diff.
If the user asks to only review up to an earlier commit `<c>`, store `<c>`.

Never write the state file into the working tree (i.e. never create
`.git`-sibling files or commit it). Never store baselines outside the repo.

## Guidelines

- If the increment is huge (> ~40 commits or > ~5k diff lines), split into
  logical chunks (e.g. by merge or by `git log --reverse` batches), review
  chunk by chunk, and tell the user where you split. Consider suggesting a more
  frequent review cadence.
- List branches with state via `ls .git/incremental-review/` when the user asks
  "what's been reviewed". `--all`-style requests: review each branch separately
  with its own baseline.
- `incremental-review reset` (or the user asking to re-review from scratch):
  delete the state file and do a full review, establishing a new baseline.
- All the honesty, concreteness, and severity guidance of `code-review` applies
  unchanged.
