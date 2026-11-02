# SubagentStop: log each worker run - task, type, status, confidence, tokens, cost and estimated savings vs Opus.
. "$PSScriptRoot\common.ps1"
try {
    $hook = Read-HookInput
    if (-not $hook) { exit 0 }
    $config = Get-RouterConfig
    if ($config.workers -notcontains [string]$hook.agent_type) { exit 0 }

    $t = Read-WorkerTranscript ([string]$hook.agent_transcript_path) $config
    $report = Get-ReportFields @([string]$hook.last_assistant_message, $t.handback, $t.last_text)
    $family = if ($t.model) { Get-ModelFamily $t.model } elseif ($hook.agent_type -like 'haiku-*') { 'haiku' } else { 'sonnet' }

    Add-LogEntry @{
        ev = 'worker'; session = $hook.session_id; prompt_id = $hook.prompt_id; agent_id = $hook.agent_id
        agent = $hook.agent_type; family = $family; model = $t.model; task = $t.task; type = $(if ($t.type) { $t.type } else { 'unknown' })
        status = $report.status; confidence = $report.confidence; partial_why = $report.partial_why
        tokens = $t.usage
        cost = [math]::Round($t.cost, 5); opus_cost = [math]::Round($t.opus_cost, 5); saved = [math]::Round($t.opus_cost - $t.cost, 5)
    }
} catch {
    [Console]::Error.WriteLine("cheap-model-router subagent-stop: $_")
}
exit 0
