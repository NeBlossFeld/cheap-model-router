# Learned routing rules
<!-- Added automatically from `route-feedback:` lines. Edit or delete freely. -->
- plugin/mod tests -> sonnet-worker  (2026-10-21)
- several small mechanical steps in a row (file syncs, folder copies) -> batch them into one haiku-worker brief instead of doing them yourself  (2026-10-21)
- web page text/HTML extraction → haiku-scout, not opus  (2026-10-21)
- bundling/merging static pages into one self-contained HTML → sonnet-worker (confirmed good)  (2026-10-21)
- quick fact-checks / single-page lookups (e.g. verifying a rate or price) → haiku-scout, not opus  (2026-10-21)
- research → split it: haiku-scout gathers and extracts the sources, Opus writes the conclusion (not sonnet-worker end to end)  (2026-10-21)
- /graphify --update (scripted incremental runs) → haiku-worker; full /graphify builds (community naming) → sonnet-worker, not opus  (2026-10-23)
- lookups that need judgment across several sources → sonnet-worker; haiku-scout only for single-page extraction, reading known files, and gathering sources without judging them. In a research split, write haiku-scout's DONE WHEN as "sources gathered and extracted", so gathering alone counts as done  (2026-10-23)
- fake test-data/fixture generators with an exact spec and a substring-check done condition → haiku-worker, not sonnet  (2026-10-31)
