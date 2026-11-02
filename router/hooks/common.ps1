# Shared helpers for cheap-model-router hooks. Dot-source this file.
# Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less scripts as ANSI.

$ErrorActionPreference = 'Stop'
$script:Utf8 = New-Object System.Text.UTF8Encoding $false
[Console]::OutputEncoding = $script:Utf8
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture

$script:UserHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$script:RouterDir = [System.IO.Path]::Combine($script:UserHome, '.claude', 'router')
$script:LogPath = Join-Path $script:RouterDir 'log.jsonl'
$script:FeedbackPath = Join-Path $script:RouterDir 'feedback.md'
$script:StateDir = Join-Path $script:RouterDir 'state'
$script:SkillPath = [System.IO.Path]::Combine($script:UserHome, '.claude', 'skills', 'cheap-model-router', 'SKILL.md')

function Read-HookInput {
    $reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), $script:Utf8)
    $raw = $reader.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return $raw | ConvertFrom-Json
}

function Write-HookJson($obj) {
    [Console]::Out.Write(($obj | ConvertTo-Json -Depth 8 -Compress))
}

function Write-Context([string]$event, [string]$text) {
    Write-HookJson @{ hookSpecificOutput = @{ hookEventName = $event; additionalContext = $text } }
}

function Get-RouterConfig {
    return [System.IO.File]::ReadAllText((Join-Path $script:RouterDir 'config.json'), $script:Utf8) | ConvertFrom-Json
}

function Add-LogEntry([hashtable]$entry) {
    $entry['ts'] = (Get-Date).ToUniversalTime().ToString('o')
    $line = ($entry | ConvertTo-Json -Depth 6 -Compress) + "`n"
    [System.IO.File]::AppendAllText($script:LogPath, $line, $script:Utf8)
}

function Read-Log([int]$days = 0) {
    if (-not (Test-Path $script:LogPath)) { return @() }
    $cutoff = if ($days -gt 0) { (Get-Date).ToUniversalTime().AddDays(-$days) } else { [datetime]::MinValue }
    $items = foreach ($line in [System.IO.File]::ReadAllLines($script:LogPath, $script:Utf8)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $e = $line | ConvertFrom-Json } catch { continue }
        if ($days -gt 0 -and ([datetime]$e.ts).ToUniversalTime() -lt $cutoff) { continue }
        $e
    }
    return @($items)
}

function Get-ModelFamily([string]$model) {
    if ($model -match 'haiku') { return 'haiku' }
    if ($model -match 'sonnet') { return 'sonnet' }
    if ($model -match 'opus') { return 'opus' }
    return $model
}

function Get-Price($prices, [string]$family, [double]$promptTokens) {
    $p = $prices.$family
    if ($null -eq $p) { return $null }
    if ($p.long_threshold -and $promptTokens -gt $p.long_threshold) { return $p.long }
    return $p
}

function Get-UsageCost($price, $u) {
    return (($u.input * $price.input) + ($u.cache_write * $price.cache_write) +
            ($u.cache_read * $price.cache_read) + ($u.output * $price.output)) / 1e6
}

function Get-StatePath([string]$sessionId) {
    if (-not (Test-Path $script:StateDir)) { New-Item -ItemType Directory -Path $script:StateDir | Out-Null }
    return Join-Path $script:StateDir ($sessionId + '.noroute')
}

function Test-NoRoute([string]$sessionId) {
    if (-not $sessionId) { return $false }
    return Test-Path (Get-StatePath $sessionId)
}

# Reads a worker's transcript: brief fields, model, deduplicated usage with costs, and its report texts.
# Background workers hand their report back through the SubagentHandback tool, not as a final reply.
function Read-WorkerTranscript([string]$path, $config) {
    $r = @{ task = ''; type = ''; model = ''; cost = 0.0; opus_cost = 0.0; handback = ''; last_text = ''
            usage = @{ input = 0.0; cache_write = 0.0; cache_read = 0.0; output = 0.0 } }
    if ($path.StartsWith('~')) { $path = $script:UserHome + $path.Substring(1) }
    if (-not $path -or -not (Test-Path $path)) { return $r }
    $seen = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($path, $script:Utf8)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $e = $line | ConvertFrom-Json } catch { continue }

        if (-not $r.task -and $e.type -eq 'user') {
            $c = $e.message.content
            $text = if ($c -is [string]) { $c } else { ($c | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join "`n" }
            $mt = [regex]::Match($text, '(?m)^\s*TASK\s*:\s*(.+)$'); if ($mt.Success) { $r.task = $mt.Groups[1].Value.Trim() }
            $my = [regex]::Match($text, '(?m)^\s*TYPE\s*:\s*([\w-]+)'); if ($my.Success) { $r.type = $my.Groups[1].Value.Trim().ToLower() }
        }
        if ($e.type -ne 'assistant') { continue }

        foreach ($block in @($e.message.content)) {
            if ($block.type -eq 'text' -and $block.text) { $r.last_text = [string]$block.text }
            if ($block.type -eq 'tool_use' -and $block.name -eq 'SubagentHandback' -and $block.input.message) { $r.handback = [string]$block.input.message }
        }

        if ($e.message.usage) {
            # One API response can span several transcript lines; count its usage once.
            $id = [string]$e.message.id
            if ($id -and $seen.ContainsKey($id)) { continue }
            if ($id) { $seen[$id] = $true }
            if ($e.message.model) { $r.model = [string]$e.message.model }
            $u = @{
                input       = [double]$e.message.usage.input_tokens
                cache_write = [double]$e.message.usage.cache_creation_input_tokens
                cache_read  = [double]$e.message.usage.cache_read_input_tokens
                output      = [double]$e.message.usage.output_tokens
            }
            foreach ($k in @($u.Keys)) { $r.usage[$k] += $u[$k] }
            $price = Get-Price $config.prices (Get-ModelFamily $r.model) ($u.input + $u.cache_write + $u.cache_read)
            if ($price) { $r.cost += Get-UsageCost $price $u }
            $r.opus_cost += Get-UsageCost $config.prices.opus $u
        }
    }
    return $r
}

# Main-session cost of one prompt's turn. Assistant lines carry no promptId, so each one belongs
# to the most recent user line before it. The transcript is written async; the final reply may be missing.
function Get-TurnCost([string]$path, [string]$promptId, $config) {
    $r = @{ cost = 0.0; tokens = 0.0; model = '' }
    if (-not $path -or -not $promptId) { return $r }
    if ($path.StartsWith('~')) { $path = $script:UserHome + $path.Substring(1) }
    if (-not (Test-Path $path)) { return $r }
    $current = ''; $seen = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($path, $script:Utf8)) {
        if ($line.IndexOf('"promptId"') -lt 0 -and $line.IndexOf('"usage"') -lt 0) { continue }
        try { $e = $line | ConvertFrom-Json } catch { continue }
        if ($e.type -eq 'user' -and $e.promptId) { $current = [string]$e.promptId; continue }
        if ($current -ne $promptId -or $e.type -ne 'assistant' -or -not $e.message.usage) { continue }
        $id = [string]$e.message.id
        if ($id -and $seen.ContainsKey($id)) { continue }
        if ($id) { $seen[$id] = $true }
        if ($e.message.model) { $r.model = [string]$e.message.model }
        $u = @{
            input       = [double]$e.message.usage.input_tokens
            cache_write = [double]$e.message.usage.cache_creation_input_tokens
            cache_read  = [double]$e.message.usage.cache_read_input_tokens
            output      = [double]$e.message.usage.output_tokens
        }
        $r.tokens += $u.input + $u.cache_write + $u.cache_read + $u.output
        $price = Get-Price $config.prices (Get-ModelFamily $r.model) ($u.input + $u.cache_write + $u.cache_read)
        if (-not $price) { $price = $config.prices.opus }
        $r.cost += Get-UsageCost $price $u
    }
    return $r
}

# STATUS and CONFIDENCE from the first text that has them (plain or markdown-bold "**STATUS:** done").
function Get-ReportFields([string[]]$texts) {
    foreach ($t in $texts) {
        if (-not $t) { continue }
        $s = [regex]::Match($t, '(?im)^[\s>*_`-]*STATUS[*_`\s]*:[*_`\s]*(done|partial|failed)\b')
        if (-not $s.Success) { continue }
        $c = [regex]::Match($t, '(?im)^[\s>*_`-]*CONFIDENCE[*_`\s]*:[*_`\s]*(high|low)\b')
        $w = [regex]::Match($t, '(?im)^[\s>*_`-]*PARTIAL-WHY[*_`\s]*:[*_`\s]*(incomplete|blocked|wrong)\b')
        return @{ status = $s.Groups[1].Value.ToLower()
                  confidence = $(if ($c.Success) { $c.Groups[1].Value.ToLower() } else { 'unknown' })
                  partial_why = $(if ($w.Success) { $w.Groups[1].Value.ToLower() } else { '' }) }
    }
    return @{ status = 'unknown'; confidence = 'unknown'; partial_why = '' }
}

# Worker runs that failed or whose turn escalated, grouped by model family and task type.
# Runs with an unknown status count only if their turn escalated.
function Get-WeakSpots($entries, $config) {
    $escalatedPrompts = @{}
    foreach ($t in $entries | Where-Object { $_.ev -eq 'turn' -and $_.escalated }) { $escalatedPrompts[$t.prompt_id] = $true }
    $groups = @{}
    foreach ($w in $entries | Where-Object { $_.ev -eq 'worker' }) {
        $escalated = $escalatedPrompts.ContainsKey($w.prompt_id)
        if ($w.status -eq 'unknown' -and -not $escalated) { continue }
        $key = "$($w.family)|$($w.type)"
        if (-not $groups.ContainsKey($key)) { $groups[$key] = @{ family = $w.family; type = $w.type; n = 0; bad = 0 } }
        $groups[$key].n++
        if ($w.status -in 'partial', 'failed' -or $escalated) { $groups[$key].bad++ }
    }
    $min = $config.weak_spot.min_tasks
    $rate = $config.weak_spot.fail_rate
    return @($groups.Values | Where-Object { $_.n -ge $min -and ($_.bad / $_.n) -ge $rate } |
        Sort-Object { $_.bad / $_.n } -Descending)
}
