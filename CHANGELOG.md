# Changelog

## 1.1.0 (2026-11-05)

### Your model requests vs the router's own picks
- When you ask for a model (`!sonnet`, or in words: "let Sonnet do it", "do it yourself"), Opus follows it and also records what it would have picked on its own: `route: sonnet ✓ · asked sonnet · auto opus`.
- Asked = auto is not counted as an override. Asked ≠ auto is a real override, a signal that the automatic routing was wrong for that kind of task, and Opus adds a learned rule when it points to a general pattern.
- Prompts that only talk about a model or the router are not treated as requests.
- `/route-stats` has a new "Your model requests" section: how many matched the router's pick, plus a table of real overrides by task type.
- "Overrides" in `/route-stats` is renamed "Prefix commands".

### Rules
- The build-list rule now sends wiring code from an integration doc, and doc edits that need writing or reading code, to sonnet-worker (Haiku kept failing on them).
- New: test-suite runs whose results need interpreting go to sonnet-worker.
- 3 more rules learned from use (see below).

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
- 2026-11-02: learned rule: small build-list items (popups, CSS fixes, wiring from an integration doc, renames, status updates) → haiku-worker, one item per brief, not sonnet
- 2026-11-02: learned rule: don't hold back work that only partly conflicts with a running worker: start the safe part now, list the rest for after it
- 2026-11-03: learned rule: /graphify --update with changed docs/images needs sub-agent dispatch → Opus orchestrates (haiku-worker can't); code-only updates can stay on haiku-worker
- 2026-11-05: learned rule: read-only debugging checks (folder listings, process lists, event logs) → haiku-scout; mechanical plan-file edits with an exact spec → haiku-worker
- 2026-11-05: changed rule: small build-list items with an exact spec → haiku-worker; wiring code from an integration doc, and doc edits that need writing or reading code → sonnet-worker (replaces the 2026-11-02 build-list rule)
- 2026-11-05: learned rule: test-suite runs whose results need interpreting → sonnet-worker, not haiku-worker
