# Stop: read the `route:` and `route-feedback:` lines from Opus's final message; log the route, save feedback as a learned rule.
. "$PSScriptRoot\common.ps1"
try {
    $hook = Read-HookInput
    if (-not $hook -or $hook.stop_hook_active) { exit 0 }
    $msg = [string]$hook.last_assistant_message
    if (-not $msg) { exit 0 }

    foreach ($fm in [regex]::Matches($msg, '(?im)^[\s>*_`]*route-feedback\s*:\s*(.+?)[`*_\s]*$')) {
        $rule = $fm.Groups[1].Value.Trim().Trim('"')
        $existing = if (Test-Path $script:FeedbackPath) { [System.IO.File]::ReadAllText($script:FeedbackPath, $script:Utf8) } else { '' }
        if ($rule -and $existing.IndexOf($rule, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
            [System.IO.File]::AppendAllText($script:FeedbackPath, ("- {0}  ({1:yyyy-MM-dd})`n" -f $rule, (Get-Date)), $script:Utf8)
            Add-LogEntry @{ ev = 'feedback'; session = $hook.session_id; rule = $rule }
            # Optional: also record the new rule in a changelog (e.g. the router's own git repo).
            $changelog = [string](Get-RouterConfig).changelog_path
            if ($changelog -and (Test-Path $changelog)) {
                [System.IO.File]::AppendAllText($changelog, ("- {0:yyyy-MM-dd}: learned rule: {1}`n" -f (Get-Date), $rule), $script:Utf8)
            }
        }
    }

    $routes = [regex]::Matches($msg, '(?im)^[\s>*_`]*route\s*:\s*(.+?)[`*_\s]*$')
    if ($routes.Count -eq 0) { exit 0 }
    $route = $routes[$routes.Count - 1].Groups[1].Value.Trim()
    $lower = $route.ToLower()

    # "asked X" = the user requested model X for this task; "auto Y" = what Opus would have picked on its own.
    # Only a request that differs from the automatic pick is a real override (a correction worth learning from).
    $asked = ([regex]::Match($lower, '\basked\s*:?\s*(haiku|sonnet|opus)')).Groups[1].Value
    $auto = ([regex]::Match($lower, '\bauto\s*:?\s*(haiku|sonnet|opus)')).Groups[1].Value
    $override = [bool]($asked -and $auto -and $asked -ne $auto)
    $lower = [regex]::Replace($lower, '\b(asked|auto)\s*:?\s*(haiku|sonnet|opus)', '')

    $models = @([regex]::Matches($lower, 'haiku|sonnet|opus') | ForEach-Object { $_.Value } | Select-Object -Unique)
    # Escalation: a cross mark after a cheap model, "haiku x ->" in plain ASCII, or the word "fail".
    $cross = [string][char]0x2717 + [char]0x2718 + [char]0x274C
    $escalated = ($lower -match 'fail') -or ($lower -match "(haiku|sonnet)[^a-z]*[$cross]") -or ($lower -match '(haiku|sonnet)\s+x\b')
    # Finished by Opus: a half-circle after a cheap model (worker left it partial, Opus completed it).
    $half = [string][char]0x25D0
    $finished = -not $escalated -and (($lower -match "(haiku|sonnet)[^a-z]*$half") -or ($lower -match '(haiku|sonnet)\s+partial\b'))
    $from = ''
    if ($escalated -or $finished) { $fm2 = [regex]::Match($lower, '(haiku|sonnet)'); if ($fm2.Success) { $from = $fm2.Groups[1].Value } }
    $primary = if ($models -contains 'haiku' -or $models -contains 'sonnet') {
        if ($escalated -or $finished) { $from } elseif ($models.Count -gt 1) { 'split' } else { $models[0] }
    } else { 'opus' }

    $config = Get-RouterConfig
    $turn = Get-TurnCost ([string]$hook.transcript_path) ([string]$hook.prompt_id) $config

    Add-LogEntry @{
        ev = 'turn'; session = $hook.session_id; prompt_id = $hook.prompt_id; route = $route
        models = $models; primary = $primary; escalated = [bool]$escalated; finished_by_opus = [bool]$finished; escalated_from = $from
        turn_cost = [math]::Round($turn.cost, 5); turn_tokens = $turn.tokens; turn_model = $turn.model
        asked = $asked; auto = $auto; override = $override
    }
} catch {
    [Console]::Error.WriteLine("cheap-model-router turn-stop: $_")
}
exit 0
