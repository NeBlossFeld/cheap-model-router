# PreToolUse (Agent): worker calls must use the brief template, keep the agent's own model, and respect !noroute.
. "$PSScriptRoot\common.ps1"

function Deny([string]$reason) {
    Write-HookJson @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; permissionDecision = 'deny'; permissionDecisionReason = $reason } }
    exit 0
}

try {
    $hook = Read-HookInput
    if (-not $hook) { exit 0 }
    $ti = $hook.tool_input
    $config = Get-RouterConfig
    if ($config.workers -notcontains [string]$ti.subagent_type) { exit 0 }

    if (Test-NoRoute $hook.session_id) {
        Deny 'Routing is OFF for this session (!noroute). Do this yourself instead of delegating.'
    }

    $expected = if ($ti.subagent_type -like 'haiku-*') { 'haiku' } else { 'sonnet' }
    if ($ti.model -and (Get-ModelFamily ([string]$ti.model)) -ne $expected) {
        Deny "Don't pass model '$($ti.model)' to $($ti.subagent_type); its agent file sets $expected. Call again without the model field."
    }

    $missing = @()
    foreach ($field in 'TASK', 'TYPE', 'DONE WHEN') {
        if ([string]$ti.prompt -notmatch "(?m)^\s*$field\s*:") { $missing += $field }
    }
    if ($missing.Count -gt 0) {
        Deny ("Worker brief is missing: {0}. Use the cheap-model-router template (TASK, TYPE, CONTEXT, DO, DON'T, DONE WHEN) and call again." -f ($missing -join ', '))
    }
} catch {
    [Console]::Error.WriteLine("cheap-model-router pre-agent: $_")
}
exit 0
