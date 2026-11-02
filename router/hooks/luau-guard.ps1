# PreToolUse (execute_luau) inside roblox-worker: block Luau that destroys instances, writes data stores, uses the network or publishes.
. "$PSScriptRoot\common.ps1"
try {
    $hook = Read-HookInput
    if (-not $hook) { exit 0 }
    $code = [string]$hook.tool_input.code

    $rules = [ordered]@{
        'destroy or remove instances' = ':\s*(Destroy|Remove|ClearAllChildren)\s*\(|Debris\s*:\s*AddItem'
        'write data stores'           = 'DataStoreService|MemoryStoreService|:\s*(SetAsync|UpdateAsync|RemoveAsync|IncrementAsync)\s*\('
        'use the network'             = 'HttpService|MessagingService|TeleportService|MarketplaceService'
        'publish or save the place'   = 'Publish|SavePlace|AssetService|InsertService|game\s*:\s*Shutdown'
    }

    foreach ($name in $rules.Keys) {
        if ($code -match $rules[$name]) {
            $reason = "Router safety: roblox-worker can't run Luau that may $name. Don't retry or work around it. Finish the rest, then list this under NEEDS-OPUS so Opus can handle it."
            Write-HookJson @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; permissionDecision = 'deny'; permissionDecisionReason = $reason } }
            exit 0
        }
    }
} catch {
    # Fail closed: a guard that can't read the code shouldn't let it through.
    [Console]::Error.WriteLine("cheap-model-router luau-guard failed, blocking: $_")
    exit 2
}
exit 0
