# /route-stats report: share of work per model, escalations, weak spots, tokens and estimated savings.
param([string]$Days = '30')
. "$PSScriptRoot\common.ps1"

$d = 30
[void][int]::TryParse(($Days -replace '[^0-9]', ''), [ref]$d)
if ($d -le 0) { $d = 30 }
$config = Get-RouterConfig
$entries = Read-Log $d
$turns = @($entries | Where-Object { $_.ev -eq 'turn' })
$workers = @($entries | Where-Object { $_.ev -eq 'worker' })
$overrides = @($entries | Where-Object { $_.ev -eq 'override' })

function Pct($a, $b) { if ($b -eq 0) { return '-' } return ('{0:N0}%' -f (100.0 * $a / $b)) }

$out = New-Object System.Collections.Generic.List[string]
$out.Add("## Route stats - last $d days")
if ($entries.Count -eq 0) {
    $out.Add('No routing data yet. It fills in as tasks get routed.')
    [Console]::Out.Write(($out -join "`n")); exit 0
}

$out.Add("`n### Who handled the task turns ($($turns.Count))")
$out.Add('| Route | Turns | Share |'); $out.Add('|---|---|---|')
foreach ($p in 'haiku', 'sonnet', 'split', 'opus') {
    $n = @($turns | Where-Object { $_.primary -eq $p -and -not $_.escalated -and -not $_.finished_by_opus }).Count
    $out.Add("| $p | $n | $(Pct $n $turns.Count) |")
}
$fin = @($turns | Where-Object { $_.finished_by_opus })
$out.Add("| partial, finished by opus | $($fin.Count) | $(Pct $fin.Count $turns.Count) |")
$esc = @($turns | Where-Object { $_.escalated })
$out.Add("| escalated to opus | $($esc.Count) | $(Pct $esc.Count $turns.Count) |")

$out.Add("`n### Worker runs ($($workers.Count))")
if ($workers.Count -eq 0) { $out.Add('None yet. Every task so far stayed with Opus.') }
else {
# A failure is a run that failed, a result the worker itself calls wrong, or a turn Opus had to redo.
# A partial that is only incomplete or blocked is not a failure: its work was kept.
$escalatedPrompts = @{}
foreach ($t in $esc) { $escalatedPrompts[$t.prompt_id] = $true }
function Test-Failure($w) { return ($w.status -eq 'failed' -or $w.partial_why -eq 'wrong' -or $escalatedPrompts.ContainsKey($w.prompt_id)) }
function Test-Partial($w) { return ($w.status -eq 'partial' -and -not (Test-Failure $w)) }

$out.Add('| Agent | Runs | Done | Partial | Failed | Unknown | High confidence | Tokens (in+out) | Cost | Opus would cost | Saved |')
$out.Add('|---|---|---|---|---|---|---|---|---|---|---|')
foreach ($g in $workers | Group-Object agent | Sort-Object Name) {
    $runs = @($g.Group)
    $done = @($runs | Where-Object { $_.status -eq 'done' -and -not (Test-Failure $_) }).Count
    $part = @($runs | Where-Object { Test-Partial $_ }).Count
    $bad = @($runs | Where-Object { Test-Failure $_ }).Count
    $unknown = @($runs | Where-Object { $_.status -notin 'done', 'partial', 'failed' -and -not (Test-Failure $_) }).Count
    $known = @($runs | Where-Object { $_.confidence -in 'high', 'low' }).Count
    $high = @($runs | Where-Object { $_.confidence -eq 'high' }).Count
    $tok = ($runs | ForEach-Object { $_.tokens.input + $_.tokens.cache_write + $_.tokens.cache_read + $_.tokens.output } | Measure-Object -Sum).Sum
    $cost = ($runs | Measure-Object -Property cost -Sum).Sum
    $opus = ($runs | Measure-Object -Property opus_cost -Sum).Sum
    $out.Add(("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7:N0} | `${8:N3} | `${9:N3} | `${10:N3} |" -f $g.Name, $runs.Count, $done, $part, $bad, $unknown, (Pct $high $known), $tok, $cost, $opus, ($opus - $cost)))
}
$partials = @($workers | Where-Object { $_.status -in 'partial', 'failed' })
if ($partials.Count -gt 0) {
    $why = $partials | Group-Object { if ($_.partial_why) { $_.partial_why } else { 'not given' } } | ForEach-Object { "$($_.Name): $($_.Count)" }
    $out.Add("`nWhy partial/failed: " + ($why -join ' / '))
}
$finishedIds = @{}; foreach ($t in $fin) { $finishedIds[$t.prompt_id] = $true }
$finishedRuns = @($workers | Where-Object { (Test-Partial $_) -and $finishedIds.ContainsKey($_.prompt_id) }).Count
$out.Add("Partials whose turn Opus had to finish: $finishedRuns of $(@($workers | Where-Object { Test-Partial $_ }).Count). Failed = failed, self-reported wrong, or redone by Opus.")

$totalSaved = [double]($workers | Measure-Object -Property saved -Sum).Sum
$out.Add(("`n**Gross savings: `${0:N2}** (worker tokens priced at Opus vs the worker's model; a rough upper estimate)." -f $totalSaved))

# Net: only turns whose own Opus cost was measured. Delegation overhead is what a delegated turn costs Opus
# beyond an average kept turn (briefing and checking); the rest Opus would have spent anyway.
$measured = @($turns | Where-Object { $null -ne $_.turn_cost -and ($_.models -contains 'haiku' -or $_.models -contains 'sonnet') })
$kept = @($turns | Where-Object { $null -ne $_.turn_cost -and $_.primary -eq 'opus' })
if ($measured.Count -gt 0 -and $kept.Count -gt 0) {
    $ids = @{}; foreach ($t in $measured) { $ids[$t.prompt_id] = $true }
    $mSaved = [double](@($workers | Where-Object { $ids.ContainsKey($_.prompt_id) }) | Measure-Object -Property saved -Sum).Sum
    $avgDelegated = [double]($measured | Measure-Object -Property turn_cost -Sum).Sum / $measured.Count
    $avgKept = [double]($kept | Measure-Object -Property turn_cost -Sum).Sum / $kept.Count
    $overhead = [math]::Max(0, ($avgDelegated - $avgKept) * $measured.Count)
    $out.Add(("**Net savings ({0} measured delegated turns): `${1:N2}** = `${2:N2} saved by workers - `${3:N2} extra Opus cost for briefing and checking." -f $measured.Count, ($mSaved - $overhead), $mSaved, $overhead))
    $out.Add(("Average Opus cost per turn: delegated `${0:N3} vs kept by Opus `${1:N3} ({2} kept turns). Delegated turns are often bigger tasks, so the true overhead may be lower." -f $avgDelegated, $avgKept, $kept.Count))
} elseif ($measured.Count -gt 0) {
    $out.Add('Net savings: needs a few measured turns that Opus kept, to compare against.')
} else {
    $out.Add('Net savings: not measured yet. It starts with the next delegated turns.')
}

$out.Add("`n### By task type")
$out.Add('| Model | Type | Runs | Partial | Failed | Unknown |'); $out.Add('|---|---|---|---|---|---|')
foreach ($g in $workers | Group-Object { "$($_.family)|$($_.type)" } | Sort-Object Name) {
    $runs = @($g.Group)
    $part = @($runs | Where-Object { Test-Partial $_ }).Count
    $bad = @($runs | Where-Object { Test-Failure $_ }).Count
    $unknown = @($runs | Where-Object { $_.status -notin 'done', 'partial', 'failed' -and -not (Test-Failure $_) }).Count
    $known = $runs.Count - $unknown
    $out.Add("| $($runs[0].family) | $($runs[0].type) | $($runs.Count) | $part | $bad ($(Pct $bad $known)) | $unknown |")
}
}

# Graph use: only runs logged since graph counting exists (they carry graph_queries).
$tracked = @($workers | Where-Object { $null -ne $_.graph_queries -and $_.agent -ne 'haiku-scout' })
$out.Add("`n### Graph use ($($tracked.Count) worker runs tracked)")
if ($tracked.Count -eq 0) { $out.Add('No tracked runs yet. Counting started with the graph-query feature.') }
else {
    $out.Add('| Runs | Count | Done | Failed | Avg tokens | Avg cost |'); $out.Add('|---|---|---|---|---|---|')
    foreach ($set in @(@{ n = 'with graph query'; r = @($tracked | Where-Object { $_.graph_queries -gt 0 }) }, @{ n = 'without'; r = @($tracked | Where-Object { $_.graph_queries -eq 0 }) })) {
        $r = $set.r
        if ($r.Count -eq 0) { $out.Add("| $($set.n) | 0 | - | - | - | - |"); continue }
        $d = @($r | Where-Object { $_.status -eq 'done' -and -not (Test-Failure $_) }).Count
        $f = @($r | Where-Object { Test-Failure $_ }).Count
        $tok = ($r | ForEach-Object { $_.tokens.input + $_.tokens.cache_write + $_.tokens.cache_read + $_.tokens.output } | Measure-Object -Average).Average
        $cst = ($r | Measure-Object -Property cost -Average).Average
        $out.Add(("| {0} | {1} | {2} | {3} | {4:N0} | `${5:N3} |" -f $set.n, $r.Count, $d, $f, $tok, $cst))
    }
    $out.Add('Different task mixes make this a rough comparison; it gets meaningful after ~20 runs each.')
}

$out.Add("`n### Prefix commands ($($overrides.Count))")
if ($overrides.Count -gt 0) { $out.Add((($overrides | Group-Object kind | ForEach-Object { "!$($_.Name): $($_.Count)" }) -join ' / ')) }

# Turns where the user asked for a model. Only asked != auto is a real override.
$asked = @($turns | Where-Object { $_.asked })
$out.Add("`n### Your model requests ($($asked.Count))")
if ($asked.Count -eq 0) { $out.Add('None logged yet.') }
else {
    $real = @($asked | Where-Object { $_.override })
    $agreed = @($asked | Where-Object { $_.auto -and -not $_.override }).Count
    $noAuto = @($asked | Where-Object { -not $_.auto }).Count
    $out.Add("Same as Opus would have picked: $agreed / real overrides: $($real.Count) / auto pick unknown: $noAuto")
    if ($real.Count -gt 0) {
        $typesByPrompt = @{}
        foreach ($w in $workers) { if ($w.prompt_id) { $typesByPrompt[$w.prompt_id] = $w.type } }
        $out.Add('| Opus picked | You asked | Task type | Times |'); $out.Add('|---|---|---|---|')
        foreach ($g in $real | Group-Object { "$($_.auto)|$($_.asked)|$(if ($typesByPrompt.ContainsKey($_.prompt_id)) { $typesByPrompt[$_.prompt_id] } else { '-' })" } | Sort-Object Count -Descending) {
            $p = $g.Name.Split('|')
            $out.Add("| $($p[0]) | $($p[1]) | $($p[2]) | $($g.Count) |")
        }
        $out.Add('Patterns that repeat (2+ times) are good candidates for a learned rule.')
    }
}

$ruleCount = 0
if (Test-Path $script:FeedbackPath) { $ruleCount = @([System.IO.File]::ReadAllLines($script:FeedbackPath, $script:Utf8) | Where-Object { $_ -match '^\s*-\s+' }).Count }
$out.Add("`nLearned rules: $ruleCount (in ~/.claude/router/feedback.md)")

[Console]::Out.Write(($out -join "`n"))
exit 0
