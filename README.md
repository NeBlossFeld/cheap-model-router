# Cheap Model Router for Claude Code

Keep Opus as your main model, but stop paying Opus prices for easy work.

Before every task, Opus decides whether to do it itself or hand it to a cheaper worker: **Haiku** for lookups and mechanical edits, **Sonnet** for standard coding. It checks the worker's result by how confident the worker says it is, logs every route, and learns from your corrections.

> In its first month of real use: 144 worker runs, $64 gross / $18 net estimated savings, and only 1% of turns escalated back to Opus.

## How it decides

| Step | Rule |
|---|---|
| 1 | You can force a model on any message: `!haiku`, `!sonnet`, `!opus`. `!noroute` turns routing off for the session, `!route` turns it back on. |
| 2 | **Read-only work goes to Haiku first:** lookups, searches, file reads, page extraction. |
| 3 | **Tiny work stays with Opus:** if the brief would be longer than the work, it just does it. |
| 4 | **Hard work stays with Opus:** design, unclear bugs, big refactors, security, anything that needs a lot of conversation context. |
| 5 | **Everything else is delegated:** Haiku when it's mechanical with an exact pattern, Sonnet when it needs real reasoning about code. |
| 6 | **Learned rules override all of the above.** They come from your own corrections. |

You see each decision as a line like `→ Haiku · rename vars in 3 files`, and every task reply ends with a `route:` line.

**When you ask for a model yourself**, Opus follows it and also records what it would have picked on its own: `route: sonnet ✓ · asked sonnet · auto opus`. If both match, nothing changes. If they differ, it's a real override: the routing was wrong for that kind of task, and it can become a learned rule.

## The workers

| Agent | Model | Can | For |
|---|---|---|---|
| `haiku-scout` | Haiku | read, search, web | search, lookup, summaries |
| `haiku-worker` | Haiku (medium effort) | edit, run commands | mechanical edits, formatting, boilerplate, known commands |
| `sonnet-worker` | Sonnet | edit, run, web | code, bug fixes, tests, docs, research |
| `roblox-worker` *(optional)* | Sonnet (high effort) | Roblox Studio MCP: scripts, game tree, Luau, console, play tests | Roblox scripting and testing |

Every worker ends with a fixed report (`STATUS`, `CONFIDENCE`, `PARTIAL-WHY`, `UNSURE`, `CHANGED`, `NEEDS-OPUS`). Opus does a light check on high-confidence results and a focused check on the points flagged as uncertain. It only redoes work that's wrong at its core, and never sends a failed task to another cheap model.

## Safety

- **Workers can't delete files, push, publish, send messages or change system settings.** A PowerShell hook blocks those commands, and the worker lists them under `NEEDS-OPUS` for Opus to handle (with your confirmation when it matters).
- **`roblox-worker` has its own Luau guard.** Its `execute_luau` calls can't destroy instances, write data stores, use the network or publish, and it has no asset upload, insert or generation tools.
- **Worker briefs must follow a template** (TASK, TYPE, DONE WHEN). A hook rejects briefs that don't.

## Stats and learning

- **`/route-stats [days]`** shows the share of work per model, partials and escalations, failures per task type, tokens, and both gross and net estimated savings. Net savings subtract the extra Opus cost of briefing and checking. It also lists your model requests and which of them were real overrides.
- **Learned rules:** when you correct a routing choice, Opus writes a `route-feedback:` line and a hook saves it to `~/.claude/router/feedback.md`. That file is loaded at every session start. The repo ships with 14 rules learned during real use.
- **Changelog of rules:** set `changelog_path` in `~/.claude/router/config.json` to a `CHANGELOG.md` (e.g. this repo's), and every newly learned rule is appended to it.

## Requirements

- **Windows with Windows PowerShell 5.1** (built in). The hooks are PowerShell scripts. On macOS or Linux, install PowerShell 7 (`pwsh`) and change `powershell.exe` to `pwsh` in the hook commands, or ask Claude to port the scripts.
- **A recent Claude Code** that supports `command` + `args` hooks and agent `effort` / `maxTurns`.
- **Optional:** the Roblox Studio MCP for `roblox-worker`.

## Install

**Option A, the script.** Clone the repo:

```
git clone https://github.com/NeBlossFeld/cheap-model-router.git
```

Then, from the repo folder:

```
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
```

Add `-NoRoblox` to skip the Roblox worker. The script:
- copies the files into `~/.claude`, backing up any file it replaces as `.bak-<time>`;
- merges the hooks into `settings.json` without touching your other settings;
- adds one line to `CLAUDE.md`;
- runs a self-test.

Your existing `config.json` and learned rules are never overwritten, so re-running it is a safe update. Then **start a new Claude Code session**.

**Option B, ask Claude.** Open Claude Code in this folder and say: *"Install this repo's router per the README, merging the hooks into my settings.json."*

### Optional: Firecrawl for haiku-scout

If you have the Firecrawl MCP, add its tools to the `tools:` line in `~/.claude/agents/haiku-scout.md`. The names contain your MCP server id, so check them in Claude Code: `mcp__<server>__firecrawl_scrape` and `mcp__<server>__firecrawl_search`.

## Data

Everything lives in `~/.claude/router/`:
- `log.jsonl`: every route and worker run.
- `feedback.md`: your learned rules.
- `config.json`: model prices for the savings estimate and the list of workers.

Prices were checked on 2026-10-20; update them if they change.

## Uninstall

1. Delete the four `agents/*-worker.md` / `haiku-scout.md` files, the two skill folders and `~/.claude/router`.
2. Remove the router's 5 hook entries (`session-start`, `prompt-submit`, `pre-agent`, `subagent-stop`, `turn-stop`) from `settings.json`.
3. Remove the routing line from `CLAUDE.md`.

## License

MIT
