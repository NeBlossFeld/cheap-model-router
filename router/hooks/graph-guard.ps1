# PreToolUse (Bash|PowerShell) inside roblox-worker: its shell may only run read-only graphify graph queries.
. "$PSScriptRoot\common.ps1"
try {
    $hook = Read-HookInput
    if (-not $hook) { exit 0 }
    $cmd = ([string]$hook.tool_input.command).Trim()
    # One graphify query/path/explain call, optionally through its full path; no chaining or redirection.
    $c = $cmd -replace '^&\s*', ''
    $allowed = ($c -match '^"?([A-Za-z]:[\\/][^"]*[\\/])?graphify(\.exe)?"?\s+(query|path|explain)\b') -and ($c -notmatch '[;|&<>`\r\n]|\$\(')
    if (-not $allowed) {
        $reason = "Router safety: roblox-worker's shell only runs graphify graph queries (graphify query / path / explain, one command, no chaining). Use the Roblox Studio tools for everything else."
        Write-HookJson @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; permissionDecision = 'deny'; permissionDecisionReason = $reason } }
    }
} catch {
    [Console]::Error.WriteLine("cheap-model-router graph-guard failed, blocking: $_")
    exit 2
}
exit 0
