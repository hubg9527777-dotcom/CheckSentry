# CheckSentry 1.2.0 - local, read-only execution evidence acquisition.
# Prefetch only proves executable launches; bat/cmd evidence requires pre-enabled Security 4688 command lines.
# No telemetry, no network calls, no registry writes and no process monitoring service.

function Initialize-CheckSentryPrefetchReader {
    if ($null -ne ('CheckSentry.PrefetchReader' -as [type])) { return }
    $code = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace CheckSentry {
  public class PrefetchRecord {
    public string Name { get; set; }
    public string Hash { get; set; }
    public int RunCount { get; set; }
    public DateTime[] TimesUtc { get; set; }
    public string[] ReferencedPaths { get; set; }
    public int Version { get; set; }
  }
  public static class PrefetchReader {
    [DllImport("ntdll.dll", ExactSpelling = true)]
    private static extern int RtlGetCompressionWorkSpaceSize(ushort format, out uint compressSize, out uint fragmentSize);
    [DllImport("ntdll.dll", ExactSpelling = true)]
    private static extern int RtlDecompressBufferEx(ushort format, byte[] dst, uint dstSize,
      byte[] src, uint srcSize, out uint actualSize, IntPtr workSpace);

    public static PrefetchRecord Read(string file) {
      byte[] data = File.ReadAllBytes(file);
      if (data.Length > 16 * 1024 * 1024) throw new InvalidDataException("Prefetch file exceeds safe limit");
      if (data.Length > 8 && data[0] == 0x4D && data[1] == 0x41 && data[2] == 0x4D) {
        if ((data[3] & 0x7F) != 4) throw new InvalidDataException("Unsupported MAM compression");
        int expected = BitConverter.ToInt32(data, 4);
        if (expected < 84 || expected > 32 * 1024 * 1024) throw new InvalidDataException("Invalid decompressed size");
        uint workspaceSize, fragmentSize, realSize;
        int status = RtlGetCompressionWorkSpaceSize(4, out workspaceSize, out fragmentSize);
        if (status != 0 || workspaceSize > 8 * 1024 * 1024) throw new InvalidDataException("No XPRESS workspace");
        int workspaceBytes = checked((int)workspaceSize);
        if (workspaceBytes < 1) workspaceBytes = 1;
        IntPtr workSpace = Marshal.AllocHGlobal(workspaceBytes);
        try {
          byte[] compressed = new byte[data.Length - 8];
          Buffer.BlockCopy(data, 8, compressed, 0, compressed.Length);
          byte[] expanded = new byte[expected];
          status = RtlDecompressBufferEx(4, expanded, (uint)expanded.Length,
            compressed, (uint)compressed.Length, out realSize, workSpace);
          if (status != 0 || realSize != expected) throw new InvalidDataException("XPRESS decode failed");
          data = expanded;
        } finally { Marshal.FreeHGlobal(workSpace); }
      }
      if (data.Length < 160 || Encoding.ASCII.GetString(data, 4, 4) != "SCCA")
        throw new InvalidDataException("Invalid prefetch header");
      int version = BitConverter.ToInt32(data, 0);
      // Supported Windows 8+ file-info layouts (including Windows 10 v30 variants and Windows 11 v31).
      if (version != 26 && version != 30 && version != 31)
        throw new InvalidDataException("Unsupported Prefetch version " + version);
      // Prefetch header is 84 bytes. The file-info block starts at 0x54 (84).
      // Its first DWORD (metrics offset) is at 84, while the *header* field at 80
      // is the prefetch hash. See libscca file-info layout: 304/296 at offset 84.
      int metricsOffset = BitConverter.ToInt32(data, 84);
      if (metricsOffset != 304 && metricsOffset != 296)
        throw new InvalidDataException("Unknown file-info layout: " + metricsOffset);
      int runOffset = metricsOffset == 304 ? 208 : 200;
      if (data.Length <= runOffset + 4) throw new InvalidDataException("Incomplete Prefetch header");
      int runs = BitConverter.ToInt32(data, runOffset);
      if (runs < 0 || runs > 100000000) throw new InvalidDataException("Bad run count");
      string name = Encoding.Unicode.GetString(data, 16, 60).TrimEnd('\0').Trim();
      if (name.Length == 0) throw new InvalidDataException("Missing executable name");
      var times = new List<DateTime>();
      for (int pos = 128; pos < 192; pos += 8) {
        long ticks = BitConverter.ToInt64(data, pos);
        if (ticks <= 0) continue;
        try {
          DateTime stamp = DateTime.FromFileTimeUtc(ticks);
          if (stamp.Year >= 2000 && stamp.Year <= 2200 && !times.Contains(stamp)) times.Add(stamp);
        } catch (ArgumentOutOfRangeException) {}
      }
      int filenameOffset = BitConverter.ToInt32(data, 100);
      int filenameSize = BitConverter.ToInt32(data, 104);
      var paths = new List<string>();
      if (filenameOffset > 0 && filenameSize > 0 && filenameSize <= 16 * 1024 * 1024 &&
          filenameOffset <= data.Length - filenameSize && filenameSize % 2 == 0) {
        string fullText = Encoding.Unicode.GetString(data, filenameOffset, filenameSize);
        foreach (string entry in fullText.Split('\0')) {
          if (entry.Length > 4 && entry.Length < 2048) paths.Add(entry);
        }
      }
      return new PrefetchRecord { Name = name, Hash = BitConverter.ToUInt32(data, 76).ToString("X8"),
        RunCount = runs, TimesUtc = times.ToArray(), ReferencedPaths = paths.ToArray(), Version = version };
    }
  }
}
'@
    Add-Type -TypeDefinition $code -ErrorAction Stop
}

function Get-CheckSentryVolumeMap {
    # A Prefetch \\VOLUME{creation-filetime-serial} marker can be mapped by exact NTFS volume serial.
    $mapping = @{}
    try {
        foreach ($volume in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 3 OR DriveType = 2' -ErrorAction Stop)) {
            $serial = ([string]$volume.VolumeSerialNumber).Replace('-', '').Trim().ToUpperInvariant()
            if ($serial -match '^[0-9A-F]{8}$' -and [string]$volume.DeviceID -match '^[A-Za-z]:$') {
                if (-not $mapping.ContainsKey($serial)) { $mapping[$serial] = @() }
                $mapping[$serial] += [string]$volume.DeviceID
            }
        }
    } catch { }
    return $mapping
}

function ConvertFrom-CheckSentryPrefetchPath {
    param([string]$RawPath, [hashtable]$VolumeMap)
    if ($RawPath -match '^[A-Za-z]:\\') { return $RawPath }
    if ($RawPath -match '^\\VOLUME\{[0-9a-fA-F]{16}-([0-9a-fA-F]{8})\}\\(.+)$') {
        $volumeSerial = $matches[1].ToUpperInvariant()
        $remaining = $matches[2]
        if ($VolumeMap.ContainsKey($volumeSerial) -and @($VolumeMap[$volumeSerial]).Count -eq 1) {
            return ([string]$VolumeMap[$volumeSerial][0] + '\' + $remaining)
        }
    }
    return ''
}

function Get-CheckSentryPfEvidence {
    $folder = Join-Path $env:WINDIR 'Prefetch'
    $meta = [ordered]@{ Source = 'Prefetch'; Status = '未扫描'; Found = 0; Parsed = 0; Failed = 0; Message = '' }
    $records = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        $meta.Status = '不可用'; $meta.Message = '未发现 Prefetch 目录，可能已关闭或未保留记录。'
        return [PSCustomObject]@{ Items = @(); Meta = [PSCustomObject]$meta }
    }
    try {
        $prefetchFiles = @(Get-ChildItem -LiteralPath $folder -Filter '*.pf' -File -ErrorAction Stop)
    } catch {
        $meta.Status = '权限不足'; $meta.Message = '不能读取 Windows Prefetch，请以管理员权限启动 CheckSentry。'
        return [PSCustomObject]@{ Items = @(); Meta = [PSCustomObject]$meta }
    }
    $meta.Found = $prefetchFiles.Count
    if ($prefetchFiles.Count -eq 0) {
        $meta.Status = '无记录'; $meta.Message = 'Prefetch 中没有保留的 .pf 文件，不代表软件从未执行。'
        return [PSCustomObject]@{ Items = @(); Meta = [PSCustomObject]$meta }
    }
    try { Initialize-CheckSentryPrefetchReader } catch {
        $meta.Status = '解析器失败'; $meta.Message = "Windows Prefetch 解析组件初始化失败：$($_.Exception.Message)"
        return [PSCustomObject]@{ Items = @(); Meta = [PSCustomObject]$meta }
    }
    $volumeMap = Get-CheckSentryVolumeMap
    $failureKinds = @{}
    foreach ($pf in $prefetchFiles) {
        try {
            $data = [CheckSentry.PrefetchReader]::Read($pf.FullName)
            $meta.Parsed++
            # Prefetch references include DLLs and documents; ONLY use a path whose last component matches the launched EXE.
            $candidates = @()
            foreach ($raw in @($data.ReferencedPaths)) {
                if ([string]::IsNullOrWhiteSpace($raw)) { continue }
                $leaf = [IO.Path]::GetFileName(([string]$raw).TrimEnd('\'))
                # Prefetch executable names are truncated at 29 characters.
                # Short names must match exactly; prefix-only matching could pick an unrelated EXE.
                $pfName = [string]$data.Name
                if ($pfName.Length -ge 29) {
                    if (-not $leaf.StartsWith($pfName, [StringComparison]::OrdinalIgnoreCase)) { continue }
                } elseif (-not [string]::Equals($leaf, $pfName, [StringComparison]::OrdinalIgnoreCase)) { continue }
                if ($leaf -notmatch '(?i)\.(exe|com|scr)$') { continue }
                $resolved = ConvertFrom-CheckSentryPrefetchPath -RawPath $raw -VolumeMap $volumeMap
                if ($resolved -match '^[A-Za-z]:\\') {
                    $candidates += [IO.Path]::GetFullPath($resolved)
                }
            }
            $candidates = @($candidates | Select-Object -Unique)
            $present = @($candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
            $path = if ($present.Count -eq 1) { [string]$present[0] }
                elseif ($candidates.Count -eq 1) { [string]$candidates[0] }
                else { '' }
            $fileStillExists = [bool]($path -and (Test-Path -LiteralPath $path -PathType Leaf))
            $displayName = if ($path) { [IO.Path]::GetFileName($path) } else { [string]$data.Name }
            $records.Add([PSCustomObject]@{
                Kind = 'EXE'; Name = $displayName; Path = $path
                PathEvidence = if ($path) { 'Prefetch 文件引用路径（未验证哈希）' } else { '未知' }
                PathVerified = $false; PfHash = [string]$data.Hash
                RunCount = [int]$data.RunCount
                Times = @($data.TimesUtc | ForEach-Object { ([datetime]$_).ToLocalTime() })
                Source = 'Prefetch'; FileExists = $fileStillExists
            })
        } catch {
            $meta.Failed++
            $reason = [string]$_.Exception.Message
            if ([string]::IsNullOrWhiteSpace($reason)) { $reason = '未知错误' }
            # Do not print the source filename or any personal paths into the UI.
            if ($reason.Length -gt 120) { $reason = $reason.Substring(0,120) }
            if (-not $failureKinds.ContainsKey($reason)) { $failureKinds[$reason] = 0 }
            $failureKinds[$reason]++
        }
    }
    $meta.Status = if ($meta.Failed -gt 0) { '部分完成' } else { '完成' }
    $reasonSummary = (@($failureKinds.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 2 | ForEach-Object { "$($_.Name) ×$($_.Value)" }) -join '；')
    $meta.Message = "读取 $($meta.Parsed)/$($meta.Found) 个 Prefetch 文件；失败 $($meta.Failed) 个。位置为文件引用推断，不等于哈希验证。"
    if ($reasonSummary) { $meta.Message += " 失败原因：$reasonSummary" }
    return [PSCustomObject]@{ Items = @($records.ToArray()); Meta = [PSCustomObject]$meta }
}

# CheckSentry 1.2.0: third-party PECmd execution is intentionally NOT supported.
# User approval is required before any future download, packaging or execution.
# .NET 10 is used by the launcher; PowerShell's built-in Prefetch reader
# remains a separate component and requires Windows accuracy validation.

function Get-CheckSentryRunningProcessEvidence {
    $meta = [ordered]@{ Source = '当前进程'; Status = '未完成'; Found = 0; Parsed = 0; Failed = 0; Message = '' }
    $items = New-Object System.Collections.Generic.List[object]
    try {
        $processes = @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop)
        $meta.Found = $processes.Count
        foreach ($process in $processes) {
            try {
                $path = [string]$process.ExecutablePath
                if ($path -notmatch '(?i)^[A-Za-z]:\\.*\.(exe|com|scr)$') { continue }
                $items.Add([PSCustomObject]@{
                    Kind = 'EXE'; Name = [IO.Path]::GetFileName($path); Path = $path
                    PathEvidence = '当前进程报告的可执行文件路径'; PathVerified = $true
                    PfHash = ''; RunCount = 0; Times = @(); Source = '当前运行'
                    FileExists = (Test-Path -LiteralPath $path -PathType Leaf)
                })
                $meta.Parsed++
            } catch { $meta.Failed++ }
        }
        $meta.Status = if ($meta.Failed -gt 0) { '部分完成' } else { '完成' }
        $meta.Message = '当前时刻的进程快照；不表示昨天运行过。访问受限的进程可能缺失路径。'
    } catch { $meta.Status = '失败'; $meta.Message = '无法读取当前进程：' + $_.Exception.Message }
    return [PSCustomObject]@{ Items = @($items.ToArray()); Meta = [PSCustomObject]$meta }
}

function Get-CheckSentryEventEvidence {
    $meta = [ordered]@{ Source = '4688'; Status = '未启用或不可访问'; Found = 0; Parsed = 0; Failed = 0; Message = '' }
    $items = New-Object System.Collections.Generic.List[object]
    $limit = 8000
    try {
        $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4688; StartTime = (Get-Date).AddDays(-30) } -MaxEvents $limit -ErrorAction Stop)
    } catch {
        $meta.Message = '无法读取进程创建事件（未开启审计、没有匹配事件或访问权限不足）。BAT/CMD 历史因此无法可靠恢复。'
        return [PSCustomObject]@{ Items = @(); Meta = [PSCustomObject]$meta }
    }
    $meta.Found = $events.Count
    $meta.Status = '完成'
    $meta.Message = if ($events.Count -ge $limit) { "只读取最近 $limit 条 4688 事件，较早记录可能被截断。" } else { '仅在启用了进程创建审计时产生记录。BAT/CMD 需要事先启用命令行记录。' }
    foreach ($event in $events) {
        try {
            [xml]$xml = $event.ToXml()
            $fields = @{}
            foreach ($node in @($xml.Event.EventData.Data)) { $fields[[string]$node.Name] = [string]$node.'#text' }
            $executable = [string]$fields['NewProcessName']
            if ($executable -match '^[A-Za-z]:\\.*\.(exe|com|scr)$') {
                $items.Add([PSCustomObject]@{
                    Kind = 'EXE'; Name = [IO.Path]::GetFileName($executable); Path = $executable
                    PathEvidence = 'Windows 安全事件 4688'; PathVerified = $true; PfHash = ''
                    RunCount = 0; Times = @($event.TimeCreated); Source = '4688'
                    FileExists = (Test-Path -LiteralPath $executable -PathType Leaf)
                })
            }
            # Read command line solely to extract absolute .bat/.cmd paths. Never retain or display command arguments.
            $cmdline = [string]$fields['CommandLine']
            if ($cmdline -and $executable -match '(?i)\\cmd\.exe$') {
                # Only a direct cmd /c or cmd /k invocation is treated as a script execution lead.
                $match = [regex]::Match($cmdline, '(?i)(?:/c|/k)\s+"*\s*(?<path>[a-z]:\\[^"<>|?*\r\n]*?\.(?:bat|cmd))(?=\s|"|$)')
                if ($match.Success) {
                    $scriptPath = $match.Groups['path'].Value.Trim().TrimEnd('"')
                    $items.Add([PSCustomObject]@{
                        Kind = '脚本'; Name = [IO.Path]::GetFileName($scriptPath); Path = $scriptPath
                        PathEvidence = '4688 命令行提取'; PathVerified = $true; PfHash = ''
                        RunCount = 0; Times = @($event.TimeCreated); Source = '4688'
                        FileExists = (Test-Path -LiteralPath $scriptPath -PathType Leaf)
                    })
                }
            }
            $meta.Parsed++
        } catch { $meta.Failed++ }
    }
    if ($meta.Failed -gt 0) { $meta.Status = '部分完成' }
    return [PSCustomObject]@{ Items = @($items.ToArray()); Meta = [PSCustomObject]$meta }
}

# BAM: a Windows-native execution history stored per user SID. No third-party tools.
# Device paths require an exact drive mapping, otherwise the location remains unknown.
function Initialize-CheckSentryDosDeviceMapper {
    if ($null -ne ('CheckSentry.DosDeviceMapper' -as [type])) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
namespace CheckSentry {
 public static class DosDeviceMapper {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern uint QueryDosDevice(string deviceName, StringBuilder target, uint maxChars);
 }
}
'@ -ErrorAction Stop
}

function Get-CheckSentryDeviceMap {
    $mapping = @{}
    try {
        Initialize-CheckSentryDosDeviceMapper
        foreach ($disk in @(Get-CimInstance Win32_LogicalDisk -ErrorAction Stop | Where-Object { $_.DeviceID -match '^[A-Za-z]:$' })) {
            $drive = [string]$disk.DeviceID
            $buffer = New-Object System.Text.StringBuilder 4096
            if ([CheckSentry.DosDeviceMapper]::QueryDosDevice($drive, $buffer, 4096) -eq 0) { continue }
            $ntTarget = ($buffer.ToString() -split [char]0)[0]
            if ($ntTarget -match '^\\Device\\HarddiskVolume\d+$') { $mapping[$ntTarget.ToUpperInvariant()] = $drive }
        }
    } catch { }
    return $mapping
}

function ConvertFrom-CheckSentryDevicePath {
    param([string]$Raw, [hashtable]$Map)
    if ($Raw -match '(?i)^[a-z]:\\') { return $Raw }
    if ($Raw -match '(?i)^(\\Device\\HarddiskVolume\d+)(\\.+)$') {
        $prefix = $matches[1].ToUpperInvariant()
        if ($Map.ContainsKey($prefix)) { return [string]$Map[$prefix] + [string]$matches[2] }
    }
    return ''
}

function Get-CheckSentryBamEvidence {
    $meta = [ordered]@{ Source='BAM'; Status='未扫描'; Found=0; Parsed=0; Failed=0; Message='' }
    $items = New-Object System.Collections.Generic.List[object]
    $roots = @('Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\bam\State\UserSettings',
               'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\bam\UserSettings')
    $rootPath = @($roots | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)
    if ($rootPath.Count -eq 0) {
        $meta.Status='不可用'; $meta.Message='系统没有可读取的 BAM 记录。'
        return [PSCustomObject]@{ Items=@(); Meta=[PSCustomObject]$meta }
    }
    try { $keys = @(Get-ChildItem -LiteralPath $rootPath[0] -ErrorAction Stop) }
    catch {
        $meta.Status='权限不足'; $meta.Message='当前账户不能读取 BAM 用户执行记录。'
        return [PSCustomObject]@{ Items=@(); Meta=[PSCustomObject]$meta }
    }
    $map = Get-CheckSentryDeviceMap
    foreach ($key in $keys) {
        try {
            $registryKey = Get-Item -LiteralPath $key.PSPath -ErrorAction Stop
            foreach ($valueName in @($registryKey.GetValueNames())) {
                $raw = [string]$valueName
                if ($raw -notmatch '(?i)\.(exe|com|scr)$') { continue }
                $meta.Found++
                try {
                    $bytes = $registryKey.GetValue($valueName, $null)
                    if (-not ($bytes -is [byte[]]) -or $bytes.Length -lt 8) { continue }
                    $utc = [DateTime]::FromFileTimeUtc([BitConverter]::ToInt64($bytes, 0))
                    if ($utc.Year -lt 2000 -or $utc -gt [DateTime]::UtcNow.AddDays(1)) { continue }
                    $mapped = ConvertFrom-CheckSentryDevicePath -Raw $raw -Map $map
                    $name = [IO.Path]::GetFileName($raw)
                    if (-not $name) { continue }
                    $items.Add([PSCustomObject]@{
                        Kind='EXE'; Name=$name; Path=$mapped
                        PathEvidence=if ($mapped) { 'BAM 注册表记录的执行路径' } else { 'BAM 记录（设备路径无法映射）' }
                        PathVerified=[bool]$mapped; PfHash=''; RunCount=0
                        Times=@($utc.ToLocalTime()); Source='BAM'
                        FileExists=[bool]($mapped -and (Test-Path -LiteralPath $mapped -PathType Leaf))
                    })
                    $meta.Parsed++
                } catch { $meta.Failed++ }
            }
        } catch { $meta.Failed++ }
    }
    $meta.Status=if ($meta.Failed -gt 0) { '部分完成' } else { '完成' }
    $meta.Message="BAM 提供部分程序的最近执行时间；读取 $($meta.Parsed) 条，失败 $($meta.Failed) 条；不包含全部历史或命令行。"
    return [PSCustomObject]@{ Items=@($items.ToArray()); Meta=[PSCustomObject]$meta }
}

# Per-user Explorer interaction evidence, less conclusive than Prefetch/BAM/4688.
# A GUI interaction can be logged without a process actually being launched.
function ConvertFrom-CheckSentryRot13 {
    param([string]$Value)
    $chars=$Value.ToCharArray()
    for ($i=0; $i -lt $chars.Length; $i++) {
        $n=[int][char]$chars[$i]
        if ($n -ge 65 -and $n -le 90) { $chars[$i]=[char](65+(($n-65+13)%26)) }
        elseif ($n -ge 97 -and $n -le 122) { $chars[$i]=[char](97+(($n-97+13)%26)) }
    }
    return -join $chars
}

function Get-CheckSentryUserAssistEvidence {
    $meta=[ordered]@{ Source='UserAssist'; Status='未扫描'; Found=0; Parsed=0; Failed=0; Message='' }
    $items=New-Object System.Collections.Generic.List[object]
    $root='Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist'
    if (-not (Test-Path -LiteralPath $root)) {
        $meta.Status='不可用'; $meta.Message='当前用户没有可读取的 UserAssist 记录。'
        return [PSCustomObject]@{ Items=@(); Meta=[PSCustomObject]$meta }
    }
    try { $keys=@(Get-ChildItem -LiteralPath $root -ErrorAction Stop) }
    catch {
        $meta.Status='权限不足'; $meta.Message='无法访问当前用户的 UserAssist。'
        return [PSCustomObject]@{ Items=@(); Meta=[PSCustomObject]$meta }
    }
    foreach ($key in $keys) {
        try {
            $countKey=Get-Item -LiteralPath (Join-Path $key.PSPath 'Count') -ErrorAction Stop
            foreach ($encodedName in @($countKey.GetValueNames())) {
                $path=ConvertFrom-CheckSentryRot13 -Value ([string]$encodedName)
                if ($path -notmatch '(?i)^[A-Za-z]:\\.*\.(exe|com|scr)$') { continue }
                $meta.Found++
                try {
                    $bytes=$countKey.GetValue($encodedName, $null)
                    if (-not ($bytes -is [byte[]]) -or $bytes.Length -lt 68) { continue }
                    $ticks=[BitConverter]::ToInt64($bytes,60)
                    if ($ticks -le 0) { continue }
                    $utc=[DateTime]::FromFileTimeUtc($ticks)
                    if ($utc.Year -lt 2000 -or $utc -gt [DateTime]::UtcNow.AddDays(1)) { continue }
                    $items.Add([PSCustomObject]@{
                        Kind='EXE'; Name=[IO.Path]::GetFileName($path); Path=$path
                        PathEvidence='UserAssist：资源管理器交互（非确定的进程执行证明）'
                        PathVerified=$true; PfHash=''; RunCount=0
                        Times=@($utc.ToLocalTime()); Source='UserAssist'
                        FileExists=(Test-Path -LiteralPath $path -PathType Leaf)
                    })
                    $meta.Parsed++
                } catch { $meta.Failed++ }
            }
        } catch { continue }
    }
    $meta.Status=if ($meta.Failed -gt 0) { '部分完成' } else { '完成' }
    $meta.Message="UserAssist 仅作当前用户 GUI 交互线索；读取 $($meta.Parsed) 条，不能单独确认程序实际启动。"
    return [PSCustomObject]@{ Items=@($items.ToArray()); Meta=[PSCustomObject]$meta }
}

function Get-CheckSentryExecutionHistory {
    $prefetch = Get-CheckSentryPfEvidence
    $events = Get-CheckSentryEventEvidence
    $running = Get-CheckSentryRunningProcessEvidence
    $bam = Get-CheckSentryBamEvidence
    $userAssist = Get-CheckSentryUserAssistEvidence
    [PSCustomObject]@{
        Items = @($prefetch.Items) + @($events.Items) + @($running.Items) + @($bam.Items) + @($userAssist.Items)
        Sources = @($prefetch.Meta, $events.Meta, $running.Meta, $bam.Meta, $userAssist.Meta)
        CreatedAt = Get-Date
    }
}
