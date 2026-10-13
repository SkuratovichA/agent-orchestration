# Workflow stages

- **No Agent tool, so the stage does its own running.** Give a stage that runs commands the `agent-orchestration:reader` type and a stage that only reads and judges the `agent-orchestration:reviewer` type; split a stage that needs both into a command stage followed by a judging one. A stage on a plugin type has that type's definition as its instructions. A stage on `general-purpose` has none of the plugin's rules, and the hook is not documented to reach a builder run as a stage: the prompt of either opens by telling it to read the worker block at its absolute path, and says in one line whether it runs commands or only reads.
- **The script cannot read files.** Pass real content through `args` or through paths the stage reads itself; a placeholder such as `"draft": "SEE_FILE"` reaches every agent literally.
- **A stalled stage is the runner's to retry, not yours to restart.** The runner retries a stalled stage on its own; if the run ends with null stages, resume it from the run id so finished agents replay from cache.
- **Schema output needs the once-at-the-end sentence** from skeleton item 9, and an "empty arrays are valid; never invent to fill a list" sentence, because the schema forces a tool call whether or not there is content.
- **No `Date.now()`, `Math.random()` or argless `new Date()`** in the script; they throw because they would break resume. Pass timestamps through `args`.

```js
const CMD = { model: 'haiku', effort: 'high', agentType: 'agent-orchestration:reader' }
const JUDGE = { model: 'sonnet', effort: 'high', agentType: 'agent-orchestration:reviewer' }
agent('Goal: say whether the suite is green, for a release gate.\nRun `cd /abs/repo || exit 1; pnpm test > /abs/scratch/t.log 2>&1; echo "exit=$?"`, then `grep -n -m 30 -A 15 -E "FAIL|Error" /abs/scratch/t.log` if it failed. Return the exit code, and for each failure the test name, expected and actual as printed, and the first stack frame in /abs/repo. Budget: 4 turns.', { ...CMD, schema: GATE })
```
