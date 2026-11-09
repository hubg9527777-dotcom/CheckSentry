param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'Start-ComplianceCheck.ps1') -LibraryOnly
. (Join-Path $root 'Get-InstalledExtensions.ps1')
. (Join-Path $root 'Get-InstalledSoftware.ps1')
function Assert-Security([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Assert-Rejected([scriptblock]$Operation, [string]$Message) {
    $rejected = $false
    try { & $Operation | Out-Null } catch { $rejected = $true }
    Assert-Security $rejected $Message
}
foreach ($uriText in @('http://docs.google.com/test','https://docs.google.com:444/test','https://docs.google.com.attacker.test/test','https://googleusercontent.com.attacker.test/test','https://user:password@docs.google.com/test','http://127.0.0.1/test')) {
    Assert-Security (-not (Test-AllowedCloudDownloadUri -Uri ([Uri]$uriText))) "Unsafe redirect allowed: $uriText"
}
Assert-Security (Test-AllowedCloudDownloadUri -Uri ([Uri]'https://docs.google.com/test')) 'Google export host rejected.'
Assert-Security (Test-AllowedCloudDownloadUri -Uri ([Uri]'https://doc-test.googleusercontent.com/test')) 'Google content host rejected.'
Assert-Rejected { Get-GoogleSheetsExportUrl -Url 'https://docs.google.com:444/spreadsheets/d/123456789012345/' } 'Custom export port allowed.'
Assert-Security ((ConvertTo-SafeNoteHtml -Text '<img src=x onerror=alert(1)>' -Link 'javascript:alert(1)') -notmatch '<img|href=.javascript:') 'Note HTML injection.'
Assert-Security (-not (Test-LocalSoftwareIconPath -Path '\\attacker.test\share\icon.ico')) 'UNC icon path accepted.'
Assert-Security ((Get-LocalIconDataUri -Path '\\attacker.test\share\icon.ico') -eq '') 'UNC icon read accepted.'
Assert-Security (-not (Test-LocalExtensionIconPath -Path '\\attacker.test\share\icon.ico')) 'Browser extension UNC icon accepted.'
Assert-Security (-not (Test-LocalExtensionIconPath -Path '\\?\UNC\attacker.test\share\icon.ico')) 'Browser extension device UNC icon accepted.'
Assert-Security (-not (Test-LocalExtensionIconPath -Path 'file:///C:/sensitive/icon.ico')) 'Browser extension URL icon accepted as a disk path.'

$main = Get-Content -LiteralPath (Join-Path $root 'Start-ComplianceCheck.ps1') -Raw -Encoding UTF8
Assert-Security ($main -match '\$request.AllowAutoRedirect = \$false') 'Cloud download must validate every redirect.'
Assert-Security ($main -notmatch '\$request.QueryString\[''refresh''\]') 'GET must not initiate cloud sync and rescan.'
$request = [PSCustomObject]@{ HttpMethod='POST'; Url=[Uri]'http://localhost:8787/api/scan'; ContentType='application/json'; Headers=@{ 'X-CheckSentry-Token'='test'; Origin='https://attacker.test' }; ContentLength64=2 }
Assert-Rejected { Assert-AuthorizedPostRequest -Request $request -CsrfToken 'test' } 'Cross-origin POST accepted.'
$request.Headers.Origin = 'http://localhost:8787'
$request.Headers['X-CheckSentry-Token'] = 'wrong'
Assert-Rejected { Assert-AuthorizedPostRequest -Request $request -CsrfToken 'test' } 'Invalid CSRF token accepted.'
$request.Headers['X-CheckSentry-Token'] = 'test'
Assert-AuthorizedPostRequest -Request $request -CsrfToken 'test'
$cookieName = 'CheckSentrySession_8787'
$sessionId = New-RandomToken -ByteCount 32
$sessions = @{}
$sessions[$sessionId] = @{ CsrfToken = (New-RandomToken -ByteCount 32); Unlocked = $false }
$cookieRequest = [PSCustomObject]@{ Url = [Uri]'http://localhost:8787/'; Cookies = @{} }
Assert-Security ($null -eq (Get-ReportSession $cookieRequest $sessions $cookieName)) 'Anonymous session accepted.'
$cookieRequest.Cookies[$cookieName] = [PSCustomObject]@{ Value = 'f' * 64 }
Assert-Security ($null -eq (Get-ReportSession $cookieRequest $sessions $cookieName)) 'Unknown session accepted.'
$cookieRequest.Cookies[$cookieName].Value = $sessionId
Assert-Security ($null -ne (Get-ReportSession $cookieRequest $sessions $cookieName)) 'Valid browser session rejected.'
$cookieRequest.Url = [Uri]'http://attacker.test:8787/'
Assert-Security ($null -eq (Get-ReportSession $cookieRequest $sessions $cookieName)) 'Foreign host session accepted.'
$secondId = New-RandomToken -ByteCount 32
$sessions[$secondId] = @{ CsrfToken = (New-RandomToken -ByteCount 32); Unlocked = $false }
$sessions[$sessionId].Unlocked = $true
Assert-Security (-not $sessions[$secondId].Unlocked) 'Takeover privileges leaked between sessions.'
Assert-Security ($sessions[$sessionId].CsrfToken -cne $sessions[$secondId].CsrfToken) 'Sessions share a CSRF token.'
$bootstrap = Get-SessionBootstrapHtml -Nonce 'test-nonce'
Assert-Security ($bootstrap.Contains("history.replaceState(null, '', '/')")) 'Bootstrap must remove fragment token from history.'
Assert-Security (-not $bootstrap.Contains($sessionId)) 'Bootstrap must not disclose session secrets.'
$request | Add-Member -NotePropertyName InputStream -NotePropertyValue ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes(('x' * ($script:MaxRequestChars + 1)))))
Assert-Rejected { Read-JsonRequestBody -Request $request } 'Oversized streamed body accepted.'
$request.InputStream.Dispose()

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('CheckSentry-security-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixture
try {
    Assert-XlsxArchiveComplete -Path (Join-Path $root 'list_template.xlsx')
    $zipPath = Join-Path $fixture 'malicious.xlsx'
    $zip = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($entryName in @('[Content_Types].xml','xl/workbook.xml')) {
            $entry = $zip.CreateEntry($entryName)
            $writer = New-Object IO.StreamWriter($entry.Open())
            try { $writer.Write('<!DOCTYPE workbook [<!ENTITY payload "boom">]><workbook>&payload;</workbook>') } finally { $writer.Dispose() }
        }
    } finally { $zip.Dispose() }
    Assert-Rejected { Assert-XlsxArchiveComplete -Path $zipPath } 'XLSX DTD/entity payload accepted.'
    Assert-Rejected { Import-CloudRuleSheets -Path $zipPath } 'Cloud rule snapshot bypassed XLSX preflight.'
    $oversizedJson = Join-Path $fixture 'oversized.json'
    $stream = [IO.File]::Create($oversizedJson)
    try { $stream.SetLength(33554433) } finally { $stream.Dispose() }
    Assert-Rejected { Read-BrowserJsonDocument -Path $oversizedJson -MaxAttempts 1 } 'Oversized browser JSON accepted.'
    $badPackage = Join-Path $fixture 'bad.nupkg'
    [IO.File]::WriteAllText($badPackage, 'not the verified package')
    Assert-Rejected { & (Join-Path $root 'Prepare-Dependencies.ps1') -PackagePath $badPackage } 'Untrusted module package accepted.'
    $sentinel = Join-Path $fixture 'keep.txt'
    [IO.File]::WriteAllText($sentinel, 'keep')
    Assert-Rejected { & (Join-Path $root 'Build-Release.ps1') -OutputDirectory $fixture } 'Nonempty build directory accepted.'
    Assert-Security (Test-Path -LiteralPath $sentinel) 'Build removed existing user files.'
    Assert-Rejected { & (Join-Path $root 'Build-Release.ps1') -Version '../outside' -OutputDirectory (Join-Path $fixture 'output') } 'Unsafe version path accepted.'
} finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force
}
# Windows PowerShell 5.1 reads BOM-less non-ASCII scripts as the system ANSI codepage.
# Check all project scripts so a newly added diagnostic cannot silently break release builds.
foreach ($scriptFile in @(Get-ChildItem -LiteralPath $root -Filter '*.ps1') + @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1')) {
    $scriptBytes = [IO.File]::ReadAllBytes($scriptFile.FullName)
    $hasUtf8Bom = $scriptBytes.Length -ge 3 -and $scriptBytes[0] -eq 0xEF -and $scriptBytes[1] -eq 0xBB -and $scriptBytes[2] -eq 0xBF
    $hasNonAscii = $false
    foreach ($scriptByte in $scriptBytes) {
        if ($scriptByte -ge 128) { $hasNonAscii = $true; break }
    }
    Assert-Security (-not $hasNonAscii -or $hasUtf8Bom) "UTF-8 BOM required for Windows PowerShell 5.1: $($scriptFile.Name)"

    $tokens = $null; $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($scriptFile.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        $errorDetails = @($errors | ForEach-Object {
            '{0}:{1}: {2}' -f $_.Extent.StartLineNumber, $_.Extent.StartColumnNumber, $_.Message
        }) -join '; '
        throw "PowerShell parse error: $($scriptFile.Name): $errorDetails"
    }
}
Write-Host 'CheckSentry security regression tests passed.' -ForegroundColor Green
