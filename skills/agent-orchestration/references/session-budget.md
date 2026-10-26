# Your own session's budget

These are the orchestrator's own rules, not just the workers': they bite hardest in a session that spawns nothing. Most of a large feature's cost is cache reads carrying a long session, not output. Max effort is cheap; context logistics are not.

- Phase-scope sessions: `/clear` or `/compact` at phase boundaries (spec, implement, review, polish), well before the window limit. A compact costs one rewrite of the context and pays for itself within a few requests. Hand off through a written brief or ledger, never by dragging the whole context forward.
- Compact before an expected idle longer than the prompt cache lives, because an idle giant context expires and re-caches whole.
- Grind loops run in fresh workers: test-fix cycles, gate re-runs, any mechanical iteration over five tool calls. A fat-session request pays for reading the whole context before generating anything, while a fresh worker pays a small fraction of that.
- Never Read a 50KB+ agent report back into a fat session, and never take a raw MCP dump. Agents return summaries; issue-tracker and wiki data come through field-selected requests.
- Batch independent tool calls into one request: every avoided request at fat context saves a full re-read of that context.
