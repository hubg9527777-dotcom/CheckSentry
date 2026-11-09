# Run in Windows PowerShell 5.1 with the CheckSentry source package.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'Get-ExecutionHistory.ps1')
Initialize-CheckSentryPrefetchReader
$directory = Join-Path ([IO.Path]::GetTempPath()) ('CheckSentry-pf-fixture-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $directory | Out-Null
function Require([bool]$Valid,[string]$Message) { if (-not $Valid) { throw $Message } }
function Write-Int32([byte[]]$Bytes,[int]$Offset,[int]$Value) { [BitConverter]::GetBytes($Value).CopyTo($Bytes,$Offset) }
function Make-TestPrefetch([int]$FormatVersion,[int]$InfoOffset,[string]$Name,[string]$Path) {
    [byte[]]$bytes = New-Object byte[] 640
    Write-Int32 $bytes 0 $FormatVersion
    [Text.Encoding]::ASCII.GetBytes('SCCA').CopyTo($bytes,4)
    [Text.Encoding]::Unicode.GetBytes($Name).CopyTo($bytes,16)
    Write-Int32 $bytes 76 100
    Write-Int32 $bytes 84 $InfoOffset
    $runOffset = if ($InfoOffset -eq 304) { 208 } else { 200 }
    Write-Int32 $bytes $runOffset 4
    [BitConverter]::GetBytes(([datetime]'2026-11-07T14:30:00Z').ToFileTimeUtc()).CopyTo($bytes,128)
    $paths = [Text.Encoding]::Unicode.GetBytes($Path + [char]0 + 'C:\Doc\notes.txt' + [char]0)
    Write-Int32 $bytes 100 330
    Write-Int32 $bytes 104 $paths.Length
    [Array]::Copy($paths,0,$bytes,330,$paths.Length)
    $file = Join-Path $directory ($Name + '-' + $FormatVersion + '.pf')
    [IO.File]::WriteAllBytes($file,$bytes)
    return $file
}
try {
    $a = Make-TestPrefetch -FormatVersion 30 -InfoOffset 304 -Name 'DEMO.EXE' -Path 'C:\Test\DEMO.EXE'
    $b = Make-TestPrefetch -FormatVersion 31 -InfoOffset 296 -Name 'DEMO.EXE' -Path 'C:\Test\DEMO.EXE'
    $first = [CheckSentry.PrefetchReader]::Read($a)
    $second = [CheckSentry.PrefetchReader]::Read($b)
    Require ($first.RunCount -eq 4 -and $second.RunCount -eq 4) 'Run count offsets are wrong.'
    Require ($first.TimesUtc.Count -eq 1 -and $second.TimesUtc.Count -eq 1) 'Run timestamps not parsed.'
    Require ($first.Name -eq 'DEMO.EXE' -and $second.Name -eq 'DEMO.EXE') 'Executable name corrupted.'
    Require (@($first.ReferencedPaths | Where-Object { $_ -like '*.txt' }).Count -eq 1) 'Synthetic document reference not preserved for filtering.'
    $paths = @(ConvertFrom-CheckSentryPrefetchPath -RawPath 'C:\Test\DEMO.EXE' -VolumeMap @{})
    Require ($paths[0] -eq 'C:\Test\DEMO.EXE') 'Absolute path conversion is wrong.'
    $self = Make-TestPrefetch -FormatVersion 31 -InfoOffset 296 -Name 'CHECKSENTRY-1.2.0.EXE' -Path 'C:\Tools\CheckSentry-1.2.0.exe'
    $selfRec = [CheckSentry.PrefetchReader]::Read($self)
    Require ($selfRec.Name -eq 'CHECKSENTRY-1.2.0.EXE') 'CheckSentry executable name missing.'
    Require (@($selfRec.ReferencedPaths | Where-Object { $_ -eq 'C:\Tools\CheckSentry-1.2.0.exe' }).Count -eq 1) 'Portable CheckSentry EXE path missing from strings.'
    Require ((ConvertFrom-CheckSentryRot13 -Value 'P:\Grfg\Qrzb.rkr') -eq 'C:\Test\Demo.exe') 'ROT13 decoding incorrect.'
    Require ((ConvertFrom-CheckSentryDevicePath -Raw '\Device\HarddiskVolume3\Tools\Demo.exe' -Map @{ '\DEVICE\HARDDISKVOLUME3'='C:' }) -eq 'C:\Tools\Demo.exe') 'BAM device path conversion incorrect.'
    Write-Host 'Synthetic v30/v31, CheckSentry, UserAssist and BAM helpers PASS.' -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $directory -Force -Recurse -ErrorAction SilentlyContinue
}
