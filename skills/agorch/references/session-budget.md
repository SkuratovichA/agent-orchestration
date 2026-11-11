# Your own session's budget

These are the orchestrator's own rules, not just the workers': they bite hardest in a session that spawns nothing. Most of a large feature's cost is cache reads carrying a long session, and effort is a lever too: on Opus 5.5, `xhigh` cost about 2.5 times `high` for about one point more solved (Anthropic's cost guide, README Reference).

- Phase-scope sessions: `/clear` or `/compact` at phase boundaries (spec, implement, review, polish), well before the window limit. A compact costs one rewrite of the context and pays for itself within a few requests. Hand off through a written brief or ledger, never by dragging the whole context forward.
- Compact before an expected idle longer than the prompt cache lives, because an idle giant context expires and re-caches whole.
- Grind loops run in fresh workers: test-fix cycles, gate re-runs, any mechanical iteration over five tool calls. A fat-session request pays for reading the whole context before generating anything, while a fresh worker pays a small fraction of that.
- Never Read a 50KB+ agent report back into a fat session, and never take a raw MCP dump. Agents return summaries; issue-tracker and wiki data come through field-selected requests.
- Batch independent tool calls into one request: every avoided request at fat context saves a full re-read of that context.
- Change `/effort` or `/model` only at a phase boundary, right after `/clear` or a compaction: a top-level effort change rewrites the whole prompt cache, 81,000 tokens in Anthropic's measurement. An `effort` on a spawn call breaks nothing here, because every agent caches its own prompt.
- A healthy agent loop reads most of its input from the cache: Anthropic's median is 84%, and below about 80% something breaks the cache, such as text added at the front of the prompt, a tool or the system prompt changed mid-session, or an effort change.
