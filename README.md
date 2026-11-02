# agorch

agorch is short for agent orchestration; the plugin was called `agent-orchestration` until 0.12.0, and the GitHub repository keeps that name. A Claude Code plugin: the rules a session follows when it spawns subagents or workflow stages, and the agent types those rules name. It is a policy made of prompts and hooks. It decides which model does what, what a brief must contain and what a spawned agent may do; running the agents stays with Claude Code, and the plugin adds no task queue or locking of its own.

## Install

```sh
claude plugin marketplace add SkuratovichA/agent-orchestration
claude plugin install agorch@agorch
```

The same from inside a session: `/plugin marketplace add SkuratovichA/agent-orchestration`, then `/plugin install agorch@agorch`. A new session then starts with the line "The agorch plugin is active".

After a rename from `agent-orchestration`, the skills are `agorch:agorch`, `agorch:writing-briefs` and `agorch:mapping-codebases`, the agent types are `agorch:builder-m` and so on, and the codebase maps are looked for in `${XDG_CACHE_HOME:-~/.cache}/agorch/maps` (move an old `agent-orchestration/maps` there to keep them). Anything of yours that names the old skills or types, a CLAUDE.md or a permission rule, needs the new names.

`jq` is optional. Without it the Bash-output check, the turn limit and the language-server check do nothing; the skills, the agents and the worker block work the same.

## What is in it

| Path | What it is |
| --- | --- |
| `skills/agorch/` | The `agorch:agorch` skill: model and effort per stage, the agent roster, when a command runs directly and when it goes to a reader, several builders in one tree, staged verification, context economics |
| `skills/agorch/references/worker-brief-block.md` | The short block of rules a builder works under |
| `skills/agorch/references/` | Also the sections the skill points to when they are needed: language servers, several builders in one tree, staged verification and cheap swarms, turn limits, roster notes, the session's own budget |
| `skills/writing-briefs/` | The `agorch:writing-briefs` skill: the brief skeleton, the blocks to paste, how to treat a report |
| `skills/writing-briefs/references/` | The brief templates and the Workflow-stage rules |
| `skills/mapping-codebases/` | The `agorch:mapping-codebases` skill: reading, refreshing and building the per-repository codebase map |
| `agents/` | The agent types below |
| `hooks/` | The hooks below, with a test file beside each script |
| `bin/agent-turns` | The command that reads and moves a run's turn limit, on the Bash tool's PATH while the plugin is enabled |
| `bin/codebase-map` | Manages the per-repository codebase map cache outside the repo: `dir` prints and creates it (shared by all worktrees), `status` reports staleness and which modules to refresh, `modules` proposes a module split from tracked files, `stamp` records the build commit. Needs only git and POSIX tools. |
| `references/language-servers.tsv` | The language servers the SessionStart check knows about |
| `references/turn-limits.tsv` | The default turn limit of each agent type |

These are the plugin's defaults. A user's or a project's CLAUDE.md overrides them wherever the two differ.

## Agents

| Agent type | Model, effort | Turn limit | Tools | For |
| --- | --- | --- | --- | --- |
| `agorch:reader` | haiku, max | 60 | Bash, Read, Grep, Glob, LSP, Skill | reconnaissance: follows a lead over several steps and returns the answer or where it got stuck, never raw output |
| `agorch:builder-m` | sonnet, medium | none | all | the default implementer: a task or a batch of tasks whose brief leaves no architectural question open |
| `agorch:builder-l` | sonnet, xhigh | none | all | only mission-critical work or work that needs long reasoning, never work that is merely large |
| `agorch:reviewer` | sonnet, xhigh | 300 | Read, Grep, Glob, LSP, Skill | code review of a diff, a pull request or a whole batch: correctness, reuse, tests, style |
| `agorch:reviewer-arch` | opus, high | 300 | Read, Grep, Glob, LSP, Skill | architectural review, only on request or when the plan marks the change as architecture-level |

Work is batched: twenty tasks are four or five builders, each given its tasks in order, and one reviewer reads the whole batch (`skills/agorch/references/batching.md`). A builder never decides an architectural question itself: it finishes the tasks that do not depend on it and ends its turn with a `DECISION NEEDED` report, and the orchestrator answers it with `SendMessage`.

The builders have no turn limit, because a batch takes many turns, and every non-reader type compacts its own context at 200K tokens (`autoCompactWindow` in its definition). The other types keep a runaway stop far above ordinary work (the reader about 3x the p99 of past runs, the reviewers sized for a batch). The plugin's hook enforces it, not Claude Code: it counts the run's tool rounds, notes the count at 75% of the limit and at the limit, and from then on refuses the run's tool calls with a reason, so the run ends with a report of what is done and what is left. The parent session moves the limit, or gives a builder one, whenever it wants and resumes a refused run with `SendMessage`:

```sh
agent-turns                        # every run of this session: rounds, limit, and whether the limit is the run's, the session's or the default
agent-turns <agent-id> 720         # one run's limit, from its next tool call on; `default` removes it
agent-turns --type builder-m 720   # this session's limit for a type, for its running and later runs that have no limit of their own
```

The builders' `maxTurns` is 10000 and the other agents' 1000. That is Claude Code's own hard stop, which nothing moves during a session, and the builders' is out of reach of any batch; what Claude Code does with a `maxTurns` that is left out is not documented, which is why the builders carry a number and not an omission. A run cut there comes back marked partial and can be resumed the same way. `builder-m` is the default implementer; the orchestrator picks `builder-l` only for mission-critical work or work that needs long reasoning. A `model` or `effort` passed on the spawn call raises any type when the user asks for it. Opus is spawned only through `reviewer-arch` or when the user names it.

A builder runs its own tests, lint and type checks in its own shell with the log on disk, and sends a reader only on reconnaissance. A reviewer has no shell and no Agent tool, so it cannot change anything or start an agent that can: the orchestrator gives it the diff as a file. The reader and the reviewers also list `LSP`, `Skill` and `ToolSearch`, so they navigate with the language server and load the skills a brief names, and `StructuredOutput`, which a Workflow stage needs to return a schema result. They get no MCP tools: an allowlist can grant them only server by server, and most servers carry write tools.

Builders, reviewers and the reader navigate with the language server; the builders also treat its diagnostics as their first gate. `references/language-servers.tsv` lists the plugin, the binary and the install command per project marker file, and a SessionStart check names a server that is missing when a marker file sits in the working directory or up to two levels below it.

## Hooks

| Event | Script | What it does |
| --- | --- | --- |
| SessionStart | `hooks/context.sh` | adds one line that tells the session to load the skills before it spawns anything; after a compaction, says the skills it loaded are already re-attached. Leaves a marker for the session in the plugin's data directory, where `agent-turns` finds the turn counters |
| SessionStart, on startup | `hooks/lsp-check.sh` | names a language server the project needs and does not have, unless its plugin is switched off in the settings; installs nothing |
| SessionStart, on startup | `hooks/window-check.sh` | names a compaction window below 200K tokens in the settings or the environment; changes nothing |
| SessionStart, on startup, clear and compact | `hooks/map-check.sh` | when a map of the repository exists, tells the session where it is, how stale it is and which modules changed, and points to `INDEX.md` and the `mapping-codebases` skill. Silent otherwise |
| SubagentStart, matcher `^agorch:builder-` | `hooks/context.sh` | puts the worker block into the context of the two builder types. The reader and the reviewers work from their own definitions; built-in agents such as Explore and Plan, and other plugins' agents, get nothing |
| PreToolUse on Bash | `hooks/bash-output.sh` | in the main conversation only, adds a note, once per command, when a command's text does not bound its output; the command runs. It blocks nothing and grants no permission, and a simple command (a git state or history command with a cap, `ls`, a commit or a push) gets no note. A subagent's Bash gets nothing |
| PreToolUse on every tool | `hooks/turn-budget.sh` | inside a run of one of this plugin's agent types that has a turn limit only, refuses a tool call once the run's tool rounds have reached its turn limit, with a reason that says the run ends with its report and the parent can raise the limit and resume it. `StructuredOutput` is never refused, so a schema stage can still return its result |
| PostToolBatch | `hooks/turn-budget.sh` | inside a run of one of this plugin's agent types that has a turn limit only (a builder has none until `agent-turns` gives it one, and is not counted), counts the tool rounds and adds a factual note at 75% of the turn limit and at the limit: the count so far, the limit, and what happens there. The limit is re-read on every call: the run's own limit set with `agent-turns`, else the session's for its type, else `references/turn-limits.tsv`. Any other agent, and the main conversation, get nothing |
| SessionEnd | `hooks/cleanup.sh` | removes the markers, counters and limits the hooks and `agent-turns` left for that session, and any such file older than a week |

Every hook exits 0 whatever happens, so a broken hook never blocks a session. The Bash check and the turn limit keep their markers, counters and limits in the plugin's data directory, never in a shared temp directory.

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

- An agent file may set `name`, `description`, `tools`, `disallowedTools`, `model`, `effort`, `maxTurns`, `autoCompactWindow`, `skills`, `memory`, `isolation`, `background`, `color` and `omitClaudeMd`. `autoCompactWindow` (100000 to 1000000, since 2.1.296) is the subagent's own compaction window, and `CLAUDE_CODE_AUTO_COMPACT_WINDOW` overrides it; the agents here set 200000, the floor `hooks/window-check.sh` warns below. Checked on 2026-11-02. https://code.claude.com/docs/en/sub-agents `hooks`, `mcpServers` and `permissionMode` are ignored in an agent that a plugin ships. https://code.claude.com/docs/en/sub-agents
- `effort` takes `low`, `medium`, `high`, `xhigh` or `max` and overrides the session's effort; `model` takes `sonnet`, `opus`, `haiku`, `fable`, a full model id or `inherit`. A `model` or `effort` passed on the spawn call wins over the definition.
- `maxTurns` is the only per-subagent bound Claude Code itself enforces, and there is no soft limit; the `Agent` tool takes no turn count. A subagent that reaches it is stopped and its output comes back marked as partial; since 2.1.246 the parent can resume it with `SendMessage`, its context intact. Checked on 2026-10-18 (version 2.1.302). What a `maxTurns` that is left out means is not documented, so the builders, which are meant to have no limit, carry 10000 and not an omission (2026-11-02). https://code.claude.com/docs/en/sub-agents
- A subagent cannot ask its parent a question and wait: `AskUserQuestion` is removed from subagents. The documented route is the one `DECISION NEEDED` uses: the agent ends its turn with the question in its report, and the parent answers with `SendMessage` to the same agent, which resumes with its full conversation history (2026-11-02).
- `PreToolUse` documents `hookSpecificOutput.additionalContext` only in an example that also carries `permissionDecision: "allow"`. Probed on 2026-11-02 (version 2.1.316) with `claude -p`: a hook that returns the field alone puts the note in the model's context and the call goes through the normal permission flow, so under `--permission-mode default` a Bash command outside `--allowedTools` was refused exactly as with a silent hook. `hooks/bash-output.sh` relies on this and never returns a `permissionDecision`.
- Agent definitions are read when a session starts, and `/plugin` does not reload them: a session started before an update keeps the old `maxTurns` until it restarts. Seen on 2026-10-22, when a session kept the 40 of 0.7 after 0.8 was installed.
- Inside a subagent, `PreToolUse` carries `agent_id`, `agent_type` and `tool_name`, and a `permissionDecision` of `deny` refuses the call; the agent reads the reason and writes its report. Checked on 2026-10-22 (version 2.1.308) with a probe plugin.
- `PostToolBatch` fires inside a subagent once per tool round, with `agent_id` and `agent_type` in the payload (both absent in the main conversation), and may return `hookSpecificOutput.additionalContext`. The Claude Code docs ask for hook context written as factual statements rather than imperative instructions. Checked on 2026-10-18 (version 2.1.302; the payload by a recorded probe). https://code.claude.com/docs/en/hooks
- `tools: Agent(type-a, type-b)` restricts spawning only for an agent run as the main thread with `claude --agent`. In a subagent's definition the list is ignored, which is why the reviewers here have no Agent tool at all.
- A `tools` allowlist also decides whether an agent can return a schema result. Run as `claude -p --agent <type> --json-schema <schema>`, a type whose list lacked `StructuredOutput` returned none, and with the name in the list it did; without a schema the extra name changes nothing. A Workflow stage with a `schema` was not checked separately.
- A subagent invokes project, user and plugin skills through the `Skill` tool whether or not `skills` preloads any; `skills` only decides what is in its context at startup. A `tools` allowlist that omits `Skill` shuts skills out, and one that omits the MCP tools shuts those out: `tools` takes `mcp__<server>` patterns but no wildcard for every server. A background subagent keeps `LSP`, `Skill` and `ToolSearch` (`LSP` only since 2.1.280). Checked on 2026-10-15. https://code.claude.com/docs/en/sub-agents
- A subagent starts with a fresh context: its own body as the system prompt, plus the whole CLAUDE.md hierarchy the main conversation loads. It does not see the parent conversation, the skills the parent invoked or the parent's auto memory.
- A subagent can spawn subagents of its own, up to three layers below the main conversation; `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` changes the limit.
- `SubagentStart` matches on the agent type, which for a plugin agent is `plugin-name:agent-name`, and adds context only through JSON `additionalContext`. It also fires for an in-process agent-team teammate. Whether it fires for a Workflow stage is not documented; it did on 2.1.278.
- A `CLAUDE.md` at the plugin root is not loaded as context. Rules that must reach an agent ship as a skill or through the `SubagentStart` hook. https://code.claude.com/docs/en/plugins-reference
- `CLAUDE_PLUGIN_DATA` is exported to a plugin's hook processes and survives plugin updates. It is not exported to the Bash tool's commands, which do carry `CLAUDE_CODE_SESSION_ID` (the hooks' `session_id`, in the main conversation and in its subagents alike) and `CLAUDE_CONFIG_DIR`; that is why `agent-turns` finds the plugin's data directory through the marker SessionStart leaves there. A plugin's `bin/` directory is on the Bash tool's PATH while the plugin is enabled. Checked on 2026-10-22 (version 2.1.308) with a probe plugin.

### Language servers

Checked on 2026-10-12 (Claude Code 2.1.296, typescript-language-server 6.0.2).

- An agent whose `tools` is an allowlist has the `LSP` tool only when the list names it.
- The first `findReferences` after a server starts can miss files: on a two-file project the first call returned the references in one file and the second call all of them. The agents therefore ask twice and back "nothing else uses this" with a search.
- `typescript-language-server` drives `tsserver`, and the `typescript` package stopped shipping it in 7.0. With TypeScript 7 as the only one it can find, the server stops at start-up with "Could not find a valid TypeScript installation", which is why the install command pins `typescript@6`. In a project that itself uses TypeScript 7 the server falls back to the global TypeScript 6 and says that its answers do not reflect the project's compiler.

### Where the turn limits come from

Measured on 2026-10-18 over 3,169 subagent runs, a turn being one request. The plugin's own types had 20 to 44 runs each, so the p99 sits close to the maximum. The limit was set at about 3x the p99; the builders' were doubled on 2026-10-22, and on 2026-11-02 they were taken away (`none`), because one builder now works a batch of tasks in sequence and a run of that size has no p99 to measure it against. The reviewers' went from 120 to 300 for the same reason: one reviewer reads a whole batch. `reviewer-arch` had no runs and takes the reviewer's limit. `hooks/turn-limits.test.sh` pins the limits in the two tables above to `references/turn-limits.tsv`, and every agent's `maxTurns` above its limit. A builder that needs a stop for one run gets it with `agent-turns <agent-id> <turns>`.

| Type | Runs | p50 | p90 | p99 | Max | Limit |
| --- | --- | --- | --- | --- | --- | --- |
| `reader` | 44 | 4 | 9 | 21 | 29 | 60 |
| `reviewer` | 25 | 20 | 29 | 36 | 38 | 300 |
| `builder-m` | 23 | 20 | 41 | 59 | 60 | none |
| `builder-l` | 20 | 41 | 76 | 82 | 83 | none |

### The codebase map

Added in 0.10.0. The `agorch:mapping-codebases` skill keeps one map per repository in `${XDG_CACHE_HOME:-~/.cache}/agorch/maps/<repo>-<key>/`, outside the working tree, where `bin/codebase-map dir` creates and prints it. All worktrees of a repository share that directory, and nothing in it is ever committed. The map is a lead, not proof: a session confirms a claim with the language server or one grep before a plan relies on it, and when the code disagrees the code wins and that module is due for a refresh. The module readers run on the reader type (`haiku`) and the index reader on `sonnet`. `hooks/map-check.sh` tells a new session that a map exists and how stale it is, and the planning section of the `agorch` skill sends the orchestrator to its `INDEX.md`.

### Where the placement and plain-code rules come from

Added in 0.10.0 to the builders and the reviewer. In a test on a toy monorepo, `builder-m` without the placement rule inlined a generic truncate helper in the service 2 times out of 2 ("can be moved later"); with the rule it put the helper in the shared package 3 times out of 3. The plain-code bullet and the reviewer's matching bullet have no measurement of their own.

### Figures the skills point to

Moved out of `skills/agorch/SKILL.md` in 0.10.0 so that the skill, which a compaction re-attaches only up to its first 5K tokens, carries rules and not measurements. None of the first three was recorded with a date.

- A Haiku reader cost about $0.10 a run, which is why the effort that keeps it from skipping a check (`max`) is cheap for it.
- Over two weeks of runs, a Sonnet reader at `high` cost about 19 times a Haiku one, which is why `max` belongs to Haiku only.
- A `general-purpose` agent started at about 70K tokens of context, a `reader` at about 30K.
- A run cut at `maxTurns` can be resumed with `SendMessage` from Claude Code 2.1.246 on; the check is under "What Claude Code does with a plugin agent". The measurement behind the turn limits (3,169 runs, about 3x the p99 for the reader and the reviewers, 6x for the builders) is under "Where the turn limits come from".

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
- "Spend your entire output context" against a turn limit: the limit is a runaway stop that no brief announces, and the fix for reaching it is a better-scoped brief or, when little is left, a raised limit. A brief never tells an agent to spend its whole context, and never states a turn budget, because a model told a tight budget "may decline to attempt the task at all, scope it down aggressively, or stop early" (Anthropic's task-budgets guide, read on 2026-10-18).
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

- The compaction window comes from `autoCompactWindow` in the settings, per model under `modelSettings`, from `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, or for a subagent from its own `autoCompactWindow` frontmatter; `hooks/window-check.sh` reads the first two. https://code.claude.com/docs/en/settings-reference#modelsettings and https://code.claude.com/docs/en/env-vars
- After a compaction the invoked skill bodies are re-attached, capped at 5K tokens per skill, which is why `hooks/context.sh` tells the session not to load them again. https://code.claude.com/docs/en/context-window#what-survives-compaction

## License

MIT, see `LICENSE`.
