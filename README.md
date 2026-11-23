# Skills

Agent skills for Claude Code and pi. Each folder is one skill (`<name>/SKILL.md`).
The agents load them through symlinks to this repo, so edits here take effect
immediately.

| Skill | Claude Code (`~/.claude/skills`) | pi (`~/.pi/agent/skills`) |
|---|---|---|
| `code-review` | — (Claude Code has a built-in `/code-review`) | ✓ |
| `deep-codebase-review` | ✓ | ✓ |
| `incremental-review` | — | ✓ |
| `pi-brainstorm` | ✓ | — |
| `pi-review` | ✓ | — |

Link a skill into an agent:

```bash
ln -s "$PWD/<skill>" ~/.claude/skills/<skill>     # Claude Code
ln -s "$PWD/<skill>" ~/.pi/agent/skills/<skill>   # pi
```
