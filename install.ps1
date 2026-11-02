# Installs (or updates) cheap-model-router into your user-level Claude Code folder.
# Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 [-NoRoblox] [-ClaudeHome <path>]
# Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less scripts as ANSI.
param(
    [switch]$NoRoblox,
    [string]$ClaudeHome = (Join-Path $HOME '.claude')
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false
$repo = $PSScriptRoot
$homeFwd = $ClaudeHome.Replace('\', '/')
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

function Read-Text($path) { return [IO.File]::ReadAllText($path, $utf8) }
function Write-Text($path, $text) {
    New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
    [IO.File]::WriteAllText($path, $text, $utf8)
}

Write-Host "Installing cheap-model-router into $ClaudeHome"

# 1. Code files: always installed; an existing different copy is kept as .bak-<time>.
$code = @(
    'agents/haiku-scout.md', 'agents/haiku-worker.md', 'agents/sonnet-worker.md',
    'skills/cheap-model-router/SKILL.md', 'skills/route-stats/SKILL.md',
    'router/hooks/common.ps1', 'router/hooks/session-start.ps1', 'router/hooks/prompt-submit.ps1',
    'router/hooks/pre-agent.ps1', 'router/hooks/worker-guard.ps1', 'router/hooks/luau-guard.ps1',
    'router/hooks/subagent-stop.ps1', 'router/hooks/turn-stop.ps1', 'router/hooks/stats.ps1'
)
if (-not $NoRoblox) { $code += 'agents/roblox-worker.md' }

foreach ($rel in $code) {
    $text = (Read-Text (Join-Path $repo $rel)).Replace('{{CLAUDE_HOME}}', $homeFwd)
    $dest = Join-Path $ClaudeHome $rel
    if ((Test-Path $dest) -and (Read-Text $dest) -ne $text) { Copy-Item $dest "$dest.bak-$stamp" }
    Write-Text $dest $text
    Write-Host "  wrote $rel"
}

# 2. Your data: config and learned rules are only created, never overwritten.
foreach ($rel in 'router/config.json', 'router/feedback.md') {
    $dest = Join-Path $ClaudeHome $rel
    if (Test-Path $dest) { Write-Host "  kept your existing $rel" }
    else { Write-Text $dest (Read-Text (Join-Path $repo $rel)); Write-Host "  wrote $rel" }
}
if ($NoRoblox) {
    $cfgPath = Join-Path $ClaudeHome 'router/config.json'
    $cfg = Read-Text $cfgPath | ConvertFrom-Json
    $cfg.workers = @($cfg.workers | Where-Object { $_ -ne 'roblox-worker' })
    Write-Text $cfgPath ($cfg | ConvertTo-Json -Depth 8)
}

# 3. settings.json: merge the router's hooks in, keep everything else.
$settingsPath = Join-Path $ClaudeHome 'settings.json'
$settings = if (Test-Path $settingsPath) { Copy-Item $settingsPath "$settingsPath.bak-$stamp"; Read-Text $settingsPath | ConvertFrom-Json } else { New-Object PSObject }
if (-not $settings.hooks) { $settings | Add-Member -NotePropertyName hooks -NotePropertyValue (New-Object PSObject) -Force }
$ours = ((Read-Text (Join-Path $repo 'settings.hooks.json')).Replace('{{CLAUDE_HOME}}', $homeFwd) | ConvertFrom-Json).hooks
foreach ($event in $ours.PSObject.Properties.Name) {
    $groups = @($ours.$event)
    $existing = @($settings.hooks.$event | Where-Object { $_ })
    foreach ($g in $groups) {
        $script = ($g.hooks[0].args | Where-Object { $_ -like '*.ps1' }) -replace '.*/', ''
        $already = $existing | Where-Object { ($_ | ConvertTo-Json -Depth 10 -Compress) -like "*$script*" }
        if (-not $already) { $existing += $g; Write-Host "  added $event hook ($script)" }
    }
    $settings.hooks | Add-Member -NotePropertyName $event -NotePropertyValue $existing -Force
}
Write-Text $settingsPath ($settings | ConvertTo-Json -Depth 20)

# 4. CLAUDE.md: one line so routing is on even if a hook fails to load.
$claudeMd = Join-Path $ClaudeHome 'CLAUDE.md'
$line = "# Model routing`nThe cheap-model-router skill is always on: route every task per ``~/.claude/skills/cheap-model-router/SKILL.md`` (normally loaded by a SessionStart hook). If it isn't in context, load that skill before working on a task.`n"
$current = if (Test-Path $claudeMd) { Read-Text $claudeMd } else { '' }
if ($current -notmatch 'cheap-model-router') { Write-Text $claudeMd ($line + "`n" + $current); Write-Host '  added routing line to CLAUDE.md' }

# 5. Self-test: the session-start hook must return the router context.
$out = '{"session_id":"install-test","source":"startup"}' | powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ClaudeHome 'router/hooks/session-start.ps1')
$ok = $false
try { $ok = (($out | ConvertFrom-Json).hookSpecificOutput.additionalContext -like '*cheap-model-router is ON*') } catch {}
if ($ok) { Write-Host "`nDone. Start a NEW Claude Code session to load the router." }
else { Write-Host "`nInstalled, but the self-test failed. Output was:`n$out"; exit 1 }
