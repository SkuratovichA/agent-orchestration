# agent-orchestration

A Claude Code plugin: the rules a session follows when it spawns subagents or workflow stages, and the agent types those rules name.

## What is in it

| Path | What it is |
| --- | --- |
| `SKILL.md` | The `agent-orchestration` skill: model and effort per stage, budgets, staged verification, context economics |
| `skills/writing-briefs/` | The `agent-orchestration:writing-briefs` skill: the brief skeleton, per-model phrasing, how to treat a report |
| `references/worker-brief-block.md` | The hygiene block every spawned agent gets |
| `hooks/` | `SubagentStart` puts that block into each spawned agent's context, so no brief has to paste it. `PreToolUse` on Bash refuses once, in the main conversation only, a command whose text does not bound its output |
| `agents/` | The agent types below |

## Agents

| Agent type | Model, effort | For |
| --- | --- | --- |
| `agent-orchestration:reader` | haiku, high | every terminal command and every lookup; follows a lead over several steps and returns the answer or where it got stuck, never raw output |
| `agent-orchestration:builder-m` | sonnet, medium | the default implementer: a brief that leaves no design question open |
| `agent-orchestration:builder-l` | sonnet, xhigh | an implementation whose difficulty is in the design |
| `agent-orchestration:reviewer` | sonnet, xhigh | code review: correctness, reuse, tests, style; read-only |
| `agent-orchestration:reviewer-arch` | opus, high | architectural review, only on request or when the plan marks the change as architecture-level; read-only |

`builder-m` is the default implementer; the orchestrator picks `builder-l` only when the difficulty is in the design. A `model` or `effort` passed on the spawn call raises any type when the user asks for it. Opus is spawned only through `reviewer-arch` or when the user names it.

Builders navigate with the language server. `references/language-servers.tsv` lists the plugin, the binary and the install command per project marker file, and a SessionStart check (`hooks/lsp-check.sh`) names the one that is missing.

## Install

The plugin loads in place from a skills directory, as `agent-orchestration@skills-dir`:

```sh
git clone git@github.com:SkuratovichA/agent-orchestration.git ~/agent-orchestration
ln -s ~/agent-orchestration ~/.claude/skills/agent-orchestration
```

A new session then prints "The agent-orchestration plugin is active". For one session without installing anything: `claude --plugin-dir ~/agent-orchestration`.

Check the files after an edit:

```sh
claude plugin validate ~/agent-orchestration --strict
```

## What Claude Code does with a plugin agent

Checked against the Claude Code documentation on 2026-10-09 (version 2.1.296).

- An agent file may set `name`, `description`, `tools`, `disallowedTools`, `model`, `effort`, `maxTurns`, `skills`, `memory`, `isolation`, `background`, `color` and `omitClaudeMd`. `hooks`, `mcpServers` and `permissionMode` are ignored in an agent that a plugin ships. https://code.claude.com/docs/en/sub-agents
- `effort` takes `low`, `medium`, `high`, `xhigh` or `max` and overrides the session's effort; `model` takes `sonnet`, `opus`, `haiku`, `fable`, a full model id or `inherit`. A `model` or `effort` passed on the spawn call wins over the definition.
- A subagent starts with a fresh context: its own body as the system prompt, plus the whole CLAUDE.md hierarchy the main conversation loads. It does not see the parent conversation, the skills the parent invoked or the parent's auto memory. It inherits the built-in and MCP tools, narrowed by `tools` and `disallowedTools`.
- A subagent can call any skill through the Skill tool. `skills:` in its frontmatter goes further and injects the full text of the listed skills at startup. None of the agents here preload a skill, because which skill governs the work depends on the files, and the brief names it.
- A `CLAUDE.md` at the plugin root is not loaded as context. Rules that must reach an agent ship as a skill or through the `SubagentStart` hook, which is what `hooks/context.sh` does. https://code.claude.com/docs/en/plugins-reference
- A subagent can spawn subagents of its own, up to three layers below the main conversation; `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` changes the limit. The builders and reviewers use that for `reader` only, and `reader` has no Agent tool.
- Whether a plugin loaded from a skills directory exposes its `agents/` is not stated in the documentation. Confirm it in a new session: the Agent tool must list the five types above.
