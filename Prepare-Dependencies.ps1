param([string]$PackagePath = '')

$ErrorActionPreference = 'Stop'
$version = '7.8.10'
# Verified against the official PowerShell Gallery package. Update only after reviewing a new package.
$expectedPackageHash = 'd8a1d79dc8cf10c0eea30b68b70459b3fb4cac0042fb756fcb23890671857e4c'
$destination = Join-Path $PSScriptRoot ('Modules\ImportExcel\' + $version)
$stagingDirectory = $destination + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
$backupDirectory = $destination + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
$finalDestination = $destination
$temporaryPackage = $PackagePath
$downloaded = $false
if ([string]::IsNullOrWhiteSpace($temporaryPackage)) {
    $temporaryPackage = Join-Path ([System.IO.Path]::GetTempPath()) ('ImportExcel.' + $version + '.' + [guid]::NewGuid().ToString('N') + '.nupkg')
    Invoke-WebRequest -Uri ('https://www.powershellgallery.com/api/v2/package/ImportExcel/' + $version) -OutFile $temporaryPackage -UseBasicParsing
    $downloaded = $true
}
try {
    $hash = (Get-FileHash -LiteralPath $temporaryPackage -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne $expectedPackageHash) { throw 'ImportExcel 包 SHA-256 与已审核的官方版本不一致，原模块未修改。' }
    $checkPath = [IO.Path]::GetFullPath($finalDestination)
    while (-not [string]::IsNullOrWhiteSpace($checkPath)) {
        if ((Test-Path -LiteralPath $checkPath) -and ((Get-Item -LiteralPath $checkPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw '依赖目录不能包含链接。' }
        $checkPath = [IO.Path]::GetDirectoryName($checkPath)
    }
    $destination = $stagingDirectory
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($temporaryPackage, $destination)
    $manifest = Join-Path $destination 'ImportExcel.psd1'
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw 'ImportExcel 包结构无效。' }
    $metadata = Test-ModuleManifest -Path $manifest
    if ([version]$metadata.Version -ne [version]$version) { throw "ImportExcel 版本不正确：$($metadata.Version)" }
    [System.IO.File]::WriteAllText((Join-Path $destination 'PACKAGE-SHA256.txt'), ($hash + [Environment]::NewLine), (New-Object System.Text.UTF8Encoding($false)))
    $integrityEntries = @(Get-ChildItem -LiteralPath $destination -Recurse -File | Where-Object { $_.Extension -in @('.ps1','.psm1','.psd1','.dll') } | Sort-Object FullName | ForEach-Object {
        [ordered]@{ path = $_.FullName.Substring($destination.Length + 1).Replace('\','/'); sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
    })
    $integrityJson = $integrityEntries | ConvertTo-Json -Depth 3
    [System.IO.File]::WriteAllText((Join-Path $destination 'CONTENT-SHA256.json'), $integrityJson, (New-Object System.Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $finalDestination) { [IO.Directory]::Move($finalDestination, $backupDirectory) }
    try { [IO.Directory]::Move($stagingDirectory, $finalDestination) }
    catch {
        if (Test-Path -LiteralPath $backupDirectory) { [IO.Directory]::Move($backupDirectory, $finalDestination) }
        throw
    }
    if (Test-Path -LiteralPath $backupDirectory) { Write-Host "旧依赖已保留为备份：$backupDirectory" }
    Write-Host "ImportExcel $version 已准备完成。包 SHA-256：$hash" -ForegroundColor Green
} finally {
    if ($downloaded -and (Test-Path -LiteralPath $temporaryPackage)) { Remove-Item -LiteralPath $temporaryPackage -Force }
}
