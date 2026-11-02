# Turn limits

A turn limit is a runaway stop that you can move, not a budget. The builders have none: one builder works a batch of tasks in sequence, which takes many turns, and it compacts its own context at 200K tokens (`autoCompactWindow` in its definition). The reader and the reviewers have a limit far above ordinary runs, so a run that reaches it is stuck or badly scoped; the measurement behind the numbers is in the README, under "Where the turn limits come from". The roster in `SKILL.md` shows the limits and `references/turn-limits.tsv` at the plugin root holds them (`none` means no limit).

The plugin's hook (`hooks/turn-budget.sh`) counts the tool rounds of a run that has a limit, adds one factual note to the agent's context at 75% of the limit and one at the limit, and from then on refuses the run's tool calls with a reason, so the run ends with a report of what is done and what is left. The `agent-turns` command, on your Bash tool's PATH while the plugin is enabled, reads and moves the limit at any moment, and gives a builder one when you want a stop for a run that looks stuck. A change applies from the run's next tool call, and a run refused at its limit carries on once you raise the limit and resume it with `SendMessage`, its context intact:

```sh
agent-turns                        # every run of this session: rounds, limit, and whether the limit is the run's, the session's or the default
agent-turns <agent-id> 720         # one run's limit, where <agent-id> is the id the Agent call returned; `default` removes it
agent-turns --type builder-m 720   # this session's limit for a type, for its running and later runs that have no limit of their own
```

A run with no limit is not counted and has no row in the list, so a limit given to it counts rounds from the moment it is set.

Every type's `maxTurns` is Claude Code's own hard stop, which no command moves and which is read only when the session starts: 10000 for the builders, 1000 for the others. A run cut there comes back marked partial and resumes with `SendMessage` the same way; the README's Reference says from which Claude Code version.

No definition and no brief states a turn number, because a model told a tight budget may decline the task, scope it down or stop early. A brief sizes the task instead (`agent-orchestration:writing-briefs`, item 11). When a report says the limit was reached and little is left, raise the limit and resume; when much is left, re-scope and spawn again.
