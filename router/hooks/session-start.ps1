# SessionStart: load the router skill, learned rules and weak spots into context.
. "$PSScriptRoot\common.ps1"
try {
    $hook = Read-HookInput
    $skill = [System.IO.File]::ReadAllText($script:SkillPath, $script:Utf8)
    $skill = [regex]::Replace($skill, '(?s)^---.*?\r?\n---\r?\n', '')

    $parts = @("[cheap-model-router is ON for this session. Its full instructions follow.]", $skill.Trim())

    if (Test-Path $script:FeedbackPath) {
        $rules = [System.IO.File]::ReadAllLines($script:FeedbackPath, $script:Utf8) | Where-Object { $_ -match '^\s*-\s+' }
        if ($rules) { $parts += "## Learned rules (from the user's corrections)`n" + ($rules -join "`n") }
    }

    $entries = Read-Log 60
    $workers = @($entries | Where-Object { $_.ev -eq 'worker' })
    if ($workers.Count -gt 0) {
        $saved = ($workers | Measure-Object -Property saved -Sum).Sum
        $parts += ("Router so far (60d): {0} delegations, est. saved `${1:N2}. /route-stats for details." -f $workers.Count, $saved)
    }

    if ($hook -and (Test-NoRoute $hook.session_id)) {
        $parts += "NOTE: the user turned routing OFF for this session (!noroute). Do everything yourself until they send !route."
    }

    Write-Context 'SessionStart' ($parts -join "`n`n")
} catch {
    [Console]::Error.WriteLine("cheap-model-router session-start: $_")
}
exit 0
