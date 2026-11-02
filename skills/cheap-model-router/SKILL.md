---
name: cheap-model-router
description: Always-on routing of easy work to cheaper models. Before doing any task, decide whether Opus keeps it or it goes to haiku-scout, haiku-worker or sonnet-worker, then delegate, check the result by confidence, and log the route. Loaded automatically at session start by a hook.
---

# Cheap model router (always on)

The user installed this skill and explicitly wants easy work delegated to the worker agents below, so delegating to them is authorized. Goal: spare Opus for hard work without losing quality or burning tokens twice.

## Workers
| Agent | Model | Can | Use for (TYPE) |
|---|---|---|---|
| `haiku-scout` | Haiku | read, search, web | search, lookup, read-summarize |
| `haiku-worker` | Haiku | edit, run commands | mechanical-edit, format-convert, shell-run, boilerplate, translate |
| `sonnet-worker` | Sonnet | edit, run, web | write-code, bugfix, tests, refactor-small, docs, research, data-wrangling |
| `roblox-worker` | Sonnet | Roblox Studio: read/grep/edit scripts, game tree, run Luau, console, play tests | roblox-script, roblox-bugfix, roblox-test, roblox-inspect |

Workers can't delete, push, publish, send or change system settings (a hook blocks it). `roblox-worker` also can't destroy instances, write data stores, use the network or publish from `execute_luau`, and has no asset upload, insert or generation tools. They report those under NEEDS-OPUS.

Roblox Studio work with a clear scope goes to `roblox-worker`. Keep each brief to one script, feature or test scenario; for bigger work, send several briefs one after another. If it comes back `partial` / `incomplete`, send the remaining part as a new roblox-worker brief instead of finishing it yourself (this is the one exception to "never re-send to a cheap model"). The other workers have no Studio tools. Opus keeps game design, unclear bugs and anything that changes many systems at once.

## Decide (in this order)
1. **Override prefix** from the user (`!haiku`, `!sonnet`, `!opus`): the prompt hook tells you; obey it. `!noroute`: do everything yourself, no route lines.
2. **Read-only → Haiku first.** Any lookup, search, file read, page fetch or extraction that you can't answer from what's already in context goes to `haiku-scout`, even if you could do it in 2–3 tool calls. Keep it yourself only if it's a single read of a file you already know, or if the reading needs the conversation's context to interpret.
3. **Tiny → Opus does it.** Other work (edits, commands) that takes about 2 quick tool calls, or where the brief would be longer than the work: just do it. Pure conversation is not routed.
4. **Hard → Opus keeps it:** design or architecture, unclear root cause, large or cross-cutting refactors, security-sensitive work, ambiguous requests that need clarifying, judgment calls, or work that leans on so much conversation context that briefing it would take more than ~15 lines.
5. **Otherwise delegate.** Opus is the default only when the fit is unclear. Between Haiku and Sonnet, pick Haiku whenever the task is mechanical with an exact pattern and a checkable done condition. Pick Sonnet when it needs real reasoning about code.
6. Check the **learned rules** injected at session start; they override the lanes above.

## Delegate
- Before the Agent call, show one line: `→ Haiku · <task in a few words>` (or `→ Sonnet · …`).
- Call the Agent tool with `subagent_type` set to the worker. Don't pass `model`; the agent file sets it.
- The brief must use this template. A hook rejects briefs without TASK, TYPE and DONE WHEN:

```
TASK: <one line>
TYPE: <one TYPE from the table>
CONTEXT: <file paths, key facts, conventions. Paths, not pasted contents.>
DO: <steps or spec, short>
DON'T: <scope limits>
DONE WHEN: <a checkable condition>
```

Keep briefs short. Your output tokens are the most expensive ones in this setup.

## Split, batch, parallel
- **Split** a mixed task only when the mechanical part is big (about 5+ files or many similar edits): Opus decides the design, `sonnet-worker` implements the core, `haiku-worker` does the bulk mechanical edits. If the mechanical part is small, don't split; do it in one place.
- **Batch:** several small independent tasks of the same lane go in one brief as a numbered list to one worker.
- **Parallel:** independent tasks that touch different files go to several workers in a single message. Never two writers on the same file.

## Check by confidence (never redo by default)
- `STATUS: done` + `CONFIDENCE: high` → **light check:** look at the diff or changed region, or run the quick test once. For answers, a plausibility check. Then report.
- `CONFIDENCE: low` → **deeper check, focused on the UNSURE points only.** Fix small problems yourself in place. Don't re-read or redo the parts that are fine.
- **Redo only if the result is wrong at its core.**
- `PARTIAL-WHY: incomplete` → keep what's there and finish the rest yourself. `blocked` → do the blocked step (see NEEDS-OPUS). `wrong` → treat it like failed.
- `STATUS: failed`, or `partial` with the core wrong → **Opus takes over directly.** Never send the same task to another cheap model. Reuse whatever the worker found; don't start from zero.
- NEEDS-OPUS items (delete, push, send, etc.): do them yourself, and confirm with the user first when they're hard to reverse or outward-facing.

## Log the route (a hook reads it)
On every turn that did a task, make the **last line of your final message** the route, in backticks:
- `` `route: opus` ``, kept or tiny
- `` `route: haiku ✓` `` or `` `route: sonnet ✓` ``
- `` `route: haiku ✗ → opus` ``, escalated (failed or wrong, Opus redid the core)
- `` `route: sonnet ◐ → opus` ``, partial: the worker's part was kept and Opus finished the rest. Use this whenever you complete a partial result yourself, so it's counted.
- `` `route: opus+sonnet+haiku ✓` ``, split
- `` `route: 3×haiku ✓` ``, parallel or batch

When the user corrects a routing choice ("that could've gone to Haiku", "do this kind yourself", or they used an override because you routed wrong), add a line right above the route line:
`` `route-feedback: <short general rule, e.g. "regex-heavy edits → sonnet, not haiku">` ``
The hook saves it to the learned rules, and they're loaded every session.

## Commands
- `/route-stats`: share of work per model, escalations, failures per task type, tokens and estimated savings.
- Data lives in `~/.claude/router/` (`log.jsonl`, `feedback.md`, `config.json` with prices).
