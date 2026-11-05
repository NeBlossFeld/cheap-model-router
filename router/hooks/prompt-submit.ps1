# UserPromptSubmit: routing reminder on every prompt, plus !haiku / !sonnet / !opus / !noroute / !route overrides.
. "$PSScriptRoot\common.ps1"
try {
    $hook = Read-HookInput
    if (-not $hook) { exit 0 }
    $sid = $hook.session_id
    $prompt = ([string]$hook.prompt).TrimStart()
    # Keep this file ASCII-only: build the check mark and middle dot from char codes.
    $dot = [string][char]0x00B7; $check = [string][char]0x2713
    $askNote = " Because the user asked for a model, end the route line with `` $dot asked <model> $dot auto <model you would have picked on your own>`` (e.g. ``route: sonnet $check $dot asked sonnet $dot auto opus``)."

    $m =[regex]::Match($prompt, '^!(haiku|sonnet|opus|noroute|route)\b', 'IgnoreCase')
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
            'opus' { Write-Context 'UserPromptSubmit' ('[router] User override !opus: do this request yourself.' + $askNote) }
            'haiku' { Write-Context 'UserPromptSubmit' ('[router] User override !haiku: delegate this request to haiku-scout (read-only work) or haiku-worker (edits/commands), even if you would route it elsewhere. Keep the usual brief and check.' + $askNote) }
            'sonnet' { Write-Context 'UserPromptSubmit' ('[router] User override !sonnet: delegate this request to sonnet-worker, even if you would route it elsewhere. Keep the usual brief and check.' + $askNote) }
        }
        exit 0
    }

    if (Test-NoRoute $sid) { exit 0 }
    $text = '[router on] Route this request per cheap-model-router before working: read-only lookups -> haiku-scout first; tiny edits or hard work -> you; other clear fits -> haiku-worker / sonnet-worker / roblox-worker (Studio). If it is a task, end the final message with the `route:` line.'
    # A model or worker named in the prompt may be a routing request ("let sonnet do it", "do it yourself"); Opus decides.
    if ($prompt -match '(?i)\b(haiku|sonnet|opus|sub-?agents?|workers?|cheap(er)? models?)\b|\bdo (it|this|that) yourself\b') {
        $text += ' The prompt names a model or worker. Only if the user is asking which model should do THIS task (not talking about the router or a model in general), follow it and end the route line with ` ' + $dot + ' asked <model> ' + $dot + ' auto <model you would have picked on your own>`.'
    }
    Write-Context 'UserPromptSubmit' $text
} catch {
    [Console]::Error.WriteLine("cheap-model-router prompt-submit: $_")
}
exit 0
