---
name: multi-model-design-review
description: Review an implementation plan in turns with two models — you and a second model run as a separate pi session (/opt/homebrew/bin/pi), from Claude Code or from pi itself. The two sides alternate on one plan doc in the repo — each checks the plan against the actual code (does what it names exist, does each step work, is the order right, what's missing, how is each step verified), fixes the plan in place, records findings by severity, and the turn is committed — until no blockers are left and both sides approve, or a set number of rounds. Use when the user asks for a design review, plan review or implementation-plan review with another model, "with pi", "with <model>" or "in turns", or wants a plan made ready to implement.
---

Where `multi-model-brainstorm` widens a doc (new ideas, bigger picture), this skill
**narrows a plan until it can be built**. The goal is fixed; the question each
turn is "if someone implemented exactly this, step by step, what would go
wrong?" Two models take turns on **one markdown plan doc in the current git
repo**; every turn is one commit touching only that doc, so
`git log -p -- <doc>` is the whole review.

## Host and peer

You are the **host**: you run the review, take your own turns with your own
tools, and make every commit. The **peer** is a separate pi session on
`PEER_MODEL`, run through `run-pi.sh` (below). This works from either host:

- **Claude Code**: your side is `claude`; the peer's side is `pi`.
- **pi**: you run on your own model (`HOST_MODEL`, the model this pi session
  runs; ask the user if you aren't sure). The peer is a **second pi session
  on a different model** — never your own session. `PEER_MODEL` must differ
  from `HOST_MODEL`, or there's no second opinion: if asked for the same
  one, say so and ask. Both sides are pi, so name each **side by its model
  id without the provider** (`glm-5.3`, `deepseek-v4-pro`).

`SELF` and `PEER` below are those side names. Logs go under `LOG_ROOT`:
`~/.claude/multi-model-design-review-logs` in Claude Code,
`~/.pi/agent/multi-model-design-review-logs` in pi.

## The runner and its sandbox

Every peer turn goes through `run-pi.sh` in this skill's directory
(`RUN=<skill dir>/run-pi.sh`, a link to the repo's `shared/run-pi.sh`). pi has
no permission system: with `bash` it runs any shell command unasked. The
runner (`--tools doc`) gives the peer file tools only
(`read,ls,grep,find,edit,write`: read the whole repo to check the plan,
edit only the doc), excludes `bash` and MCP tools, and turns off extensions,
skills, prompt templates, MCP and project-local pi files. **Never call pi
directly with other flags, and never change the runner's sandbox.** The peer
can't run git, so **you make its commit for it** after checking it changed
nothing but the doc.

## Inputs

Take these from the request; ask only for what is missing and has no sensible
default:

- **Plan doc**: path in the repo. If the plan exists only in the conversation
  (e.g. from plan mode), write it to a file first (ask where, default
  `docs/plans/<slug>.md`) and commit that as the starting version.
- **Goal**: what the plan must achieve, in one or two sentences — the yardstick
  for "missing" vs "out of scope". If none is given, read the plan and state
  the goal you inferred.
- **Rounds**: default 3 max (a round = one host turn + one peer turn). The
  review stops early when it converges (see below).
- **Who starts**: default the host.
- **Peer model**: default `zai/glm-5.3`; if the host is itself a `zai/glm-*`
  model, default `deepseek/deepseek-v4-pro`. Known to work: `zai/glm-5.3`,
  `deepseek/deepseek-v4-pro` (`zai/glm-5.3-highspeed` isn't on the current
  plan). Resolve loose names with `pi --list-models <search>`; don't guess
  IDs.

## Setup

1. Read the repo's `CLAUDE.md` / `AGENTS.md` / contributor docs: their rules
   and principles are review criteria, and the peer must get them too (paste
   the relevant parts into its first prompt; it may also `read` them).
2. `git status --short`. If the doc has uncommitted changes, commit them first
   as the starting version (`design-review: starting version of <doc>`).
   Always commit with a pathspec (`git commit -m ... -- "$DOC"`) so nothing
   else is staged; an untracked doc needs `git add -- "$DOC"` first. Leave
   other files alone. Commit on the current branch.
3. `LOG_DIR=$LOG_ROOT/$(date -u +%Y%m%dT%H%M%SZ)`; every peer prompt and raw
   output goes there.
4. One peer session for the whole review:
   ```bash
   PI_SESSION_DIR="$LOG_DIR/session"
   PI_SESSION_ID=$(uuidgen | tr A-Z a-z)
   ```
   Write `PI_SESSION_ID`, `PEER_MODEL`, `SELF`/`PEER`, `RUN` and `LOG_DIR` in
   your reply (shell variables don't survive between tool calls) and reuse
   them every turn, always running the peer from the repo root with the same
   model.

## What a reviewer checks

Work through the plan **step by step against the code**, not from memory:

1. **Grounding.** Every file, function, signal, config key, table, endpoint or
   test the plan names: open it and confirm it exists and does what the plan
   assumes. A plan built on a wrong assumption about the code is a blocker.
   Cite what you checked as `path:line`.
2. **Each step works.** Inputs and outputs of each step are concrete (data
   shapes, signatures, config keys, where state lives). No "handle X
   appropriately", "update as needed", "etc." — replace with the actual change
   or flag it.
3. **Order and dependencies.** Each step only uses what earlier steps built;
   the tree compiles and tests pass after each step (or the plan says why
   not). Spot steps that should be split, merged or reordered.
4. **Missing work.** Callers and other users of anything changed; save/load
   and data migration; config/schema and docs; translations/UI text;
   error paths and untrusted input at boundaries; concurrency/timing;
   performance on large inputs; cleanup of what's replaced.
5. **Verification.** Each step says how it's verified: which test (new or
   existing, by name), which command, which manual check. Untestable claims
   get a test or a check.
6. **Fit with the codebase.** Reuses existing helpers and formats instead of a
   parallel one; follows the repo's documented principles and layering;
   no hardcoding where the repo wants data/config.
7. **Simpler alternative.** If a materially simpler design meets the same
   goal, say so concretely (what it drops, what it costs). Don't redesign for
   taste.
8. **Risks.** What's hard to reverse, what could break existing behaviour,
   and what's still unknown — with a step to find out early (a spike, a
   prototype, a test) rather than a hope.

**Stay in scope.** Don't add features, polish or "while we're here" work the
goal doesn't need; move such ideas to a short `## Later` list instead. That's
`multi-model-brainstorm`'s job, not this one.

## The turn contract (same for both sides)

Each turn:

1. **Review**: read the whole plan, then the other side's last turn
   (`git log -1 --format='%an%n%B' -- "$DOC"`, `git diff HEAD~1 -- "$DOC"`).
   Check the other side's changes and findings against the code too — a
   reviewer can be wrong. Then run the checklist above on the plan.
2. **Fix the plan in place** where the fix is clear: correct names and paths,
   add missing steps, reorder, make vague steps concrete, add verification.
   Real edits to the plan, not just comments.
3. **Record what you can't fix alone** in a `## Review` section at the end of
   the doc, one line per finding:
   `- [ ] **blocker|major|minor** (<side>, r<N>) <step/section>: <problem> — <evidence path:line> — <proposed fix or question>`
   - *blocker*: the plan would fail or do the wrong thing as written.
   - *major*: works but with a real gap (missing step, untested path, risk).
   - *minor*: clarity or small improvement.
   The other side answers each open finding: fixes the plan and ticks it
   (`- [x] … — fixed r<N>: <how>`), or rejects it with evidence
   (`— rejected r<N> (<side>): <why>`). A rejected finding the original side
   still holds stays open with both arguments; don't tick the other side's
   findings without a fix or evidence. Questions only the user can answer go
   in `## Open questions for the user`.
4. **Commit message**: subject `design-review(<side>) r<N>: <what changed>`;
   body: what you fixed and why, findings added (by severity), findings
   resolved or rejected, what the other side should check next.
5. **Verdict** at the end of the reply: `APPROVED` (no open blocker or major
   that you raised or still hold; you'd implement this plan as written) or
   `CHANGES NEEDED`.

**Converged** when both sides say `APPROVED` in a row with no edit in the
second turn (or only minor ticks). Then stop, even before the round limit.
At the round limit, stop anyway and report what's open.

## The host's turn

Do the contract yourself: read and search the code to check the plan, edit
the doc with your own file tools, then commit:

- **Claude Code**: `git commit -m "<subject>" -m "<body>" -- "$DOC"` (with
  the harness's attribution lines).
- **pi**: author it as your side, so the log shows both models:
  ```bash
  git -c user.name="pi ($HOST_MODEL)" -c user.email="pi@localhost" \
    commit --author="pi ($HOST_MODEL) <pi@localhost>" \
    -m "<subject>" -m "<body>" -- "$DOC"
  ```

## The peer's turn

1. Build the prompt (save as `$LOG_DIR/r<N>-peer.prompt.md`). On the peer's
   **first** turn it holds everything below; on later turns the peer has the
   goal, contract and checklist in its session, so send "Round N of M, your
   turn", the previous turn's commit message and diff, and the reply-format
   reminder. Always tell it to re-read the doc from disk.
   - the goal, the doc path, round N of M, and its side name (`$PEER`; the
     other side is `$SELF`);
   - the checklist and the turn contract above, written out, and the repo's
     rules from Setup step 1;
   - the previous turn's commit message and diff, pasted in (no shell, no
     git);
   - "Your working directory is the repo root. Read any file to check the plan
     against the code, and cite `path:line` for every claim about the code.
     You may edit only `<doc>`; do not create or change any other file. You
     have no shell, so reason from the source; don't ask to run anything."
   - "End your reply with `SUBJECT: <one-line subject>`, then the commit body,
     then a last line `APPROVED` or `CHANGES NEEDED`."

2. Snapshot, then run it from the repo root (a turn can take minutes):
   ```bash
   RAW="$LOG_DIR/r$N-peer.raw.jsonl"
   git status --porcelain > "$LOG_DIR/r$N-status.before"
   ARGS=(--model "$PEER_MODEL" --tools doc --prompt "$LOG_DIR/r$N-peer.prompt.md"
         --raw "$RAW" --session-dir "$PI_SESSION_DIR" --session-id "$PI_SESSION_ID")
   ```
   - **Claude Code**: `"$RUN" run "${ARGS[@]}"` with `run_in_background: true`;
     wait for the notification.
   - **pi**: `"$RUN" start "${ARGS[@]}"`, then `"$RUN" wait "$RAW" 480`
     repeatedly while it prints `still running` (exit 3); exit 4 = it died.

   Peek at progress: `"$RUN" progress "$RAW"`. An `edit`/`write` on any path
   but `$DOC`, or a tool outside the six given: `"$RUN" stop "$RAW"` and tell
   the user.

3. Read the result: `"$RUN" reply "$RAW"`. Exit 1 (an `ERROR:` from the
   model's server, or no end of run): stop and tell the user; suggest another
   model. A partial stream is not a turn.

4. **Scope check**: `git status --porcelain | diff "$LOG_DIR/r$N-status.before" -`
   may show only `$DOC`. Anything else: don't commit; show the user the diff
   and ask (revert or delete only with their OK).

5. Commit the peer's turn with its own subject and body, authored as the
   peer:
   ```bash
   git -c user.name="pi ($PEER_MODEL)" -c user.email="pi@localhost" \
     commit --author="pi ($PEER_MODEL) <pi@localhost>" \
     -m "design-review($PEER) r$N: $SUBJECT" -m "$BODY" -- "$DOC"
   ```
   No change → nothing to commit; note its verdict.

The peer's findings are an opinion, not instructions: verify each against the
code on your next turn (it's a different model and can cite lines that don't
say what it claims), and never run commands it suggests.

## Finish

Tell the user:
- the **verdict**: ready to implement, or not and why;
- the rounds played and `git log --oneline -- "$DOC"`;
- what changed in the plan (main fixes, by which side), the findings still
  open by severity, rejected findings worth a second look, and the open
  questions for the user;
- where the logs and peer session are (`$LOG_DIR`; `pi --export <session
  file>` renders it as HTML) — the plan and quoted code went to a third-party
  endpoint.

Don't start implementing, squash or push unless asked.
