#!/usr/bin/env bash
# One sandboxed pi turn for the multi-model-brainstorm / multi-model-design-review / multi-model-code-review
# skills, from either host (Claude Code or pi). The sandbox lives here only:
# file tools, no bash, no extensions/skills/prompt templates/MCP, and
# project-local pi files ignored. Never loosen it.
#
#   run-pi.sh run   --model M --tools ro|doc --prompt FILE --raw FILE
#                   [--session-dir DIR --session-id ID]
#                   Runs in the foreground; writes RAW (json stream) and
#                   RAW.exit. No session id = ephemeral (--no-session).
#   run-pi.sh start (same args)   Same, detached; returns at once (pi host).
#   run-pi.sh wait RAW [SECS]     Blocks up to SECS (default 480): exit 0 when
#                                 finished, 3 if still running, 4 if it died.
#   run-pi.sh progress RAW        Tools called so far (→ tool path/pattern).
#   run-pi.sh reply RAW           The reply text; exit 1 on error / no end.
#   run-pi.sh stop RAW            Kill a started run.
#
# ro  = read,ls,grep,find              (reviews)
# doc = read,ls,grep,find,edit,write   (turn-based doc skills; the caller
#       checks with git that only the doc changed)
set -u
cmd=${1:-}; [ $# -gt 0 ] && shift

case $cmd in
run|start)
  if [ "$cmd" = start ]; then
    raw=; for ((i=1; i<=$#; i++)); do [ "${!i}" = --raw ] && { j=$((i+1)); raw=${!j}; }; done
    [ -n "$raw" ] || { echo "need --raw FILE" >&2; exit 2; }
    rm -f "$raw.exit"
    nohup "$0" run "$@" >/dev/null 2>&1 &
    echo $! > "$raw.pid"; echo "started pid $! → $raw"; exit 0
  fi
  model= tools= prompt= raw= sdir= sid=
  while [ $# -gt 0 ]; do
    case $1 in
      --model) model=$2;; --tools) tools=$2;; --prompt) prompt=$2;; --raw) raw=$2;;
      --session-dir) sdir=$2;; --session-id) sid=$2;;
      *) echo "unknown arg: $1" >&2; exit 2;;
    esac; shift 2
  done
  [ -n "$model" ] && [ -f "$prompt" ] && [ -n "$raw" ] \
    || { echo "need --model, --prompt FILE (existing), --raw FILE" >&2; exit 2; }
  case $tools in
    ro)  t=read,ls,grep,find;;
    doc) t=read,ls,grep,find,edit,write;;
    *)   echo "--tools must be ro or doc" >&2; exit 2;;
  esac
  if [ -n "$sid" ]; then
    [ -n "$sdir" ] || { echo "--session-id needs --session-dir" >&2; exit 2; }
    sess=(--session-dir "$sdir" --session-id "$sid")
  else
    sess=(--no-session)
  fi
  rm -f "$raw.exit"
  pi -p --mode json "${sess[@]}" \
    --no-extensions --no-skills --no-prompt-templates --no-mcp --no-approve \
    --tools "$t" --exclude-tools 'bash,mcp__*' \
    --model "$model" \
    "$(cat "$prompt")" < /dev/null > "$raw" 2>&1
  rc=$?; echo $rc > "$raw.exit"; exit $rc;;

wait)
  raw=${1:?RAW}; max=${2:-480}; n=0
  while [ ! -e "$raw.exit" ]; do
    if [ -f "$raw.pid" ] && ! kill -0 "$(cat "$raw.pid")" 2>/dev/null; then
      sleep 1; [ -e "$raw.exit" ] && break
      echo "died without finishing"; exit 4
    fi
    [ $n -ge "$max" ] && { echo "still running"; exit 3; }
    sleep 10; n=$((n+10))
  done
  echo "finished, exit $(cat "$raw.exit")";;

progress)
  grep '^{' "${1:?RAW}" | jq -r 'select(.type=="tool_execution_start")
    | "→ \(.toolName) \(.args.path // .args.pattern // "")"';;

reply)
  raw=${1:?RAW}
  grep -q '"type":"agent_end"' "$raw" || { echo "no agent_end: the run did not finish" >&2; exit 1; }
  end=$(grep '^{' "$raw" | jq -c 'select(.type=="agent_end")' | tail -1)
  err=$(jq -r '.messages[-1].errorMessage // empty' <<<"$end")
  [ -z "$err" ] || { echo "ERROR: $err" >&2; exit 1; }
  jq -r '.messages[-1] | .content[]? | select(.type=="text") | .text' <<<"$end";;

stop)
  raw=${1:?RAW}; pid=$(cat "$raw.pid" 2>/dev/null) || { echo "no pid file"; exit 1; }
  pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null; echo "stopped $pid";;

*) sed -n '2,24p' "$0"; exit 2;;
esac
