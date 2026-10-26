# Map briefs

There are two briefs: the module brief for step 2 of building and for refreshing, and the index brief for step 3. Fill in every `<...>`. Every path is absolute. The playbook is written for code that exports symbols. For a module of another kind, say in the brief what its public surface is: the commands a `bin/` directory offers, the routes of a service, or the skills and agent types of a plugin.

Contents: the module brief, the module file shape, the index brief, the index shape.

## The module brief

```text
You are the reader for one module of a codebase map. Goal: a module file that tells a planner who has never opened this module what it is for, what it offers other code and what it needs, without the planner reading its source.

Repository: <repo root>. Module: <module path>, <files> tracked files. For the module `.`, the module is the files at the repository root only. Write the result to <map dir>/modules/<slug>.md with a heredoc, overwriting the file. It is the only file you write.

First commands: `cd <repo root> || exit 1; git ls-files -- <module path> | head -200`. For `.`, use `git ls-files | grep -v / | head -200`. For a module whose slug ends in `-top`, which holds only the files directly in its directory, use `git ls-files -- ':(glob)<module path>/*' | head -200`. Then read the manifest (package.json, pyproject.toml, Cargo.toml, go.mod) and the entry points (index.*, main.*, __init__.py, mod.rs, route or handler registries), using line ranges.

Playbook:
- Public surface: what the entry points export. For each exported symbol, find who uses it outside the module. Use the LSP tool's findReferences when a server answers; otherwise `git -C <repo root> grep -lw "<symbol>" -- . ':!<module path>' | head -20`, leaving out `':!<module path>'` for the module `.`. List up to five user modules.
- Dependencies: the other modules of this repository that this module imports, found from its import lines. Name them by module path.
- Reusable helpers: functions that know nothing of this module's domain, such as formatting, parsing, retries, validation, type guards and client wrappers. Give each its path:line and a line on what it does. They matter most: they are what other modules should reuse, or what belongs in the shared package.
- Read a file over 400 lines through its outline (`grep -n -E "^(export |def |class |func |pub fn )"`), not whole.
- Read about 25 files at most. Past that, map from outlines and say so under "Not mapped".

<refresh only> The module changed since <commit>. `git diff --stat <commit> HEAD -- <module path>` shows what changed. Read the current module file first. Change only what the diff makes wrong.

Report: Answer, with the file path and its line count, then five lines:
1. the purpose;
2. whether the public surface changed (yes, no, or first build);
3. whether the dependencies changed (yes, no, or first build);
4. the two most reusable helpers;
5. what you could not resolve.
If you get stuck, report Stuck as your definition says.
```

## The module file shape

Keep a module file under 60 lines. Leave out any line that has nothing to say.

```markdown
# <module path>
<one sentence: what this module is for>

Entry points: `<path>` (<what starts there>)
Public surface: `<symbol>` (<path:line>), used by <module>, <module>
Reusable helpers: `<symbol>` (<path:line>): <what it does>
Depends on: <module> (<what for>), <module>
Used by: <module>, <module>
Data flow: <numbered steps, `path:symbol` each, only when it is not obvious>
Conventions: <only what differs from the rest of the repository>
Not mapped: <what was skipped and why>
```

## The index brief

Spawn it with `model: 'sonnet', effort: 'high'` on the reader type: writing the index is synthesis, which runs at `high`, not reconnaissance at `medium`.

```text
You are the reader that writes the index of a codebase map. Goal: <map dir>/INDEX.md, under 200 lines, which lets a planner place a change in this repository and find the code to reuse before writing any.

Inputs: <map dir>/modules.tsv and every <map dir>/modules/*.md. Read them all. Also read, with line ranges, the repository's root README, its CLAUDE.md and its workspace manifest (pnpm-workspace.yaml, the root package.json, Cargo.toml, go.work or pyproject.toml). Read source only to settle a contradiction between two module files.

Write INDEX.md with a heredoc, in the shape below. The commit on its second line is `git -C <repo root> rev-parse --short HEAD`. Report Answer, with the path and its line count, and any contradiction you could not settle.
```

## The index shape

```markdown
# <repo name>: codebase map
Commit <sha7>. Detail per module is in modules/<slug>.md. Confirm a claim in the code before relying on it.

## Layout
<three to six lines: languages, build tool, workspace layout, where tests live>

## Modules
| Module | Purpose | Main entry |
| --- | --- | --- |

## Where shared code lives
- `<path>`: <the kinds of helper it holds>, e.g. `<symbol>`, `<symbol>`
- General helpers sitting inside a feature module, which a new caller should reuse or move to the shared package: `<symbol>` (<path:line>)

## Dependencies
<module> -> <module>, <module>

## Main flows
### <flow, e.g. an HTTP request that creates an order>
1. `<path>:<symbol>`: <step>

## Conventions
<repository-wide only: error handling, logging, configuration, naming, test layout>
```

The Dependencies section has one line per module that depends on another. Main flows has three to seven flows.
