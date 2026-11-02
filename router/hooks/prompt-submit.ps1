# UserPromptSubmit: routing reminder on every prompt, plus !haiku / !sonnet / !opus / !noroute / !route overrides.
. "$PSScriptRoot\common.ps1"
try {
    $hook = Read-HookInput
    if (-not $hook) { exit 0 }
    $sid = $hook.session_id
    $prompt = ([string]$hook.prompt).TrimStart()

    $m = [regex]::Match($prompt, '^!(haiku|sonnet|opus|noroute|route)\b', 'IgnoreCase')
    if ($m.Success) {
        $cmd = $m.Groups[1].Value.ToLower()
        Add-LogEntry @{ ev = 'override'; kind = $cmd; session = $sid; prompt_id = $hook.prompt_id }
        switch ($cmd) {
            'noroute' {
                New-Item -ItemType File -Path (Get-StatePath $sid) -Force | Out-Null
                Write-Context 'UserPromptSubmit' '[router] The user turned routing OFF for this session (!noroute). Do everything yourself, no route lines, until they send !route.'
            }
            'route' {
                $p = Get-StatePath $sid
                if (Test-Path $p) { Remove-Item $p -Force }
                Write-Context 'UserPromptSubmit' '[router] Routing is back ON (!route). Route this request per cheap-model-router.'
            }
            'opus' { Write-Context 'UserPromptSubmit' '[router] User override !opus: do this request yourself. End with `route: opus`.' }
            'haiku' { Write-Context 'UserPromptSubmit' '[router] User override !haiku: delegate this request to haiku-scout (read-only work) or haiku-worker (edits/commands), even if you would route it elsewhere. Keep the usual brief, check and route line.' }
            'sonnet' { Write-Context 'UserPromptSubmit' '[router] User override !sonnet: delegate this request to sonnet-worker, even if you would route it elsewhere. Keep the usual brief, check and route line.' }
        }
        exit 0
    }

    if (Test-NoRoute $sid) { exit 0 }
    Write-Context 'UserPromptSubmit' '[router on] Route this request per cheap-model-router before working: read-only lookups -> haiku-scout first; tiny edits or hard work -> you; other clear fits -> haiku-worker / sonnet-worker / roblox-worker (Studio). If it is a task, end the final message with the `route:` line.'
} catch {
    [Console]::Error.WriteLine("cheap-model-router prompt-submit: $_")
}
exit 0
