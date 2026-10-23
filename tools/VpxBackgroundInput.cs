using System;
using System.Diagnostics;
using System.Text;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

internal static class VpxBackgroundInput
{
    private static readonly string HostDirectory = AppDomain.CurrentDomain.BaseDirectory;
    private static string VpxPath;
    private const string Hint = "SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS";

    private delegate bool EnumWindowProc(IntPtr window, IntPtr parameter);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowProc callback, IntPtr parameter);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassName(IntPtr window, StringBuilder name, int count);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr window, StringBuilder text, int count);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr window);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern bool AllowSetForegroundWindow(uint processId);

    private static void Log(string message)
    {
        try { File.AppendAllText(Path.Combine(HostDirectory, "VpxBackgroundInput.log"), DateTime.Now.ToString("s") + " " + message + Environment.NewLine); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    private static void FocusPlayer(Process process)
    {
        // The launcher tracks this windowless host, so it cannot focus the child.
        // Wait for the play window rather than focusing the editor/loading dialog.
        var timer = Stopwatch.StartNew();
        IntPtr lastWindow = IntPtr.Zero;
        long visibleSince = 0;
        while (!process.HasExited && timer.ElapsedMilliseconds < 120000)
        {
            IntPtr player = IntPtr.Zero;
            EnumWindows(delegate(IntPtr window, IntPtr unused)
            {
                uint owner;
                GetWindowThreadProcessId(window, out owner);
                if (owner != (uint)process.Id || !IsWindowVisible(window)) return true;
                var className = new StringBuilder(256);
                var title = new StringBuilder(512);
                GetClassName(window, className, className.Capacity);
                GetWindowText(window, title, title.Capacity);
                if (className.ToString() == "VPPlayer" || title.ToString().StartsWith("Visual Pinball Player", StringComparison.OrdinalIgnoreCase))
                    player = window;
                return true;
            }, IntPtr.Zero);
            if (player != lastWindow) { lastWindow = player; visibleSince = timer.ElapsedMilliseconds; }
            if (player != IntPtr.Zero && timer.ElapsedMilliseconds - visibleSince >= 2000)
            {
                if (IsIconic(player)) ShowWindow(player, 9);
                SetForegroundWindow(player);
                if (GetForegroundWindow() == player)
                {
                    Log("Focused VPX player pid=" + process.Id + " hwnd=" + player);
                    return; // Startup handoff only; never fight later user window switches.
                }
            }
            Thread.Sleep(500);
        }
        Log(process.HasExited ? "VPX exited before focus handoff" : "Timed out waiting for VPX player focus");
    }

    private static string Quote(string value)
    {
        var result = new StringBuilder();
        result.Append('"');
        int slashes = 0;
        foreach (char ch in value)
        {
            if (ch == '\\') { slashes++; continue; }
            if (ch == '"')
            {
                result.Append('\\', slashes * 2 + 1);
                result.Append('"');
                slashes = 0;
                continue;
            }
            result.Append('\\', slashes);
            result.Append(ch);
            slashes = 0;
        }
        result.Append('\\', slashes * 2);
        result.Append('"');
        return result.ToString();
    }

    private static int Main(string[] args)
    {
        bool selfTest = args.Length == 1 && args[0] == "--self-test";
        var start = new ProcessStartInfo();
        start.UseShellExecute = false;
        start.CreateNoWindow = false;
        start.EnvironmentVariables[Hint] = "1";
        if (selfTest)
        {
            start.FileName = Environment.GetFolderPath(Environment.SpecialFolder.System) + @"\WindowsPowerShell\v1.0\powershell.exe";
            start.Arguments = "-NoProfile -NonInteractive -Command \"if ($env:SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS -eq '1') { exit 0 } else { exit 42 }\"";
            start.WorkingDirectory = Environment.CurrentDirectory;
        }
        else
        {
            string pathFile = Path.Combine(HostDirectory, "VpxBackgroundInput.vpx-path.txt");
            if (!File.Exists(pathFile))
            {
                Log("Missing " + pathFile + "; run install-vpx-background-input.ps1 first.");
                return 2;
            }
            VpxPath = File.ReadAllText(pathFile).Trim();
            if (!Path.IsPathRooted(VpxPath) || !File.Exists(VpxPath)
                || string.Equals(Path.GetFullPath(VpxPath), System.Reflection.Assembly.GetExecutingAssembly().Location, StringComparison.OrdinalIgnoreCase))
            {
                Log("Invalid VPX executable path: " + VpxPath);
                return 2;
            }
            start.FileName = VpxPath;
            // Honor launcher profiles using workingDirectory="table".
            start.WorkingDirectory = Environment.CurrentDirectory;
            var commandLine = new StringBuilder();
            foreach (string arg in args)
            {
                if (commandLine.Length > 0) commandLine.Append(' ');
                commandLine.Append(Quote(arg));
            }
            start.Arguments = commandLine.ToString();
        }
        using (Process process = Process.Start(start))
        {
            if (!selfTest)
            {
                AllowSetForegroundWindow((uint)process.Id);
                Log("Started VPX pid=" + process.Id);
                try { FocusPlayer(process); }
                catch (Exception ex) { Log("Focus handoff failed: " + ex.Message); }
            }
            process.WaitForExit();
            return process.ExitCode;
        }
    }
}
