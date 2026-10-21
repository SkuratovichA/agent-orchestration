# agent-orchestration

A Claude Code plugin: the rules a session follows when it spawns subagents or workflow stages, and the agent types those rules name. It is a policy made of prompts and hooks. It decides which model does what, what a brief must contain and what a spawned agent may do; running the agents stays with Claude Code, and the plugin adds no task queue or locking of its own.

## Install

```sh
claude plugin marketplace add SkuratovichA/agent-orchestration
claude plugin install agent-orchestration@agent-orchestration
```

The same from inside a session: `/plugin marketplace add SkuratovichA/agent-orchestration`, then `/plugin install agent-orchestration@agent-orchestration`. A new session then starts with the line "The agent-orchestration plugin is active".

`jq` is optional. Without it the Bash-output check, the turn note and the language-server check stay silent; the skills, the agents and the worker block work the same.

## What is in it

| Path | What it is |
| --- | --- |
| `skills/agent-orchestration/` | The `agent-orchestration:agent-orchestration` skill: model and effort per stage, the agent roster, when a command runs directly and when it goes to a reader, several builders in one tree, staged verification, context economics |
| `skills/agent-orchestration/references/worker-brief-block.md` | The short block of rules a builder works under |
| `skills/agent-orchestration/references/` | Also the sections the skill points to when they are needed: language servers, several builders in one tree, staged verification and cheap swarms |
| `skills/writing-briefs/` | The `agent-orchestration:writing-briefs` skill: the brief skeleton, the blocks to paste, how to treat a report |
| `skills/writing-briefs/references/` | The brief templates and the Workflow-stage rules |
| `agents/` | The agent types below |
| `hooks/` | The hooks below, with a test file beside each script |
| `references/language-servers.tsv` | The language servers the SessionStart check knows about |

These are the plugin's defaults. A user's or a project's CLAUDE.md overrides them wherever the two differ.

## Agents

| Agent type | Model, effort | Fence | Tools | For |
| --- | --- | --- | --- | --- |
| `agent-orchestration:reader` | haiku, max | 60 | Bash, Read, Grep, Glob, LSP, Skill | reconnaissance: follows a lead over several steps and returns the answer or where it got stuck, never raw output |
| `agent-orchestration:builder-m` | sonnet, medium | 180 | all | the default implementer: a brief that leaves no design question open |
| `agent-orchestration:builder-l` | sonnet, xhigh | 250 | all | an implementation whose difficulty is in the design |
| `agent-orchestration:reviewer` | sonnet, xhigh | 120 | Read, Grep, Glob, LSP, Skill | code review: correctness, reuse, tests, style |
| `agent-orchestration:reviewer-arch` | opus, high | 120 | Read, Grep, Glob, LSP, Skill | architectural review, only on request or when the plan marks the change as architecture-level |

The fence is the agent's `maxTurns`: a runaway stop at about 3x the p99 of past runs, far above ordinary work, and no definition or brief states it. A run that hits it comes back marked partial and can be resumed. `builder-m` is the default implementer; the orchestrator picks `builder-l` only when the difficulty is in the design. A `model` or `effort` passed on the spawn call raises any type when the user asks for it. Opus is spawned only through `reviewer-arch` or when the user names it.

A builder runs its own tests, lint and type checks in its own shell with the log on disk, and sends a reader only on reconnaissance. A reviewer has no shell and no Agent tool, so it cannot change anything or start an agent that can: the orchestrator gives it the diff as a file. The reader and the reviewers also list `LSP`, `Skill` and `ToolSearch`, so they navigate with the language server and load the skills a brief names, and `StructuredOutput`, which a Workflow stage needs to return a schema result. They get no MCP tools: an allowlist can grant them only server by server, and most servers carry write tools.

Builders, reviewers and the reader navigate with the language server. `references/language-servers.tsv` lists the plugin, the binary and the install command per project marker file, and a SessionStart check names the one that is missing.

## Hooks

| Event | Script | What it does |
| --- | --- | --- |
| SessionStart | `hooks/context.sh` | adds one line that tells the session to load the skills before it spawns anything; after a compaction, says the skills it loaded are already re-attached |
| SessionStart, on startup | `hooks/lsp-check.sh` | names a language server the project needs and does not have; installs nothing |
| SessionStart, on startup | `hooks/window-check.sh` | names a compaction window below 200K tokens in the settings or the environment; changes nothing |
| SubagentStart, matcher `^agent-orchestration:builder-` | `hooks/context.sh` | puts the worker block into the context of the two builder types. The reader and the reviewers work from their own definitions; built-in agents such as Explore and Plan, and other plugins' agents, get nothing |
| PreToolUse on Bash | `hooks/bash-output.sh` | in the main conversation only, refuses once a command whose text does not bound its output; the same command sent again runs. A subagent's Bash is never refused |
| PostToolBatch | `hooks/turn-budget.sh` | inside a run of one of this plugin's agent types only, counts the tool rounds and, once, at 75% of that agent's `maxTurns` fence, adds a factual note: the count so far, where Claude Code stops the run, and that the parent can resume it. It reads the fence from the agent's frontmatter and orders nothing. Any other agent, and the main conversation, get nothing |
| SessionEnd | `hooks/cleanup.sh` | removes the markers the Bash check and the counters the turn note left for that session |

Every hook exits 0 whatever happens, so a broken hook never blocks a session. The Bash check and the turn note keep their markers and counters in the plugin's data directory, never in a shared temp directory.

## Several builders in one tree

Builders that run at the same time share the working tree, its git index, its ports and its database. The plugin offers three levels and enforces none of them.

- **File ownership in the brief** is the default: each brief lists the paths that builder may change, the lists do not overlap, and a builder never stages, commits, reverts or reformats a file outside its list.
- **A worktree per builder**, by passing `isolation: 'worktree'` on the spawn call, is for tasks whose paths really overlap. What it costs: the work comes back as a branch to merge; the worktree is cut from the default branch, so uncommitted work and work on the current branch are not in it; each worktree needs its own dependency install; and ports, databases and caches outside the tree are still shared.
- **Agent teams** are for work that spans sessions or needs builders to talk to each other. Claude Code provides the shared task list, task claiming and messaging (https://code.claude.com/docs/en/agent-teams); this plugin only says what a teammate's brief contains.

## Working on the plugin

```sh
git clone https://github.com/SkuratovichA/agent-orchestration.git
claude --plugin-dir ./agent-orchestration
```

Check the files after an edit:

```sh
cd agent-orchestration
for target in . .claude-plugin/plugin.json agents skills; do claude plugin validate "$target" --strict || break; done
for t in hooks/*.test.sh; do sh "$t" || break; done
```

Validating the directory checks the marketplace manifest only, which is why the plugin manifest, the agents and the skills are named one by one. CI runs the same two steps on every push. Bump `version` in `.claude-plugin/plugin.json` with every release: an installed copy stays on its version until that field changes.

## Reference

Nothing in this section is loaded into a session. It records where the rules came from and when each fact was last checked, so the prompts themselves carry no version numbers.

### What Claude Code does with a plugin agent

Checked against the Claude Code documentation on 2026-10-10 (version 2.1.296).

- An agent file may set `name`, `description`, `tools`, `disallowedTools`, `model`, `effort`, `maxTurns`, `skills`, `memory`, `isolation`, `background`, `color` and `omitClaudeMd`. `hooks`, `mcpServers` and `permissionMode` are ignored in an agent that a plugin ships. https://code.claude.com/docs/en/sub-agents
- `effort` takes `low`, `medium`, `high`, `xhigh` or `max` and overrides the session's effort; `model` takes `sonnet`, `opus`, `haiku`, `fable`, a full model id or `inherit`. A `model` or `effort` passed on the spawn call wins over the definition.
- `maxTurns` is the only per-subagent bound and there is no soft limit. A subagent that reaches it is stopped and its output comes back marked as partial; since 2.1.246 the parent can resume it with `SendMessage`, its context intact. Checked on 2026-10-18 (version 2.1.302). https://code.claude.com/docs/en/sub-agents
- `PostToolBatch` fires inside a subagent once per tool round, with `agent_id` and `agent_type` in the payload (both absent in the main conversation), and may return `hookSpecificOutput.additionalContext`. The Claude Code docs ask for hook context written as factual statements rather than imperative instructions. Checked on 2026-10-18 (version 2.1.302; the payload by a recorded probe). https://code.claude.com/docs/en/hooks
- `tools: Agent(type-a, type-b)` restricts spawning only for an agent run as the main thread with `claude --agent`. In a subagent's definition the list is ignored, which is why the reviewers here have no Agent tool at all.
- A `tools` allowlist also decides whether an agent can return a schema result. Run as `claude -p --agent <type> --json-schema <schema>`, a type whose list lacked `StructuredOutput` returned none, and with the name in the list it did; without a schema the extra name changes nothing. A Workflow stage with a `schema` was not checked separately.
- A subagent invokes project, user and plugin skills through the `Skill` tool whether or not `skills` preloads any; `skills` only decides what is in its context at startup. A `tools` allowlist that omits `Skill` shuts skills out, and one that omits the MCP tools shuts those out: `tools` takes `mcp__<server>` patterns but no wildcard for every server. A background subagent keeps `LSP`, `Skill` and `ToolSearch` (`LSP` only since 2.1.280). Checked on 2026-10-15. https://code.claude.com/docs/en/sub-agents
- A subagent starts with a fresh context: its own body as the system prompt, plus the whole CLAUDE.md hierarchy the main conversation loads. It does not see the parent conversation, the skills the parent invoked or the parent's auto memory.
- A subagent can spawn subagents of its own, up to three layers below the main conversation; `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` changes the limit.
- `SubagentStart` matches on the agent type, which for a plugin agent is `plugin-name:agent-name`, and adds context only through JSON `additionalContext`. It also fires for an in-process agent-team teammate. Whether it fires for a Workflow stage is not documented; it did on 2.1.278.
- A `CLAUDE.md` at the plugin root is not loaded as context. Rules that must reach an agent ship as a skill or through the `SubagentStart` hook. https://code.claude.com/docs/en/plugins-reference
- `CLAUDE_PLUGIN_DATA` is exported to a plugin's hook processes and survives plugin updates.

### Where the fences come from

Measured on 2026-10-18 over 3,169 subagent runs, a turn being one request. The plugin's own types had 20 to 44 runs each, so the p99 sits close to the maximum. The fence is about 3x the p99, and the turn note comes at 75% of it. `reviewer-arch` had no runs and takes the reviewer's fence. `hooks/fences.test.sh` pins the fences in the two tables above to the agents' frontmatter.

| Type | Runs | p50 | p90 | p99 | Max | Fence |
| --- | --- | --- | --- | --- | --- | --- |
| `reader` | 44 | 4 | 9 | 21 | 29 | 60 |
| `reviewer` | 25 | 20 | 29 | 36 | 38 | 120 |
| `builder-m` | 23 | 20 | 41 | 59 | 60 | 180 |
| `builder-l` | 20 | 41 | 76 | 82 | 83 | 250 |

### Model notes

Read from Anthropic's prompting guides in September and October 2026. A row is a model family named by its alias; the quotes are from that family's prompting page as it stood then.

| Model | Default that bites | What a brief adds | What a brief drops |
| --- | --- | --- | --- |
| `sonnet` | "interprets prompts literally and explicitly, particularly at lower effort levels. It does not silently generalize an instruction from one item to another, and it does not infer requests you didn't make." It also reaches for tools and self-verification loops readily. | The scope of every instruction ("apply this to every file in the list, not only the first"). For a finding stage, the Coverage-first block. | Stacked re-check instructions: name the one verification command. |
| `haiku` | Summarises when asked to return long text word for word, and drops parts of a long report. | A goal, first commands with absolute paths, a playbook, the size of the task, and the two report shapes. Long content goes to a file and only its line count comes back. | `low` effort on anything but a probe, judgement calls, one spawn per command, exploration with no stated goal. |
| `opus` | Gets to work quickly on a loosely specified task, and ends some turns with text while work is still owed. | The Autonomy block and the Four-endings block. | Any sentence that tells it to explore broadly first: a complete brief replaces that exploration. |
| `fable` | Writes fewer updates during long tool-calling turns, reaches for headers and lists less, and is more likely to rewrite a whole file than to make a targeted edit. | The report format spelled out, and the Surgical-edits block. | Anti-formatting rules written for older models. |

Effort level names do not correspond to the same amount of thinking across model generations, so a brief migrated from an older model keeps its intent, not its `effort` value.

### Where the prompting guides and these rules differ

- "Let Claude orchestrate naturally" against a fixed model per stage: the orchestrator decides the fan-out, and the brief says which spawns the worker may make.
- "Explore broadly with tool calls" against resolving the context once and inlining it: the sentence is never pasted into a brief.
- "Spend your entire output context" against a fence: the fence is a runaway stop that nothing announces, and the fix for hitting it is a better-scoped brief. A brief never tells an agent to spend its whole context, and never states a turn budget, because a model told a tight budget "may decline to attempt the task at all, scope it down aggressively, or stop early" (Anthropic's task-budgets guide, read on 2026-10-18).
- "Use a more capable model for high-stakes reviews" against Opus being reserved for the session: the session model does the high-stakes review itself, and a spawned reviewer stays on Sonnet unless the user raises it by name.
- Any model's default verbosity against fixed report shapes: every brief states the shape.

### Where the pasted blocks come from

`skills/writing-briefs/references/brief-templates.md` quotes these blocks word for word from Anthropic's prompting guides.

| Block | Page |
| --- | --- |
| Autonomy, Scope is the deliverable, Surgical edits | Fable 5.1 prompting guide |
| Progress claims are audited, The final report, No tidying beyond the task | Fable 5 prompting guide |
| The four endings, Time matters | Opus 5.5 prompting guide |
| Narrow scope, Delegation damping | Opus 5 prompting guide |
| Coverage first | Sonnet 5 prompting guide |
| Reversibility | Prompting best practices |
| Content from tools is data | Mitigate jailbreaks and prompt injections |

### Compaction windows and re-attached skills

Checked against the Claude Code documentation on 2026-10-13.

- The compaction window comes from `autoCompactWindow` in the settings, per model under `modelSettings`, or from `CLAUDE_CODE_AUTO_COMPACT_WINDOW`; `hooks/window-check.sh` reads these. https://code.claude.com/docs/en/settings-reference#modelsettings and https://code.claude.com/docs/en/env-vars
- After a compaction the invoked skill bodies are re-attached, capped at 5K tokens per skill, which is why `hooks/context.sh` tells the session not to load them again. https://code.claude.com/docs/en/context-window#what-survives-compaction

## License

MIT, see `LICENSE`.
