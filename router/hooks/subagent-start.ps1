# SubagentStart: tell editing workers to ask the project's graphify graph first, when one exists.
# Scouts are left out on purpose; only the workers listed in config "graph_workers" get the hint.
. "$PSScriptRoot\common.ps1"
try {
    $hook = Read-HookInput
    if (-not $hook) { exit 0 }
    $config = Get-RouterConfig
    $graphWorkers = if ($config.graph_workers) { @($config.graph_workers) } else { @('haiku-worker', 'sonnet-worker', 'roblox-worker') }
    if ($graphWorkers -notcontains [string]$hook.agent_type) { exit 0 }

    # Look for graphify-out/graph.json in the working folder and up to 3 parents.
    $dir = [string]$hook.cwd
    $graph = $null
    for ($i = 0; $i -le 3 -and $dir; $i++) {
        $candidate = Join-Path $dir 'graphify-out\graph.json'
        if (Test-Path $candidate) { $graph = $candidate; break }
        $dir = Split-Path $dir -Parent
    }
    if (-not $graph) { exit 0 }

    $cli = Get-Command graphify -ErrorAction SilentlyContinue
    if (-not $cli) { exit 0 }

    $g = $graph.Replace('\', '/')
    $text = "[router] This project has a graphify knowledge graph ($g). Before searching files, run: graphify query ""<your question>"" --budget 1500 --graph ""$g"" (also: graphify path ""A"" ""B"" --graph ..., graphify explain ""X"" --graph ...). Use it as a map to find the right files; it can be out of date, so read the real file before editing. If it gives nothing useful, search normally. One or two queries are enough."
    Write-Context 'SubagentStart' $text
} catch {
    [Console]::Error.WriteLine("cheap-model-router subagent-start: $_")
}
exit 0
