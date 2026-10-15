---
name: agent-orchestration
description: Use when spawning a subagent or workflow stage, picking its model or effort, writing a worker brief or implementation plan, running several builders in one tree, fanning out reviews or verification, or deciding what context a stage gets.
---

These are this plugin's defaults. The user's and the project's CLAUDE.md override them wherever the two differ, and a rule from here is never presented to an agent as something the user requires.

## Model and effort per stage

| Stage kind | Model | Effort |
| --- | --- | --- |
| Real work — implementation, review, synthesis, critic, anything with judgement in it | `sonnet` — the default for every spawned agent. `opus` stays reserved for the main/orchestrator session — use it for a spawned agent only when the user asks for that agent to be raised | `high` |
| A purely mechanical stage that only shuttles or reformats text, with no judgement in it | `haiku` / `sonnet` — `opus` is waste | `low` |
| Mechanical retrieval — locate-a-link hunts, search-and-report sweeps (code host, chat, wiki, package registries), any schema-constrained "go find X and list it" | `sonnet`, not `opus` | `low` |
| Reconnaissance whose output is large or of unknown size — a search across a repository, a log or a dump to characterise, a lead that takes several steps | `haiku` (`sonnet` when reading the output needs judgement) | `high` |
| Probes and trivial checks | `haiku` | `low` |
| `fable` | only when it is asked for explicitly, by name, in that request | — |

- **Name a model by its alias, never by a version.** `haiku`, `sonnet`, `opus` and `fable` resolve to the latest model of their family, so every spawn uses the latest Haiku and the latest Sonnet unless the user names a version. No version number goes into a spawn call, an agent definition or a brief, and this plugin needs no edit when a new version ships.
- Agents doing real work must be smart — don't send a weak model to do engineering; `sonnet` is the floor for that, not `haiku`.
- `opus` is reserved for the main/orchestrator session, not spawned agents — unless the user asks for a specific agent to run on `opus`, or the stage is an architectural review through `agent-orchestration:reviewer-arch`.
- `fable` is NOT a default and NOT a fallback. If the requested model is unavailable for a call, say so — don't silently swap in another model.
- Effort: the session runs at whatever the user set; every `Workflow` stage is pinned at `effort: 'high'` (`low` for the mechanical stages above). The `Agent` tool takes `model` and `effort` on the call, and a spawn that names neither inherits the session's: spawn a plugin type, whose definition pins both, or pass them. A `haiku` agent runs at `high`, the level that suits strict instruction following, and drops to `low` only for a probe or another short, simple request, because at `low` it is more likely to skip a check or stop early. Raise a specific agent above `high` (`xhigh`) only through an agent type that pins it (`builder-l`, `reviewer`) or when the user asks for that agent to be raised.
- Corollary for subagents themselves: a subagent does the task it was given and reports back. If it decides the task needs a fan-out, it says so in its report and never spawns an implementer. The one exception is reconnaissance: a builder may send a `reader`.
- Keep `sonnet` for the synthesis/critic/review stages that read the cheap stages' merged output — `opus` is reserved for the main session, not spawned for this either, unless asked. In workflow scripts pin this structurally instead of relying on inheritance:

  ```js
  const SMART = { model: 'sonnet', effort: 'high' };  // judgement: review, synthesis, critic
  const CHEAP = { model: 'sonnet', effort: 'low' };   // mechanical: locate, sweep, reformat
  agent(`find the design mocks ...`, { ...CHEAP, schema: HITS });
  agent(`synthesize the findings ...`, { ...SMART, schema: REPORT });
  ```

## The agent types this plugin ships

Spawn these instead of `general-purpose` when the stage fits. Model, effort and the turn limit are pinned in each definition, and so are the tools of the reader and the reviewers, so nothing is inherited from the session by accident.

| Agent type | Model, effort | Turn limit | Spawn it for |
| --- | --- | --- | --- |
| `agent-orchestration:reader` | `haiku`, `high` | 15 | reconnaissance: given a goal, the first commands and what it may do next, it follows the lead over several steps and returns the answer, or exactly where it got stuck. Not for a one-liner whose output is known to be small |
| `agent-orchestration:builder-m` | `sonnet`, `medium` | 40 | the default implementer: any change whose brief leaves no design question open |
| `agent-orchestration:builder-l` | `sonnet`, `xhigh` | 40 | an implementation whose difficulty is in the design: several modules, a migration, concurrency or state, a contract other code depends on |
| `agent-orchestration:reviewer` | `sonnet`, `xhigh` | 30 | review of a diff for correctness, reuse, tests and style; it has no shell and cannot edit |
| `agent-orchestration:reviewer-arch` | `opus`, `high` | 30 | architectural review, only when the user asks for it or the plan marks the change as architecture-level; it has no shell and cannot edit |

- **Judge the difficulty before you spawn an implementer**, and say which one you chose and why in a clause. `builder-m` is the default: the brief leaves no design question open. If the worker would still have to decide how modules, data or concurrent actors fit together, it is `builder-l`. When you cannot tell, split the task until each part is a `builder-m` task.
- `opus` is spawned only through `reviewer-arch`, or when the user names it for a specific agent. A code review is `reviewer`; an architectural one asks what the change does to code that lives somewhere else, and that is the question worth the stronger model.
- **The user can raise any type.** A definition fixes the role, the tools and the body; `model` and `effort` passed on the `Agent` call win over it. When the user asks for a smarter model for a piece of work, spawn the type that fits the difficulty with their model, for example `Agent({ subagent_type: 'agent-orchestration:builder-l', model: 'opus', prompt })`, and say in the brief that the user asked. Never raise one on your own judgement: when a plan marks a change as mission-critical and the user has named no model, say so in the plan and let them choose. The same call-level `model: 'sonnet'` gives a `reader` whose filtering needs judgement.
- **The turn limit is enforced by the harness, not by the agent's goodwill.** An agent that reaches it is stopped where it stands, and what it has comes back marked as partial. You can resume it, but a task that will not fit is better split before the spawn, and a brief names a smaller budget when the task needs less.
- **A reviewer reads; it does not run.** Write the diff to a file before the spawn (`git diff main...HEAD > <scratch>/change.diff`) and give the reviewer that path with the intent of the change. It searches the tree with the language server, Grep and Glob on its own, and loads the skills the brief names with the Skill tool: name the team's review or style skill for the files in the diff (a Python style skill, a testing skill) the same way you would for a builder.
- **No MCP tools in the reader or the reviewers, by design.** Their allowlist cannot grant MCP tools without naming each server, and most servers carry write tools (send a message, create a page), which would break the rule that a reading stage cannot change anything. Fetch what they need from an issue tracker or a wiki yourself, field-selected, and put it in the brief. Builders have no allowlist and inherit the session's MCP tools.

## Commands: run it, send it to a file, or send a reader

What a command prints into the main conversation is re-read on every later request, so the question for each command is how much it prints, not whether it is a command.

| The output is | Do |
| --- | --- |
| known and small: `git status --short`, `git diff --stat`, `ls` of one directory, `wc -l`, a gate's exit code | run it directly |
| of unknown size, and you know what you are looking for | send it to a file and read the part you need: `cmd > <log> 2>&1; echo "exit=$?"`, then `grep -n -m 20 <pattern> <log>` or `tail -c 4000 <log>` |
| made of long lines (minified code, JSON, base64) | bound the width as well as the length: `cut -c1-300`, and `tail -c 4000` rather than `tail -n` |
| large, and what matters in it is a judgement or takes several steps to find | one `agent-orchestration:reader` with the goal, the first commands and what it may do next |

- A reader costs a whole agent start, so it earns its place only when it saves more than that. Never one reader per command, and never a reader for the first row.
- **A builder runs its own gates** (tests, lint, type checks) in its own shell, with the log on disk. Its context ends with it, so a stack trace it reads never reaches this conversation, and a reader retelling the failure would only lose the expected and actual values the builder needs.
- When a reader does run a gate for you, the brief asks for the failure word for word: the failing test's name, the expected and the actual value as the log prints them, the first stack frame that is in the repository's own code, and the path of the full log.
- The plugin's `PreToolUse` hook refuses once, in the main conversation only, a Bash command whose text does not bound its output and is not on its short list of quiet commands. Bound it, or send the same command again unchanged and it runs, which is for the command you are certain prints a few lines. A subagent's Bash is never refused.

## Language servers

When the SessionStart check adds a line about a missing language server, tell the user before the first builder spawn and install only on their go-ahead. `references/language-servers.md` next to this file (`${CLAUDE_SKILL_DIR}/references/language-servers.md`) has the table, the plugins and the binaries.

## You are responsible for the output of anyone dumber than you

If you spawn a model weaker than yourself (e.g. you are Fable and you spawn Opus), you MUST review what it produced — read the diff, check the reasoning, verify the tests actually pin the bug — before merging or reporting it as done. Never relay a subagent's claim as fact without checking it.

## Division of labour

- The smarter model does the research and writes the implementation plan; the spawned agent implements it and runs the gates. Commits, pushes and pull requests are the orchestrator's unless the brief hands one over.
- Don't hand an agent a vague goal and hope — hand it a verified fix locus (file:line), the constraints, the acceptance criteria, and the verification commands.
- A spawned agent loads the same CLAUDE.md files you do, so a brief does not restate them. Inline only the lines this task turns on: a typing ban, a commit convention, a setup step before the tests.
- Name the skills that govern the worker's files in the brief (a testing skill, a language style skill, …) and never restate them — the worker loads them itself, the brief stays short, and a restated skill is a stale one. This holds for every type this plugin ships: the builders, the reviewers and the reader all have the Skill tool. A type without it (one whose `tools` allowlist omits `Skill`) gets the paths of the `SKILL.md` files to Read instead.
- When an installed plugin offers an agent type that preloads those skills (its `skills:` frontmatter), spawn that type instead of `general-purpose`, in `Agent` calls and as a workflow stage's `agentType` alike: the skill body is then in the worker's context before its first token, whatever the brief says.

## Writing the brief itself

Load `agent-orchestration:writing-briefs` before writing the prompt for any spawned agent or Workflow stage, once this skill has fixed the model and effort. It carries the brief skeleton (verified loci, inlined context, scope as the deliverable, owned paths and authorised side effects, the proving command per claim, the output contract, the budget as a stop condition, the autonomy block), the Workflow-stage rules in its references, and how to treat a report when it comes back. It names this skill's model table, command rules, turn limits and verification shapes instead of repeating them; its `references/brief-templates.md` holds the paste-able blocks and three filled-in briefs.

## Plan first; implementation never starts in the planning session

For any multi-file task the smart model writes the implementation plan — loci (file:line), constraints, acceptance criteria, verification commands — and shows it to the user BEFORE implementation tokens burn. The approved plan becomes the worker brief; fresh worker contexts implement it. A brief-driven worker ships a verified change for a fraction of what a worker that explores and iterates costs.

## Feed each stage the minimum; extract shared inputs once

- Parallel or sequential agents must not each re-read the same big artifact (a generated `schema.ts`, a 190KB source file). The orchestrator reads/greps it ONCE and inlines the needed slice into each prompt.
- Resolve mechanical retrieval once and inline the answer. Never write "go verify these N things against repo X" into a brief: a brief that sends a worker exploring is the failure this section exists to prevent.
- Per stage: review lenses get the diff + the target functions, not the whole file; verify agents get the finding loci (file:line) + the verification commands, not the implementation context.
- Never `fork` from a session above ~100K tokens — a fork cache-writes the entire parent context before doing any work. Spawn a fresh agent with a written brief instead.

## Several builders in one tree

Before a second builder starts in the same working tree, read `references/several-builders.md` (`${CLAUDE_SKILL_DIR}/references/several-builders.md`). In short: non-overlapping file ownership in each brief is the default, a worktree per builder is only for paths that really overlap, and agent teams are for work that spans sessions; the plan names the level it picked.

## Fan-outs: staged verification and cheap swarms

Before a Workflow or a set of agents verifies findings or sweeps for breadth, read `references/fan-outs.md` (`${CLAUDE_SKILL_DIR}/references/fan-outs.md`). In short: cap the findings before verifying them, run one skeptic and a second only on what the first failed to refute, and use a cheap swarm only where every claim carries its own evidence.

## Your own session's budget

These are the orchestrator's own rules, not just the workers' — they bite hardest in a session that spawns nothing. Most of a large feature's cost is cache reads carrying long sessions, not output. Max effort is cheap; context logistics are not.

- Phase-scope sessions: `/clear` or `/compact` at phase boundaries (spec → implement → review → polish), well before the window limit — a compact costs one rewrite of the context and pays for itself within a few requests. Hand off through a written brief or ledger, never by dragging the whole context forward.
- Compact BEFORE an expected idle longer than the prompt cache lives: an idle giant context expires and re-caches whole.
- Grind loops run in fresh workers: test-fix cycles, gate re-runs, any mechanical iteration over five tool calls. A fat-session request pays for reading the whole context before generating anything, while a fresh worker pays a small fraction of that.
- Never Read a 50KB+ agent report back into a fat session, and never take a raw MCP dump. Agents return summaries; issue-tracker and wiki data come through field-selected requests.
- Batch independent tool calls into one request: every avoided request at fat context saves a full re-read of that context.

## The worker block and who gets it

`references/worker-brief-block.md` next to this file (`${CLAUDE_SKILL_DIR}/references/worker-brief-block.md`) is the short set of rules an implementer works under: output hygiene, its own gates, when a reader is worth it, evidence, side effects. The plugin's `SubagentStart` hook puts it into the context of the two builder types and of no other agent, so the type you spawn tells you what to do, and nothing has to be checked in the conversation first:

- **`agent-orchestration:builder-m` and `builder-l`, spawned with the Agent tool** — the block arrives on its own. The brief does not paste it.
- **`agent-orchestration:reader`, `reviewer` and `reviewer-arch`** — neither. Their definitions carry the rules that fit them: none of the three has an Agent tool, and the reviewers have no shell to run a gate in.
- **Any other agent that implements or runs commands** (a `general-purpose` agent, another plugin's type, a headless `claude -p` worker, a teammate on another type, and a builder run as a Workflow stage, because the documentation does not say the hook fires for a stage) — paste the file's contents into the prompt, or open the prompt by telling the agent to read the file at its absolute path. It is short on purpose, and a one-line summary of it does not work.
- **`Explore`, `Plan` and the other built-in read-only types** — neither. They have no Agent tool, and their own instructions already cover what they do.
