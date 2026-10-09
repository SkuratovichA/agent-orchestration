---
name: agent-orchestration
description: Use when spawning a subagent or workflow stage, picking its model or effort, writing a worker brief or implementation plan, fanning out reviews or verification, or deciding what context a stage gets.
---

## Model and effort per stage

| Stage kind | Model | Effort |
| --- | --- | --- |
| Real work — implementation, review, synthesis, critic, anything with judgement in it | `sonnet` — the default for every spawned agent. `opus` stays reserved for the main/orchestrator session — use it for a spawned agent only when the user asks for that agent to be raised | `high` |
| A purely mechanical stage that only shuttles or reformats text, with no judgement in it | `haiku` / `sonnet` — `opus` is waste | `low` |
| Mechanical retrieval — locate-a-link hunts, search-and-report sweeps (code host, chat, wiki, package registries), any schema-constrained "go find X and list it" | `sonnet`, not `opus` | `low` |
| Any terminal command at all — the hard rule. `grep`, `git log`, `git commit`, a test run, a log to characterise; no exception for small commands, and the same rule goes verbatim into every prompt you write | `haiku` (`sonnet` when reading the output needs judgement) | `high` |
| Probes and trivial checks — a probe on `opus` costs more than on `haiku` | `haiku` | `low` |
| `fable` | only when it is asked for explicitly, by name, in that request | — |

- **Name a model by its alias, never by a version.** `haiku`, `sonnet`, `opus` and `fable` resolve to the latest model of their family, so every spawn uses the latest Haiku and the latest Sonnet unless the user names a version. No version number goes into a spawn call, an agent definition or a brief, and this plugin needs no edit when a new version ships.
- Agents doing real work must be smart — don't send a weak model to do engineering; `sonnet` is the floor for that, not `haiku`.
- `opus` is reserved for the main/orchestrator session, not spawned agents, from now on — unless the user asks for a specific agent to run on `opus`, or the stage is an architectural review through `agent-orchestration:reviewer-arch`.
- `fable` is NOT a default and NOT a fallback. If the requested model is unavailable for a call, say so — don't silently swap in another model.
- Effort: the session runs at whatever the user set; every `Workflow` stage is pinned at `effort: 'high'` (`low` for the mechanical stages above). The `Agent` tool takes `model` and `effort` on the call (verified on Claude Code 2.1.296, 2026-10-10), and a spawn that names neither inherits the session's: spawn a plugin type, whose definition pins both, or pass them. A `haiku` agent runs at `high`, the level that suits strict instruction following, and drops to `low` only for a probe or another short, simple request, because at `low` it is more likely to skip a check or stop early. Raise a specific agent above `high` (`xhigh`) only through an agent type that pins it (`builder-l`, `reviewer`) or when the user asks for that agent to be raised.
- Corollary for subagents themselves: a subagent does the task it was given and reports back. If it decides the task needs a fan-out, it can't spawn a smarter model — the communication is performed in report manner. The one exception is retrieval: a worker may spawn `haiku`/`sonnet` retrieval subagents rather than grepping for itself.
- Keep `sonnet` for the synthesis/critic/review stages that read the cheap stages' merged output — `opus` is reserved for the main session, not spawned for this either, unless asked. In workflow scripts pin this structurally instead of relying on inheritance:

  ```js
  const SMART = { model: 'sonnet', effort: 'high' };  // judgement: review, synthesis, critic
  const CHEAP = { model: 'sonnet', effort: 'low' };   // mechanical: locate, sweep, reformat
  agent(`find the design mocks ...`, { ...CHEAP, schema: HITS });
  agent(`synthesize the findings ...`, { ...SMART, schema: REPORT });
  ```

## The agent types this plugin ships

Spawn these instead of `general-purpose` when the stage fits. Model and effort are pinned in each definition, so nothing is inherited from the session by accident.

| Agent type | Model, effort | Spawn it for |
| --- | --- | --- |
| `agent-orchestration:reader` | `haiku`, `high` | every terminal command and every lookup: given a goal, the first commands and what it may do next, it follows the lead over several steps and returns the answer, or exactly where it got stuck |
| `agent-orchestration:builder-m` | `sonnet`, `medium` | the default implementer: any change whose brief leaves no design question open |
| `agent-orchestration:builder-l` | `sonnet`, `xhigh` | an implementation whose difficulty is in the design: several modules, a migration, concurrency or state, a contract other code depends on |
| `agent-orchestration:reviewer` | `sonnet`, `xhigh` | review of a diff for correctness, reuse, tests and style; read-only |
| `agent-orchestration:reviewer-arch` | `opus`, `high` | architectural review, only when the user asks for it or the plan marks the change as architecture-level; read-only |

- **Judge the difficulty before you spawn an implementer**, and say which one you chose and why in a clause. `builder-m` is the default: the brief leaves no design question open. If the worker would still have to decide how modules, data or concurrent actors fit together, it is `builder-l`. When you cannot tell, split the task until each part is a `builder-m` task.
- `opus` is spawned only through `reviewer-arch`, or when the user names it for a specific agent. A code review is `reviewer`; an architectural one asks what the change does to code that lives somewhere else, and that is the question worth the stronger model.
- **The user can raise any type.** A definition fixes the role, the tools and the body; `model` and `effort` passed on the `Agent` call win over it. When the user asks for a smarter model for a piece of work, spawn the type that fits the difficulty with their model, for example `Agent({ subagent_type: 'agent-orchestration:builder-l', model: 'opus', prompt })`, and say in the brief that the user asked. Never raise one on your own judgement: when a plan marks a change as mission-critical and the user has named no model, say so in the plan and let them choose. The same call-level `model: 'sonnet'` gives a `reader` whose filtering needs judgement.
- A subagent can spawn subagents of its own, up to three layers below the main conversation by default (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` changes that). The builders and the reviewers use it for `reader` only; `reader` has no Agent tool and is the end of the chain.

## Language servers

Builders navigate with the `LSP` tool and treat the diagnostics that arrive after an edit as their first gate, which is why `builder-m` at `medium` is enough for most work. A language server needs its plugin enabled and its binary on PATH. `references/language-servers.tsv` lists, per project marker file, the language, the plugin, the binary and the install command. The plugin's SessionStart check (`hooks/lsp-check.sh`) adds one line to the session when the working directory has a marker and the binary is missing; it never installs anything. When that line appears, tell the user before the first builder spawn and install only on their go-ahead.

## You are responsible for the output of anyone dumber than you

If you spawn a model weaker than yourself (e.g. you are Fable and you spawn Opus), you MUST review what it produced — read the diff, check the reasoning, verify the tests actually pin the bug — before merging or reporting it as done. Never relay a subagent's claim as fact without checking it.

## Division of labour

- The smarter model does the research and writes the implementation plan; the spawned agent implements it, runs the tests, and opens the PR.
- Don't hand an agent a vague goal and hope — hand it a verified fix locus (file:line), the constraints, the acceptance criteria, and the verification commands.
- Give every agent the hard project rules explicitly: no `any`, reuse existing code instead of re-writing it, invest into code de-duplication, use local claude.md instructions, no attribution to the assistant in commits/PRs, one PR per task, don't self-merge unless told.
- Name the skills that govern the worker's files in the brief (a testing skill, a language style skill, …) and never restate them — the worker loads them itself, the brief stays short, and a restated skill is a stale one.
- When an installed plugin offers an agent type that preloads those skills (its `skills:` frontmatter — e.g. `<plugin>:python-implementer`), spawn that type instead of `general-purpose`, in `Agent` calls and as a workflow stage's `agentType` alike: the skill body is then in the worker's context before its first token, whatever the brief says. Verified on Claude Code 2.1.278 for both spawn paths.

## Writing the brief itself

Load `agent-orchestration:writing-briefs` before writing the prompt for any spawned agent or Workflow stage, once this skill has fixed the model and effort. It carries the brief skeleton (verified loci, inlined context, scope as the deliverable, authorised side effects, the proving command per claim, the output contract, the budget as a stop condition, the autonomy block), the per-model sentences for Sonnet, Haiku, Opus and Fable, the resolution of every place the prompting docs disagree with the house rules, the Workflow-stage rules, and how to treat a report when it comes back. It names this skill's model table, retrieval rules, budgets and verification shapes instead of repeating them; `references/brief-templates.md` holds the paste-able blocks and three filled-in briefs.

## Plan first; implementation never starts in the planning session

For any multi-file task the smart model writes the implementation plan — loci (file:line), constraints, acceptance criteria, verification commands — and shows it to the user BEFORE implementation tokens burn. The approved plan becomes the worker brief; fresh 40–100K worker contexts implement it. A brief-driven worker ships a verified change for a fraction of what a worker that explores and iterates costs.

## Feed each stage the minimum; extract shared inputs once

- Parallel or sequential agents must not each re-read the same big artifact (a generated `schema.ts`, a 190KB source file). The orchestrator reads/greps it ONCE and inlines the needed slice into each prompt.
- Per stage: review lenses get the diff + the target functions, not the whole file; verify agents get the finding loci (file:line) + the verification commands, not the implementation context.
- Never `fork` from a session above ~100K tokens — a fork cache-writes the entire parent context before doing any work. Spawn a fresh agent with a written brief instead.

## Verification fan-outs are capped and staged

Cap findings before verifying (`review.findings.slice(0, 5)`), and never run byte-identical duplicate skeptics in parallel — sampling noise is not verification. Run one skeptic; spend a second only on findings the first FAILED to refute:

```js
const v1 = await agent(refute(f), { ...SMART, schema: VERDICT });
const v2 = v1.refuted ? null : await agent(refute(f), { ...SMART, schema: VERDICT });
const survives = !v1.refuted && v2 && !v2.refuted;
```

## Cheap swarms are for grounded breadth; judgment stays smart

- A wide `sonnet`/`haiku` fan-out is right when every claim can carry its own evidence — file:line, a verbatim quote, a command that proves it (call-site sweeps, checklist audits, per-file conformance checks, log characterization).
- It is wrong for subtle analysis: one smart-model read beats ten cheap ones.
- Anti-hallucination machinery that verifiably works: schema output with "empty is a valid answer — never invent to fill a quota", verbatim-evidence fields re-checked at verify time, refute-by-default skeptics (the staged v1/v2 above — cheap v1 first).
- Prefer deterministic checks (a test run cannot hallucinate) over any model vote; stop fan-outs on marginal yield (2 dry rounds), never at a fixed headcount.
- NO chatty multi-turn mutual checking between agents — it multiplies boot cost (the swarm's real cost floor) without adding ground truth.
- Shape: find (cheap, evidence-carrying) → verify (staged skeptics) → synthesize (smart), as a DAG.

## Your own session's budget

These are the orchestrator's own rules, not just the workers' — they bite hardest in a session that spawns nothing. Most of a large feature's cost is cache reads carrying long sessions, not output. Max effort is cheap; context logistics are not.

- Phase-scope sessions: `/clear` or `/compact` at phase boundaries (spec → implement → review → polish), at ~150–200K rather than at the window limit — a compact costs one rewrite of the context and pays for itself within a few requests.
- Compact BEFORE an expected idle over an hour: cache TTL is one hour, and an idle giant context expires and re-caches whole.
- Grind loops run in fresh workers: a fat-session request pays for reading the whole context before generating anything, while a fresh worker at 40–100K pays a small fraction of that.
- Never Read a 50KB+ agent report back into a fat session, and never take a raw MCP dump.
- Batch independent tool calls into one request: every avoided request at fat context saves a full re-read of that context.
- The plugin's `PreToolUse` hook refuses once, in the main conversation only, a Bash command whose text does not bound its output (no stdout to a file, no final `head`, `tail`, `wc` or `grep -c`). Give the goal and the command to a `reader`, or bound it; the same command sent again unchanged runs, which is for the command you are certain prints a few lines. A subagent's Bash is never refused.

The full block, with the worker-facing rules alongside these, is in `references/worker-brief-block.md`.

## The hygiene block every spawned agent gets

`references/worker-brief-block.md` (next to this file) holds the bash-output and context hygiene rules, the "worker agents do not do their own retrieval" rules including the 40 tool calls / 150K context budget, the session and context budget hygiene rules, and the load-the-governing-skill rule. This directory is also a plugin (`.claude-plugin/plugin.json`), and its `SubagentStart` hook (`hooks/context.sh`) puts that file into the context of every agent the session spawns — `Agent` tool and `Workflow` stages alike, verified on Claude Code 2.1.278 — so a brief does not paste it and the orchestrator stops carrying a 7KB copy per spawn. The proof that the hook is running is the session-start line "The agent-orchestration plugin is active". Without that line (no `jq`, the plugin disabled, a `claude -p` worker on another machine, another harness), paste the file's contents VERBATIM into every spawned agent's prompt. A one-line summary does not work.
