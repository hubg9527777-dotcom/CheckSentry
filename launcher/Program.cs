#nullable enable
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;

namespace CheckSentry.Launcher;

internal static class Program
{
    // 指定仅从 System32 目录加载系统 DLL，防止 DLL 预加载/劫持攻击
    [DllImport("user32.dll", EntryPoint = "MessageBoxW", CharSet = CharSet.Unicode, SetLastError = true, ExactSpelling = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    private static extern int MessageBox(IntPtr handle, string text, string caption, uint type);

    [DllImport("kernel32.dll", SetLastError = true, ExactSpelling = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetConsoleCP(uint codePageId);

    [DllImport("kernel32.dll", SetLastError = true, ExactSpelling = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetConsoleOutputCP(uint codePageId);

    private static readonly UTF8Encoding Utf8NoBom = new(false);

    private static int Main(string[] args)
    {
        string logPath = string.Empty;
        try
        {
            ConfigureConsoleEncoding();
            var forwarded = args.Where(a => !string.Equals(a, "--portable", StringComparison.OrdinalIgnoreCase)).ToArray();
            var dataDirectory = Path.GetFullPath(AppContext.BaseDirectory);
            Directory.CreateDirectory(dataDirectory);
            MigrateLegacyData(dataDirectory);

            var logDirectory = Path.Join(dataDirectory, "Logs");
            AssertNoReparsePoints(logDirectory);
            Directory.CreateDirectory(logDirectory);
            logPath = Path.Join(logDirectory, "CheckSentry-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".log");
            AssertNoReparsePoints(logPath);
            File.WriteAllText(logPath, "CheckSentry started " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + Environment.NewLine, Utf8NoBom);

            var assembly = typeof(Program).Assembly;
            var runtimeDirectory = Path.Join(dataDirectory, ".CheckSentryRuntime", assembly.ManifestModule.ModuleVersionId.ToString("N"));
            ExtractPayload(assembly, runtimeDirectory);
            var scriptPath = Path.Join(runtimeDirectory, "Start-ComplianceCheck.ps1");
            var listPath = Path.Join(dataDirectory, "list.xlsx");

            var startInfo = new ProcessStartInfo
            {
                FileName = Path.Join(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe"),
                UseShellExecute = false,
                WorkingDirectory = runtimeDirectory,
                RedirectStandardOutput = false,
                RedirectStandardError = false
            };
            foreach (var argument in new[] { "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", scriptPath, "-ListPath", listPath, "-LogPath", logPath })
                startInfo.ArgumentList.Add(argument);
            foreach (var argument in forwarded)
                startInfo.ArgumentList.Add(argument);

            using var process = new Process { StartInfo = startInfo };
            if (!process.Start()) throw new InvalidOperationException("无法启动 Windows PowerShell。");
            process.WaitForExit();
            if (process.ExitCode != 0)
            {
                var message = "CheckSentry 启动失败。\n\n错误日志：\n" + logPath;
                MessageBox(IntPtr.Zero, message, "CheckSentry", 0x10);
            }
            return process.ExitCode;
        }
        catch (Exception exception)
        {
            var message = "CheckSentry 启动失败：" + exception.Message;
            try
            {
                if (!string.IsNullOrWhiteSpace(logPath))
                {
                    File.AppendAllText(logPath, exception.ToString() + Environment.NewLine, Utf8NoBom);
                }
                MessageBox(IntPtr.Zero, message + (string.IsNullOrWhiteSpace(logPath) ? string.Empty : "\n\n错误日志：\n" + logPath), "CheckSentry", 0x10);
            }
            catch (Exception fallbackException)
            {
                // 替换原有的空 catch 与无类型 catch，记录异常输出
                Console.Error.WriteLine(exception);
                Console.Error.WriteLine("记录错误日志失败: " + fallbackException);
            }
            return 1;
        }
    }

    private static void ConfigureConsoleEncoding()
    {
        if (!SetConsoleCP(65001)) Trace.WriteLine("SetConsoleCP failed: " + Marshal.GetLastWin32Error());
        if (!SetConsoleOutputCP(65001)) Trace.WriteLine("SetConsoleOutputCP failed: " + Marshal.GetLastWin32Error());
        try
        {
            Console.InputEncoding = Utf8NoBom;
        }
        catch (IOException ex)
        {
            // 避免空 catch 块，在控制台重定向或非交互式执行时保留追踪信息
            Trace.WriteLine($"无法配置 Console.InputEncoding: {ex.Message}");
        }

        try
        {
            Console.OutputEncoding = Utf8NoBom;
        }
        catch (IOException ex)
        {
            Trace.WriteLine($"无法配置 Console.OutputEncoding: {ex.Message}");
        }
    }

    private static void ExtractPayload(Assembly assembly, string runtimeDirectory)
    {
        AssertNoReparsePoints(runtimeDirectory);
        Directory.CreateDirectory(runtimeDirectory);
        var root = Path.GetFullPath(runtimeDirectory).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        foreach (var resourceName in assembly.GetManifestResourceNames().Where(name => name.StartsWith("payload/", StringComparison.Ordinal)))
        {
            var relative = resourceName["payload/".Length..].Replace('/', Path.DirectorySeparatorChar);
            if (Path.IsPathRooted(relative) || relative.Contains(':')) throw new InvalidDataException("嵌入资源路径无效。");
            var destination = Path.GetFullPath(Path.Join(runtimeDirectory, relative));
            if (!destination.StartsWith(root, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("嵌入资源路径无效。");
            AssertNoReparsePoints(destination);
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            using var source = assembly.GetManifestResourceStream(resourceName) ?? throw new InvalidDataException("无法读取嵌入资源：" + resourceName);
            var temporary = destination + ".tmp-" + Guid.NewGuid().ToString("N");
            try
            {
                using (var output = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None)) source.CopyTo(output);
                AssertNoReparsePoints(destination);
                File.Move(temporary, destination, true);
            }
            finally
            {
                if (File.Exists(temporary)) File.Delete(temporary);
            }
        }
        if (!File.Exists(Path.Join(runtimeDirectory, "Start-ComplianceCheck.ps1"))) throw new InvalidDataException("自包含资源不完整。");
    }

    // Textual containment does not detect junctions/symbolic links. Do not extract through them.
    private static void AssertNoReparsePoints(string path)
    {
        for (var current = Path.GetFullPath(path); !string.IsNullOrEmpty(current); current = Path.GetDirectoryName(current))
        {
            try
            {
                if ((File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                    throw new IOException("安全限制：路径包含链接或重解析点：" + current);
            }
            catch (FileNotFoundException) { /* Destination has not been created yet. */ }
            catch (DirectoryNotFoundException) { /* Parent has not been created yet. */ }
        }
    }

    private static void MigrateLegacyData(string dataDirectory)
    {
        var legacyDirectory = Path.Join(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CheckSentry");
        if (string.Equals(Path.GetFullPath(legacyDirectory).TrimEnd(Path.DirectorySeparatorChar), dataDirectory.TrimEnd(Path.DirectorySeparatorChar), StringComparison.OrdinalIgnoreCase)) return;
        if (!Directory.Exists(legacyDirectory)) return;
        AssertNoReparsePoints(legacyDirectory);
        AssertNoReparsePoints(dataDirectory);

        foreach (var name in new[] { "list.xlsx", "CheckSentry.settings.json", "CheckSentry.cloud.json" })
        {
            var source = Path.Join(legacyDirectory, name);
            var destination = Path.Join(dataDirectory, name);
            if (!File.Exists(source)) continue;
            AssertNoReparsePoints(source);
            AssertNoReparsePoints(destination);
            if (!File.Exists(destination))
            {
                File.Move(source, destination);
            }
            else
            {
                var recoveredName = Path.GetFileNameWithoutExtension(name) + "-recovered-from-C-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + Path.GetExtension(name);
                File.Move(source, Path.Join(dataDirectory, recoveredName));
            }
        }

        var legacyLogs = Path.Join(legacyDirectory, "Logs");
        if (Directory.Exists(legacyLogs))
        {
            AssertNoReparsePoints(legacyLogs);
            var targetLogs = Path.Join(dataDirectory, "Logs");
            AssertNoReparsePoints(targetLogs);
            Directory.CreateDirectory(targetLogs);
            foreach (var source in Directory.GetFiles(legacyLogs, "*.log"))
            {
                AssertNoReparsePoints(source);
                var destination = Path.Join(targetLogs, Path.GetFileName(source));
                if (File.Exists(destination)) destination = Path.Join(targetLogs, Path.GetFileNameWithoutExtension(source) + "-migrated-" + Guid.NewGuid().ToString("N") + ".log");
                File.Move(source, destination);
            }
            if (!Directory.EnumerateFileSystemEntries(legacyLogs).Any()) Directory.Delete(legacyLogs);
        }

        var legacyRuntime = Path.Join(legacyDirectory, "Runtime");
        // Retain old runtime contents: recursively deleting user-writable legacy directories is unsafe.
        if (Directory.Exists(legacyRuntime)) Trace.WriteLine("保留旧运行目录，请确认后手动清理：" + legacyRuntime);
        if (!Directory.EnumerateFileSystemEntries(legacyDirectory).Any()) Directory.Delete(legacyDirectory);
    }
}
