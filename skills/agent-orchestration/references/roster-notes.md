# Roster notes

Three notes on the agent types this plugin ships, for the moments the roster in `SKILL.md` is not enough.

## Raising a type when the user asks

A definition fixes the role, the tools and the body; `model` and `effort` passed on the `Agent` call win over it. When the user asks for a smarter model for a piece of work, spawn the type that fits the difficulty with their model, for example `Agent({ subagent_type: 'agent-orchestration:builder-l', model: 'opus', prompt })`, and say in the brief that the user asked. Never raise one on your own judgement: when a plan marks a change as mission-critical and the user has named no model, say so in the plan and let them choose.

The same call-level `model: 'sonnet'`, with `effort: 'medium'`, gives a `reader` whose filtering needs judgement: `Agent({ subagent_type: 'agent-orchestration:reader', model: 'sonnet', effort: 'medium', prompt })`. Without the effort it keeps the definition's `max`, and `max` belongs to Haiku only, because a Sonnet reader at `high` already costs many times what a Haiku one does (the measurement is in the README's Reference).

## How a reviewer gets its work

A reviewer reads; it does not run. Write the diff to a file before the spawn (`git diff main...HEAD > <scratch>/change.diff`) and give the reviewer that path with the intent of the change. It searches the tree with the language server, Grep and Glob on its own, and loads the skills the brief names with the Skill tool: name the team's review or style skill for the files in the diff (a Python style skill, a testing skill) the same way you would for a builder.

## Why the reader and the reviewers have no MCP tools

Their allowlist cannot grant MCP tools without naming each server, and most servers carry write tools (send a message, create a page), which would break the rule that a reading stage cannot change anything. Fetch what they need from an issue tracker or a wiki yourself, field-selected, and put it in the brief. Builders have no allowlist and inherit the session's MCP tools.
