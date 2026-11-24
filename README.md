# Skills

Agent skills for Claude Code and pi. Each folder is one skill (`<name>/SKILL.md`).
The agents load them through symlinks to this repo, so edits here take effect
immediately.

| Skill | Claude Code (`~/.claude/skills`) | pi (`~/.pi/agent/skills`) |
|---|---|---|
| `code-review` | — (Claude Code has a built-in `/code-review`) | ✓ |
| `deep-codebase-review` | ✓ | ✓ |
| `incremental-review` | — | ✓ |
| `multi-model-brainstorm` | ✓ | ✓ |
| `multi-model-code-review` | ✓ | ✓ |
| `multi-model-design-review` | ✓ | ✓ |

The `multi-model-*` skills get a second opinion from a different model, run as
a separate pi session, from either agent. They run it through `shared/run-pi.sh` (linked into
each of them), which holds the peer's sandbox: file tools only, no shell,
extensions, skills or MCP.

Link a skill into an agent:

```bash
ln -s "$PWD/<skill>" ~/.claude/skills/<skill>     # Claude Code
ln -s "$PWD/<skill>" ~/.pi/agent/skills/<skill>   # pi
```
