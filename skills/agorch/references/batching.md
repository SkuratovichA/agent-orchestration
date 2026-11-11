# Batching tasks into agents

Twenty tasks are four or five agents working in sequence, never twenty agents. Every start caches a whole prompt, every extra agent adds a report to read, a diff to review and a merge to settle, and an agent that stays on a line of work keeps what it learned, so its fifth task costs less than its first.

## Group before the first spawn

The plan lists every task, then groups them. Apply these in order:

1. **Tasks that touch the same files or the same module go to one agent.** Two agents on one file cost a merge; one agent doing both costs nothing.
2. **Tasks that depend on each other go to one agent, in dependency order.** B that uses what A adds is the second item of A's batch, not a second agent waiting for A.
3. **Tasks of one ticket and one pull request stay together.** A batch may carry several tickets only when the agent finishes one ticket's tasks before it starts the next, so each pull request is a clean slice of the work.
4. **Independent lines of work (different modules, no shared file) are different agents,** at most four running at once.

About five tasks per agent is where to start, not a cap. Group by line of work, not by count: an agent compacts its own context as it goes, so a long batch is fine. One agent for one task is right only when that task is large in itself, or has to run in a worktree of its own.

## One type for the whole batch

`builder-m` unless a task in the batch is mission-critical or needs long reasoning. Then that task is the batch's own: put it alone with `builder-l`, and the rest stays with `builder-m`. Never raise a whole batch because one task in it is hard.

## What the brief holds

The sections of `agorch:writing-briefs` are written once for the whole batch (scope, owned paths, side effects, output contract). The tasks come as a numbered list in the order to do them, and each task carries its own loci, acceptance criteria and proving command:

```
# Tasks, in this order
1. <what> — locus <abs path>:<line>; done when <criterion>; proof: <command>
2. <what> — depends on 1; locus ...; done when ...; proof: ...
3. ...

# Ledger
Keep a ledger at <abs path under the scratchpad>: one line per task, "<n> <status> <proving command> exit=<code>". Re-read it and this list after a compaction, before the next task.

# Report
One entry per task, in order: outcome, the evidence for its criterion, what is left. A task you did not reach is "not run" with the reason.
```

The architectural questions that can be settled before the spawn are settled in the brief, with the reason. The rest the builder brings back (below).

## When a builder stops with DECISION NEEDED

A builder that meets an architectural decision finishes every task that does not depend on it and ends its turn with a report that begins `DECISION NEEDED`: the question, two or three options with what each costs, its recommendation, and the tasks waiting. Answer it, then continue the same agent with its context intact:

```ts
SendMessage({ to: '<agent id>', message: 'Decision: option B, because <reason>. Continue with tasks 3 to 5.' })
```

- Answer from the plan, the codebase and the user's rules when they settle it. When the choice is the user's (a product behaviour, a public contract others use, a cost they carry), put it to the user with the options and the recommendation, then relay the answer.
- Answer once, in a sentence, with the reason, so the next task of the batch that runs into the same choice follows it.
- In a Workflow stage nothing can be resumed: settle the design in the stage's prompt, or split the stage at the decision.

## When builder-m could not prove a task: one step up, once

A task `builder-m` could not prove goes to `builder-l` once, alone, with the failure in its brief. That covers a proving command still red when the builder stopped, a task it reports as not done, and a correctness finding of the reviewer that you confirmed. The brief carries the task as it was, the proving command, its failure word for word, and what `builder-m` tried. The task does not go back to `builder-m`, and you do not fix it in the session.

```ts
Agent({ subagent_type: 'agorch:builder-l', prompt: `${taskBrief}\n\n# What failed under builder-m\n${proof} exit=${code}\n${failureVerbatim}\nTried: ${attempts}` })
```

- This is why `builder-m` runs at `medium`. In Anthropic's cost guide, running every checkable task at a low effort and re-running only the failures at a higher one was the cheapest policy measured: about 97% solved for $0.17 a task, against 95.3% for $0.29 with everything at `high` (Opus 5.5, SWE-bench Pro subset), and most of the lift was the second attempt itself. Sonnet 5.5 at `medium` scored about 7 points below `high` on the same set for 59% of the cost, so the first rung fails more often and the second pays it back.
- It works only where the check is real. A gate that would still pass with the change reverted proves nothing, so a green gate is not the end of the check for a task whose criterion it does not pin: the reviewer's finding is that task's check.
- One step, once. A task `builder-l` could not prove either comes back to you as a decision: re-scope it, or put it to the user, who may ask for `builder-xl`. Never raise the effort of a whole batch because one task in it failed.

## Reviewing a batch

One `agorch:reviewer` reads the whole batch, not one per task: give it the combined diff as a file, the list of tasks with their intent, and the tests that prove them. A separate review per task repeats the start and misses what the tasks do to each other. Use `reviewer-arch` only when the plan marks a task as architecture-level.
