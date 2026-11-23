---
name: zcc-review
description: Get a read-only second-opinion code review of the current diff from the GLM model behind the z.ai-backed z_cc wrapper (~/rclone/bin/z_cc), then apply any fixes yourself in this session. Use when the user asks to run "z_cc", "zcc", or wants a GLM second opinion on a change — without granting that session write/shell access to the repo.
---

`~/rclone/bin/z_cc` normally launches `claude --dangerously-skip-permissions`
against a third-party endpoint (`api.z.ai`) using a plaintext API token. That
combination — a non-Anthropic backend plus every permission check disabled —
means that session could edit files or run shell commands with zero
confirmation. This skill gets the "second opinion from a different model"
value without that blast radius: it reuses the wrapper's environment (token,
base URL, model overrides, isolated `CLAUDE_CONFIG_DIR`) but calls `claude`
itself in non-interactive `-p` mode, limited to read tools and read-only `git`
commands by `--setting-sources ""`, `--tools`, `--permission-mode dontAsk` and `--strict-mcp-config`
(an allowlist alone is not enough; see step 3). It never edits or runs commands — only text
review comments come back, and applying fixes stays with you, under normal
permission prompts.

**Never add `--dangerously-skip-permissions` or `--permission-mode
bypassPermissions` to the invocation below.** That defeats the entire point
of this skill.

## Steps

1. Determine what to review: `git status --short` plus `git diff` for
   tracked changes. List any **untracked new files** by path explicitly —
   plain `git diff` doesn't show their content, so the prompt must name
   them and ask the reviewer to `Read` them directly.

2. Build a review prompt: one or two sentences of context on what the
   change does (from the current conversation, or ask the user if this
   skill is invoked cold), the repo root, the list of modified files, and
   the list of new files. Ask for correctness bugs and high-confidence
   simplification/reuse issues — the same bar as this project's
   `/code-review` skill, not a style nitpick pass. Tell it that its working
   directory is the repo root, that it should run plain `git show` / `git diff`
   / `git log` (the allow rules are prefix matches, so `git -C <path> show` is
   refused and the reviewer may conclude git is unavailable), and that it has
   read-only tools only, so it should reason from the source rather than try
   to run code.

3. Invoke it, sourcing the wrapper's exported env vars live rather than
   copying the token into this file — that way a rotated credential just
   works, and the secret has exactly one on-disk copy. Capture the input
   prompt and the returned text to a per-run log file, since traffic here
   goes to a third-party endpoint and a local record of exactly what was
   sent/received is worth keeping.

   **Stream to a file; never wrap the call in `$( )`.** A real review of a
   non-trivial diff runs 15-25 minutes, which is past the foreground Bash
   timeout, so this must go in the background — and command substitution
   makes the run un-peekable while it does. `claude -p` writes only to its
   stdout pipe, so under `RESPONSE=$(claude -p ...)` the child's fd 1 is a
   pipe owned by the capturing shell: there is no file on disk, and reading
   that pipe steals bytes from the capture. If the run is then killed
   (timeout, Ctrl-C), the log block never executes and **the entire review is
   lost with nothing written**. Redirect to a file instead, and write the
   input half of the log up front so a record survives even a killed run:

   ```bash
   mkdir -p ~/.claude/zcc-review-logs
   STAMP=$(date -u +%Y%m%dT%H%M%SZ)
   LOG_FILE=~/.claude/zcc-review-logs/$STAMP.md
   RAW_FILE=~/.claude/zcc-review-logs/$STAMP.raw.jsonl

   {
     echo "# zcc-review $(date -u +%Y-%m-%dT%H:%M:%SZ)"
     echo
     echo "**Repo:** $(pwd)"
     echo "**Raw stream:** $RAW_FILE"
     echo
     echo "## Input"
     echo '```'
     echo "$REVIEW_PROMPT"
     echo '```'
   } > "$LOG_FILE"

   eval "$(grep '^export ' ~/rclone/bin/z_cc)"
   claude -p "$REVIEW_PROMPT" \
     --setting-sources "" \
     --tools "Read,Grep,Glob,Bash" \
     --permission-mode dontAsk \
     --strict-mcp-config \
     --allowedTools "Read Grep Glob Bash(git diff:*) Bash(git status:*) Bash(git log:*) Bash(git show:*)" \
     --output-format stream-json --verbose \
     < /dev/null > "$RAW_FILE" 2>&1

   {
     echo
     echo "## Output"
     echo '```'
     grep '^{' "$RAW_FILE" | jq -r 'select(.type=="result") | .result'
     echo '```'
   } >> "$LOG_FILE"
   ```

   **All four restriction flags are required.** `--allowedTools` alone only
   *pre-approves* the listed tools; it does not block anything else. The
   wrapper's `CLAUDE_CONFIG_DIR` (`~/.zai_cc`) starts sessions in `auto`
   permission mode, so without the flags every other tool goes to the
   auto-mode classifier, which approved them: on 2026-10-12 a review run
   wrote scripts to /tmp, tried to start a web server and ran Playwright
   Even earlier runs in `default` mode ran
   `./gradlew` tests, `npx tsc`, `gh api` and sub-agents. Allow rules in the
   reviewed project's own `.claude/settings*.json` also apply to this
   session; for example, a project that allows `Bash(node -e:*)` lets the
   reviewer run arbitrary code. What each flag does:
   - `--setting-sources ""` loads no user, project or local settings files,
     so the only allow rules are the ones on this command line. Verified on
     2026-10-12 in a project that allows `node -e`: `node -e` with a file write was
     refused, `git log` ran, and z.ai auth (env vars) is unaffected.
   - `--tools` removes Write, Edit, NotebookEdit, Task, WebFetch etc. from
     the session entirely.
   - `--permission-mode dontAsk` refuses any tool call not in `--allowedTools`
     instead of asking a classifier. Claude Code still auto-allows its
     built-in read-only commands such as `ls`. Verified: `touch` and
     `printf > file` were refused.
   - `--strict-mcp-config` loads no MCP servers. The wrapper config has the
     cmux-cua desktop-control tools.

   `< /dev/null` stops `claude -p` from waiting 3s for stdin and printing a
   warning into the stream; `grep '^{'` keeps any non-JSON line out of `jq`.

   After launching, confirm the restrictions took effect from the stream's
   init event; the expected output is `mode=dontAsk tools=Read,Grep,Glob,Bash`
   in some order:

   ```bash
   grep '^{' "$RAW_FILE" | jq -r 'select(.subtype=="init") | "mode=\(.permissionMode) tools=\(.tools|join(","))"'
   ```

   If the mode isn't `dontAsk` or other tools are listed, stop the run.

   Run that block from the repo root, with `run_in_background: true`.
   `stream-json` (which requires `--verbose`) emits one NDJSON event per
   step as it happens, so the run is peekable mid-flight — unlike
   `--output-format text`, which emits nothing until the very end.

   To peek at a run in progress, render the raw stream:

   ```bash
   jq -r 'select(.type=="assistant") | .message.content[]?
          | if .type=="tool_use" then "→ \(.name) \(.input.file_path // .input.pattern // .input.command // "")"
            elif .type=="text" then .text
            else empty end' "$RAW_FILE" | tail -40
   ```

   Peek when the user asks, or to confirm the run is making progress rather
   than hung. Do not treat a partial stream as the review — findings are only
   final once the `result` event lands.

   If `~/rclone/bin/z_cc` no longer exists, or its export lines change shape
   (e.g. the token variable is renamed), stop and tell the user rather than
   guessing. Use the captured `result` text (not a fresh invocation) for
   step 4 below.

   Before reading any log file, check it is **this** run's — match `$STAMP`,
   or check the header timestamp and that the content discusses the current
   diff. The logs directory accumulates previous reviews, and an older one
   can look plausible enough to report by mistake.

4. Read the returned review text. Treat every finding the way you'd treat
   a human reviewer's comment — verify it against the actual code before
   acting, since it's a different, generally less capable model and can be
   wrong or hallucinate a file/line. Apply real fixes yourself with the
   normal Edit tool, under normal permission prompts. The GLM session's
   output is advisory text only — never let it drive an edit or command
   directly.

5. Tell the user what GLM flagged, what you fixed, and what you skipped
   and why.
