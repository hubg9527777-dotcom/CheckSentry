# CheckSentry 1.2.0 read-only, redacted coverage diagnosis.
# Does not output application names, user SIDs, full paths or raw event contents.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Get-ExecutionHistory.ps1')
$report = Get-CheckSentryExecutionHistory
Write-Host 'CheckSentry 1.2.0 历史证据来源状态（无个人路径）'
foreach ($item in @($report.Sources)) {
    '{0}: {1}; Found={2}; Parsed={3}; Failed={4}' -f $item.Source, $item.Status, $item.Found, $item.Parsed, $item.Failed
}
Write-Host ('合并前的证据条数：' + @($report.Items).Count)
Write-Host '注意：没有足够权限或系统没有留存记录时，这不是完整的执行历史。'
