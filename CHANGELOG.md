# Changelog

## 1.0.0 (2026-11-02)

First public release, after a month of daily use.

### Routing
- Always-on routing: Opus decides per task whether to keep it or delegate it to `haiku-scout`, `haiku-worker`, `sonnet-worker` or `roblox-worker`.
- Read-only work goes to Haiku first; tiny and hard work stays with Opus.
- Overrides: `!haiku`, `!sonnet`, `!opus`, `!noroute`, `!route`.
- Split, batch and parallel delegation for mixed or repeated work.

### Workers
- Fixed report format: `STATUS`, `CONFIDENCE`, `PARTIAL-WHY`, `UNSURE`, `CHANGED`, `NEEDS-OPUS`.
- Opus checks results by confidence and only redoes work that's wrong at its core.
- `haiku-worker` runs at medium effort; `roblox-worker` runs Sonnet at high effort with a 70-turn limit and a turn budget.
- Roblox work is briefed one script, feature or test scenario at a time; an incomplete Roblox run goes back to `roblox-worker` as a new brief.

### Safety
- Worker guard blocks deleting, git push/reset/clean, publishing, sending and system changes.
- Luau guard blocks destroying instances, data store writes, network calls and publishing in `execute_luau`.
- Brief template enforced by a hook.

### Stats
- `/route-stats` with gross and net savings. Net subtracts only the extra Opus cost of delegated turns over kept turns.
- Background workers' reports are read from their hand-back message.
- Unknown worker status is counted separately, never as a failure.
- Partials record a reason (`incomplete`, `blocked`, `wrong`); partials that Opus finishes are logged as `◐`.

### Removed during the first month
- Automatic "weak spots" (moving a task type up a tier after failures). Partial results were too often counted as failures and pushed work to Opus.

## Learned rules

Rules learned from corrections are appended below. To record new ones automatically, set `changelog_path` in `router/config.json` to this file's path.

- 2026-10-21: learned rule: plugin/mod tests -> sonnet-worker
- 2026-10-21: learned rule: several small mechanical steps in a row (file syncs, folder copies) -> batch them into one haiku-worker brief instead of doing them yourself
- 2026-10-21: learned rule: web page text/HTML extraction → haiku-scout, not opus
- 2026-10-21: learned rule: bundling/merging static pages into one self-contained HTML → sonnet-worker (confirmed good)
- 2026-10-21: learned rule: quick fact-checks / single-page lookups (e.g. verifying a rate or price) → haiku-scout, not opus
- 2026-10-21: learned rule: research → split it: haiku-scout gathers and extracts the sources, Opus writes the conclusion (not sonnet-worker end to end)
- 2026-10-23: learned rule: /graphify --update (scripted incremental runs) → haiku-worker; full /graphify builds (community naming) → sonnet-worker, not opus
- 2026-10-23: learned rule: lookups that need judgment across several sources → sonnet-worker; haiku-scout only for single-page extraction, reading known files, and gathering sources without judging them. In a research split, write haiku-scout's DONE WHEN as "sources gathered and extracted", so gathering alone counts as done
- 2026-10-31: learned rule: fake test-data/fixture generators with an exact spec and a substring-check done condition → haiku-worker, not sonnet
