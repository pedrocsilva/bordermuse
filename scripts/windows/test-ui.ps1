param([Parameter(Mandatory=$true)][string]$AppPath,[Parameter(Mandatory=$true)][string]$ReportDirectory)
$ErrorActionPreference = 'Stop'
$previous = $env:BORDERMUSE_SMOKE_DIR
$runtimeEnvironment = @{}
foreach ($name in @('DOTNET_ROOT','DOTNET_ROOT_X64','DOTNET_MULTILEVEL_LOOKUP')) {
    $runtimeEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
try {
    New-Item -ItemType Directory -Force $ReportDirectory | Out-Null
    $env:BORDERMUSE_SMOKE_DIR = (Resolve-Path $ReportDirectory).Path
    # Force the app to rely on its published runtimes instead of the runner SDK.
    $env:DOTNET_ROOT = Join-Path $env:BORDERMUSE_SMOKE_DIR 'missing-system-runtime'
    $env:DOTNET_ROOT_X64 = $env:DOTNET_ROOT
    $env:DOTNET_MULTILEVEL_LOOKUP = '0'
    $process = Start-Process -FilePath (Resolve-Path $AppPath).Path -PassThru
    if (-not $process.WaitForExit(120000)) { Stop-Process -Id $process.Id -Force; throw 'Native UI smoke test timed out.' }
    if ($process.ExitCode -ne 0) {
        if (Test-Path "$ReportDirectory/failure.txt") { Get-Content "$ReportDirectory/failure.txt" }
        Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddMinutes(-3)} -ErrorAction SilentlyContinue |
            Where-Object { $_.ProviderName -in @('.NET Runtime','Application Error') } | Select-Object -First 4 Message | Format-List
        throw "Native app exited with code $($process.ExitCode)."
    }
    $report = Get-Content "$ReportDirectory/report.json" | ConvertFrom-Json
    if (-not $report.passed) { throw 'Native UI smoke test did not pass.' }
    $report | ConvertTo-Json
} finally {
    $env:BORDERMUSE_SMOKE_DIR = $previous
    foreach ($name in $runtimeEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $runtimeEnvironment[$name], 'Process')
    }
}
