---
name: mapping-codebases
description: Use before planning or briefing a change in a repository whose layout the session does not know yet, when the SessionStart line says a codebase map exists or has gone stale, or when deciding where new code belongs. It reads, refreshes or builds a per-repository map of modules, shared helpers, dependencies and main flows that cheap readers write once and later sessions reuse.
---

# Mapping codebases

Someone who knows a codebase carries a map of it: which module does what, where the shared helpers live, who calls whom, how a request travels through it. A session starts without that map. A builder briefed without it writes the helper that already exists two packages away, or keeps a general one inside the feature where nobody else will find it. This skill keeps the map on disk, outside the repository, so cheap readers write it once and every later session and worktree reuses it.

The map is a lead, not proof. Before a plan or a brief relies on something the map says, confirm it with the language server or one grep. When the code disagrees, the code wins and that module is due for a refresh.

## Where it lives

`codebase-map dir` creates the directory and prints it. The command is on the Bash tool's PATH while the plugin is enabled. The directory is `${XDG_CACHE_HOME:-~/.cache}/agent-orchestration/maps/<repo>-<key>/`: one per repository, shared by its worktrees, never inside the tree and never committed.

| File | Holds | Written by |
| --- | --- | --- |
| `INDEX.md` | the whole repository in under 200 lines: layout, a module table, where shared code lives, module dependencies, the main flows, conventions | one index reader |
| `modules/<slug>.md` | one module: purpose, entry points, public surface and its users, reusable helpers, dependencies, data flow | one reader per module |
| `modules.tsv` | `path<TAB>slug<TAB>files`, the module list | `codebase-map modules`, then corrected by you |
| `commit` | the commit the map describes | `codebase-map stamp` |

## Reading it

Most sessions only read the map.

1. Run `codebase-map status`. It says when the map was built, how many commits behind it is, and which modules changed since.
2. Read `INDEX.md` before you write the plan. Open a module file only for a module the task touches.
3. Put what each builder needs into its brief as resolved context, the way `agent-orchestration:writing-briefs` says: the helpers to reuse with their paths, the shared package a new helper goes to, and the callers a change reaches. Builders are not sent to read the map.
4. If `status` lists a module the task touches under `refresh`, refresh that module before the plan relies on it.

## Building it

Build the map when there is none and the work spans more than one module, or more than one change in this repository. A repository small enough to read whole in a few tool calls needs no map. Building runs without asking; tell the user in one line that it is happening.

1. Propose the modules with `d=$(codebase-map dir) && codebase-map modules > "$d/modules.tsv"`. Then read the TSV and correct it by hand:
   - keep a module of a few files as its own line, but give several such modules to one reader in step 2;
   - split a module past about 300 files with a smaller limit (`codebase-map modules 60`) and keep its lines;
   - drop generated and vendored trees.
   Five to forty modules is the range that works.
2. Map each module with one `agent-orchestration:reader`, at most four at a time, using the module brief in `references/map-briefs.md` next to this file (`${CLAUDE_SKILL_DIR}/references/map-briefs.md`). A reader may take several small modules, writing one file for each. Each reader writes its own `modules/<slug>.md` files and returns five lines per module. Nothing else from its reading reaches this conversation.
3. Write the index with one `agent-orchestration:reader` called with `model: 'sonnet', effort: 'high'`, because it is synthesis rather than reconnaissance, using the index brief from the same file. It reads every module file and writes `INDEX.md`.
4. Run `codebase-map stamp`.
5. Read `INDEX.md` once. Check three of its claims against the code with the language server or grep. If a claim is wrong, send its module back to step 2.

## Refreshing it

When `status` lists modules under `refresh`, run step 2 for those modules only, adding the refresh line from the module brief.

- If a reader's summary says the module's public surface or its dependencies changed, run step 3 again.
- Otherwise leave `INDEX.md` alone.

Then run `codebase-map stamp`. Rebuild from step 1 instead when any of these holds:
- `status` says the repository does not have the build commit;
- more than half of the modules changed;
- the `unmapped` count is files in a new top-level directory.

## Where new code goes

The plan names a home for every new helper, and `INDEX.md`'s "Where shared code lives" section is where that home comes from:
- A helper that knows nothing of the feature it serves goes to the shared package listed there, if another module could call it as written.
- A helper that uses the feature's own types or rules stays with the feature.

A builder puts a helper only where its brief lets it write, so the brief lists that shared package among the builder's paths. The builders and the reviewer apply the same rule on their side.
