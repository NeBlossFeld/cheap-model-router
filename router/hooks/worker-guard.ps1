# PreToolUse (Bash|PowerShell) inside haiku-worker / sonnet-worker: block deletes, pushes, publishing, sending and system changes.
. "$PSScriptRoot\common.ps1"
try {
    $hook = Read-HookInput
    if (-not $hook) { exit 0 }
    $cmd = [string]$hook.tool_input.command

    $rules = [ordered]@{
        'delete files'           = '(^|[;&|(\n]|/c)\s*(rm|rmdir|rd|del|erase|ri|unlink|shred)(\s|$)|Remove-Item|Clear-Content|Clear-RecycleBin|\bgit\s+rm\b'
        'git history or remote'  = '\bgit\s+(push|reset\s+--hard|clean|rebase|filter-branch|branch\s+-D|tag\s+-d|stash\s+(drop|clear))\b|--force\b|--force-with-lease'
        'publish or send'        = '\b(npm|pnpm|yarn|cargo|twine|gem)\s+publish\b|\bdocker\s+push\b|\bgh\s+(pr|issue|release|repo|gist)\s+(create|merge|close|comment|edit|delete|review)\b|Send-MailMessage|\bcurl\b.*(-X\s*(POST|PUT|PATCH|DELETE)|--data|\s-d\s|-F\s)|Invoke-(WebRequest|RestMethod)\b.*-Method\s+(Post|Put|Patch|Delete)'
        'system settings'        = 'Set-ExecutionPolicy|\breg(\.exe)?\s+(add|delete|import)\b|(Set|New|Remove)-ItemProperty\b.*\b(HKLM|HKCU)|\bshutdown\b|Restart-Computer|Stop-Computer|\bformat(\.com)?\s+[a-z]:|\bdiskpart\b|\bbcdedit\b|\bnetsh\b|Set-Service|Stop-Service|\bsc(\.exe)?\s+(config|delete|stop)\b|Stop-Process|\btaskkill\b|\bschtasks\b|\bsetx\b'
    }

    foreach ($name in $rules.Keys) {
        if ($cmd -match $rules[$name]) {
            $reason = "Router safety: workers can't run commands that $name. Don't retry or work around it. Finish the rest, then list this command under NEEDS-OPUS so Opus can handle it."
            Write-HookJson @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; permissionDecision = 'deny'; permissionDecisionReason = $reason } }
            exit 0
        }
    }
} catch {
    # Fail closed: a guard that can't read the command shouldn't let it through.
    [Console]::Error.WriteLine("cheap-model-router worker-guard failed, blocking: $_")
    exit 2
}
exit 0
