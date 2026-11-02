---
name: route-stats
description: Show cheap-model-router statistics - share of work per model, escalations, weak spots per task type, tokens and estimated savings. Use when the user runs /route-stats or asks how the routing is doing.
argument-hint: "[days, default 30]"
allowed-tools: PowerShell(powershell -NoProfile -ExecutionPolicy Bypass -File {{CLAUDE_HOME}}/router/hooks/stats.ps1*)
---

Run this with the PowerShell tool. Pass the number of days from the arguments, or leave it out for 30:

```
powershell -NoProfile -ExecutionPolicy Bypass -File {{CLAUDE_HOME}}/router/hooks/stats.ps1 $ARGUMENTS
```

Show the user the report as it comes back (it's already markdown). Then add at most 3 short suggestions drawn from it, such as a task type that keeps failing on Haiku and should move to Sonnet, or a lane that's never used. Offer to save a suggestion as a learned rule. If they agree, add a `route-feedback:` line as the cheap-model-router skill describes.

Don't add a `route:` line for this turn.
