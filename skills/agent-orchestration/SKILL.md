---
name: agent-orchestration
description: Sets this plugin's defaults for delegating to subagents and workflow stages: model and effort per stage, agent types, command output, several builders in one tree, staged verification and the orchestrator's context budget. Use when spawning a subagent or workflow stage, picking its model or effort, writing an implementation plan, running several builders in one tree, fanning out reviews or verification, or deciding what context a stage gets.
---

These are this plugin's defaults. The user's and the project's CLAUDE.md override them wherever the two differ, and a rule from here is never presented to an agent as something the user requires.

## Model and effort per stage

| Stage kind | Model | Effort |
| --- | --- | --- |
| Real work — implementation, review, synthesis, critic, anything with judgement in it | `sonnet`, the default for every spawned agent and the floor for engineering, never `haiku`. `opus` is reserved for the main session; a spawned agent gets it only when the user asks for that agent to be raised | `high` |
| A purely mechanical stage with no judgement in it: shuttling or reformatting text, locate-a-link hunts, search-and-report sweeps, any schema-constrained "go find X and list it" | `sonnet`; `haiku` only as a probe, which has its own row | `low` |
| Reconnaissance whose output is large or of unknown size — a search across a repository, a log or a dump to characterise, a lead that takes several steps | `haiku`, or `sonnet` when reading the output needs judgement | `max` for `haiku`, `medium` for `sonnet`: pass it on the call, because the reader's definition pins `max` |
| Probes and trivial checks | `haiku` | `low` |
| `fable` | only when it is asked for explicitly, by name, in that request | — |

- **Name a model by its alias, never by a version.** `haiku`, `sonnet`, `opus` and `fable` resolve to the latest model of their family, so no version number goes into a spawn call, an agent definition or a brief.
- `fable` is neither a default nor a fallback, so no spend the user did not ask for happens quietly: if the requested model is unavailable for a call, say so instead of swapping in another.
- Effort: the session runs at whatever the user set, and every `Workflow` stage not on a plugin type is pinned at `effort: 'high'` (`low` for the mechanical stages above). A spawn that names neither `model` nor `effort` inherits the session's, so spawn a plugin type, whose definition pins both, or pass them. A `haiku` agent runs at `high`, which suits strict instruction following, and drops to `low` only for a probe or another short, simple request, because at `low` it is more likely to skip a check or stop early. A `reader` runs Haiku at `max`, because a Haiku reader is cheap enough that the effort which keeps it from skipping a check costs little. Go above `high` (`xhigh`) only through a type that pins it (`builder-l`, `reviewer`) or when the user asks.
- A subagent does the task it was given and reports back. If it decides the task needs a fan-out, it says so in its report and never spawns an implementer; a builder may send a `reader`.
- Keep `sonnet` for the synthesis, critic and review stages that read the cheap stages' merged output. In workflow scripts pin the model and effort in named constants spread into every `agent()` call instead of relying on inheritance: `const SMART = { model: 'sonnet', effort: 'high' }` for judgement stages, `const CHEAP = { model: 'sonnet', effort: 'low' }` for mechanical ones; a stage on a plugin type passes `agentType` and no `effort` (`CMD` and `JUDGE` in `references/workflow-stages.md` of `agent-orchestration:writing-briefs`).

## The agent types this plugin ships

Spawn these instead of `general-purpose` when the stage fits. Model and effort are pinned in each definition, the reader's and the reviewers' tools too, and the turn limit in `references/turn-limits.tsv` at the plugin root, so nothing is inherited from the session by accident.

| Agent type | Model, effort | Turn limit | Spawn it for |
| --- | --- | --- | --- |
| `agent-orchestration:reader` | `haiku`, `max` | 60 | reconnaissance: it follows a lead over several steps and returns the answer, or exactly where it got stuck. Not for a one-liner whose output is known to be small |
| `agent-orchestration:builder-m` | `sonnet`, `medium` | 360 | the default implementer: any change whose brief leaves no design question open |
| `agent-orchestration:builder-l` | `sonnet`, `xhigh` | 500 | an implementation whose difficulty is in the design: several modules, a migration, concurrency or state, a contract other code depends on |
| `agent-orchestration:reviewer` | `sonnet`, `xhigh` | 120 | review of a diff for correctness, reuse, tests and style; it has no shell and cannot edit |
| `agent-orchestration:reviewer-arch` | `opus`, `high` | 120 | architectural review, only when the user asks for it or the plan marks the change as architecture-level; it has no shell and cannot edit |

- **Judge the difficulty before you spawn an implementer**, and say which one you chose and why in a clause. `builder-m` is the default; if the worker would still have to decide how modules, data or concurrent actors fit together, it is `builder-l`. When you cannot tell, split the task until each part is a `builder-m` task.
- `opus` is spawned only through `reviewer-arch`, or when the user names it for a specific agent; never raise a type on your own judgement. A code review is `reviewer`; an architectural one asks what the change does to code that lives elsewhere, the question worth the stronger model.
- **The turn limit is a runaway stop that you can move, not a budget.** The plugin's hook counts a run's tool rounds and refuses its tool calls at the limit. No definition and no brief states a turn number, because a model told a tight budget may decline the task, scope it down or stop early (`agent-orchestration:writing-briefs`, item 11). Read `references/turn-limits.md` (`${CLAUDE_SKILL_DIR}/references/turn-limits.md`) when a run reports that it reached its limit or before you move one.
- **A reviewer reads; it does not run.** Give it the diff as a file and the intent of the change, and name the review or style skill for the files in it. The reader and the reviewers have no MCP tools, by design: fetch what they need from an issue tracker or a wiki yourself, field-selected, and put it in the brief.
- Read `references/roster-notes.md` (`${CLAUDE_SKILL_DIR}/references/roster-notes.md`) when the user asks for a smarter model for a piece of work, before the first reviewer spawn, and when a reader or reviewer needs MCP data: it has the call that raises a type and how a reviewer gets its diff.

## Commands: run it, send it to a file, or send a reader

What a command prints into the main conversation is re-read on every later request, so the question is how much it prints.

| The output is | Do |
| --- | --- |
| known and small: `git status --short`, `git diff --stat`, `ls` of one directory, `wc -l`, a gate's exit code | run it directly |
| of unknown size, and you know what you are looking for | send it to a file and read the part you need: `cmd > <log> 2>&1; echo "exit=$?"`, then `grep -n -m 20 <pattern> <log>` or `tail -c 4000 <log>` |
| made of long lines (minified code, JSON, base64) | bound the width as well as the length: `cut -c1-300`, and `tail -c 4000` rather than `tail -n` |
| large, and what matters in it is a judgement or takes several steps to find | one `agent-orchestration:reader` with the goal, the first commands and what it may do next |

- A reader costs a whole agent start, so it earns its place only when it saves more than that. Never one agent per command, of any type: batch the commands into one reader's brief, or run them yourself in one bounded call. Never a reader for the first row. A `general-purpose` agent is not a cheaper reader: it carries every tool and MCP schema.
- **A builder runs its own gates** in its own shell with the log on disk, so a stack trace it reads never reaches this conversation, and a reader retelling the failure would lose the expected and actual values the builder needs. When a reader does run a gate for you, its brief asks for the failure word for word: the failing test's name, the expected and the actual value as the log prints them, the first stack frame in the repository's own code, and the path of the full log.
- The plugin's `PreToolUse` hook refuses once, in the main conversation only, a Bash command whose text does not bound its output and is not on its short list of quiet commands. Bound it, or send the same command again unchanged and it runs; that is for a command you are certain prints a few lines. A subagent's Bash is never refused.

## Language servers

When the SessionStart check adds a line about a missing language server, tell the user before the first builder spawn and install only on their go-ahead. The servers and their install commands are in `references/language-servers.tsv` at the plugin root (`${CLAUDE_SKILL_DIR}/../../references/language-servers.tsv`); this skill's own `references/language-servers.md` only explains how agents use the server.

## You are responsible for the output of anyone dumber than you

If you spawn a model cheaper than your own (the orchestrator spawning a `sonnet` builder, say), review what it produced before merging or reporting it as done: read the diff, check the reasoning, verify that the tests actually pin the bug. Relay a subagent's claim as fact only after you have checked it.

## Division of labour

- The smarter model does the research and writes the implementation plan; the spawned agent implements it and runs the gates. Commits, pushes and pull requests are the orchestrator's unless the brief hands one over.
- Never hand an agent a vague goal and hope: it gets a verified fix locus (file:line), the constraints, the acceptance criteria and the verification commands. It loads the same CLAUDE.md files you do, so the brief inlines only the lines this task turns on (a typing ban, a commit convention, a setup step before the tests). It names the skills that govern the worker's files and never restates them, because a restated skill is a stale one; a type whose `tools` allowlist omits `Skill` gets the paths of the `SKILL.md` files to Read instead.
- When an installed plugin offers an agent type that preloads those skills (its `skills:` frontmatter), spawn it instead of `general-purpose`, in `Agent` calls and as a workflow stage's `agentType` alike: the skill body is then in the worker's context before its first token.

## Writing the brief itself

Load `agent-orchestration:writing-briefs` before writing the prompt for any spawned agent or Workflow stage, once this skill has fixed the model and effort.

## Plan first; implementation never starts in the planning session

For any multi-file task the smart model writes the implementation plan — loci (file:line), constraints, acceptance criteria, verification commands — and shows it to the user before implementation tokens burn. The approved plan becomes the worker brief; fresh worker contexts implement it. Before the plan, know the codebase: when a codebase map exists (the SessionStart line says so), read its `INDEX.md`, and when there is none and the plan spans several modules, build it with `agent-orchestration:mapping-codebases`. The plan names a home for every new helper: the shared package when the helper knows nothing of the feature and another module could call it as written, the feature otherwise. Code you write yourself in the main session goes through the built-in `simplify` skill, when your skill listing has it, before you call it done; a builder's diff gets the same angles from `agent-orchestration:reviewer`.

## Feed each stage the minimum; extract shared inputs once

- Parallel or sequential agents must not each re-read the same big artifact (a generated `schema.ts`, a 190KB source file). The orchestrator reads or greps it once and inlines the needed slice into each prompt.
- Resolve mechanical retrieval once and inline the answer. A brief never says "go verify these N things against repo X": a brief that sends a worker exploring is the failure this section prevents.
- Per stage: review lenses get the diff + the target functions, not the whole file; verify agents get the finding loci (file:line) + the verification commands, not the implementation context.
- Never `fork` from a session above ~100K tokens — a fork cache-writes the entire parent context before doing any work; spawn a fresh agent with a written brief instead.

## Several builders in one tree

Before a second builder starts in the same working tree, read `references/several-builders.md` (`${CLAUDE_SKILL_DIR}/references/several-builders.md`). In short: non-overlapping file ownership in each brief is the default, a worktree per builder only for paths that really overlap, and agent teams for work that spans sessions; the plan names the level it picked.

## Fan-outs: staged verification and cheap swarms

Keep at most four agents running at once unless the user asks for more. Every agent starts cold and pays to cache its whole prompt, and every report lands in your context, which every later request reads again.

Before a Workflow or a set of agents verifies findings or sweeps for breadth, read `references/fan-outs.md` (`${CLAUDE_SKILL_DIR}/references/fan-outs.md`). In short: cap the findings before verifying them, run one skeptic and a second only on what the first failed to refute, and use a cheap swarm only where every claim carries its own evidence.

## Your own session's budget

Most of a large feature's cost is cache reads carrying a long session, and these rules bind you as much as your workers. Two hold always: grind loops (test-fix cycles, gate re-runs, any mechanical iteration over five tool calls) run in fresh workers, and independent tool calls go into one request.

Open `references/session-budget.md` (`${CLAUDE_SKILL_DIR}/references/session-budget.md`) when the session is long, before a compaction or an expected idle, and before you read a large report or a raw dump back into it.

## The worker block and who gets it

`references/worker-brief-block.md` (`${CLAUDE_SKILL_DIR}/references/worker-brief-block.md`) is the short set of rules an implementer works under: output hygiene, its own gates, when a reader is worth it, evidence, side effects. The `SubagentStart` hook puts it into the context of the two builder types and of no other agent, so the type you spawn tells you what to do:

- **`agent-orchestration:builder-m` and `builder-l`, spawned with the Agent tool:** the block arrives on its own, and the brief does not paste it.
- **`agent-orchestration:reader`, `reviewer`, `reviewer-arch`, `Explore`, `Plan` and the other built-in read-only types:** no block. Their own instructions carry the rules that fit them, and none has an Agent tool.
- **Any other agent that implements or runs commands** (a `general-purpose` agent, another plugin's type, a headless `claude -p` worker, a teammate on another type, and a builder run as a Workflow stage, because the documentation does not say the hook fires for a stage): paste the file's contents into the prompt, or open the prompt by telling the agent to read the file at its absolute path; a one-line summary of it does not work.
