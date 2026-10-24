using System;
using System.Collections;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.XR.Management;

namespace VRLauncher
{
    /// <summary>
    /// Launches Visual Pinball tables and monitors the process
    /// </summary>
    public class TableLauncher : MonoBehaviour
    {
        // Windows API for window focus management
        [DllImport("user32.dll")]
        private static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll")]
        private static extern bool IsIconic(IntPtr hWnd);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

        [DllImport("user32.dll")]
        private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

        // Polled globally rather than through the Input System: while a table
        // is running VPinballX holds focus, and Keyboard.current only reports
        // keys when this window is focused - which is never, at the one moment
        // the rescue hotkey is needed.
        [DllImport("user32.dll")]
        private static extern short GetAsyncKeyState(int vKey);

        private const int VK_BACK = 0x08;

        // Window show commands
        private const int SW_RESTORE = 9;
        private const int SW_SHOW = 5;

        // SetWindowPos flags
        private static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
        private const uint SWP_NOMOVE = 0x0002;
        private const uint SWP_NOSIZE = 0x0001;
        private const uint SWP_SHOWWINDOW = 0x0040;

        [Header("Configuration")]
        [Tooltip("Path to VPinballX_GL64.exe")]
        public string vpinballExecutable = @"C:\Visual Pinball\VPinballX_GL64.exe";

        [Tooltip("Time in seconds to wait before attempting to focus the VP window")]
        public float focusDelaySeconds = 2.0f;

        private VpxProfile[] vpxProfiles = new VpxProfile[0];
        private TableProfile[] tableProfiles = new TableProfile[0];

        private Process currentProcess;
        private bool backspaceWasPressed = false;
        private bool isTableRunning = false;
        private string currentTablePath;
        private Keyboard keyboard;
        private readonly Stopwatch launchClock = new Stopwatch();
        private LaunchFeedback feedback;
        private string runtimeLogPath;
        private long runtimeLogOffset;
        private string pendingLogLine = "";
        private float nextLogRead;
        private bool cancelled;
        private GUIStyle progressStyle;

        public string LastLaunchError { get; private set; }
        public string LastReturnNotice { get; private set; }
        public bool LastSessionCounted { get; private set; }
        public bool LastStartupConfirmed => feedback != null && feedback.StartupCompleted;

        public delegate void TableExitedHandler();
        public event TableExitedHandler OnTableExited;

        /// <summary>
        /// Launches a Visual Pinball table
        /// </summary>
        /// <param name="tablePath">Full path to the .vpx file</param>
        /// <returns>True if launch was successful</returns>
        public bool LaunchTable(string tablePath)
        {
            LastLaunchError = null;
            LastReturnNotice = null;
            LastSessionCounted = false;
            if (isTableRunning)
            {
                UnityEngine.Debug.LogWarning("A table is already running!");
                LastLaunchError = "Another table is still running.";
                return false;
            }

            LaunchCommand command = VpxProfiles.Resolve(tablePath, vpinballExecutable, vpxProfiles, tableProfiles, LauncherPaths.AppDirectory);
            if (!File.Exists(command.Executable))
            {
                UnityEngine.Debug.LogError($"VPinballX executable not found: {command.Executable}");
                LastLaunchError = "The configured VPX program could not be found.";
                return false;
            }

            if (!File.Exists(tablePath))
            {
                UnityEngine.Debug.LogError($"Table file not found: {tablePath}");
                LastLaunchError = "This table file could not be found.";
                return false;
            }

            try
            {
                currentTablePath = tablePath;
                feedback = new LaunchFeedback(tablePath);
                cancelled = false;
                runtimeLogPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "VPinballX", "10.8", "vpinball.log");
                runtimeLogOffset = File.Exists(runtimeLogPath) ? new FileInfo(runtimeLogPath).Length : 0;
                pendingLogLine = "";
                launchClock.Restart();

                // Stop Unity's XR session before launching VPinballX
                UnityEngine.Debug.Log("Stopping Unity XR session before launching table...");
                StopXR();

                ProcessStartInfo startInfo = new ProcessStartInfo
                {
                    FileName = command.Executable,
                    Arguments = command.Arguments,
                    UseShellExecute = false,
                    WorkingDirectory = command.WorkingDirectory
                };

                if (command.ProfileName != null)
                    UnityEngine.Debug.Log($"Using VPX profile '{command.ProfileName}' for this table");

                UnityEngine.Debug.Log($"Launching table: {Path.GetFileName(tablePath)}");
                UnityEngine.Debug.Log($"Command: {startInfo.FileName} {startInfo.Arguments}");

                currentProcess = Process.Start(startInfo);

                if (currentProcess != null)
                {
                    isTableRunning = true;
                    // Poll on the Unity thread: one exit path, including immediately exiting hosts.

                    // Start coroutine to focus the VPinballX window after a delay
                    StartCoroutine(FocusVPinballWindow());

                    return true;
                }
                else
                {
                    UnityEngine.Debug.LogError("Failed to start process");
                    LastLaunchError = "Windows could not start the configured VPX program.";
                    currentTablePath = null;
                    // Restart XR if launch failed
                    StartXR();
                    return false;
                }
            }
            catch (System.Exception ex)
            {
                UnityEngine.Debug.LogError($"Error launching table: {ex.Message}");
                LastLaunchError = "Windows could not start VPX. See the launch log for details.";
                currentTablePath = null;
                StartXR();
                return false;
            }
        }

        private void FinishTable()
        {
            if (!isTableRunning || currentProcess == null) return;
            ReadRuntimeLog();
            int exitCode = currentProcess.HasExited ? currentProcess.ExitCode : -1;
            launchClock.Stop();
            LastSessionCounted = feedback.CountSession(exitCode, launchClock.Elapsed.TotalSeconds, cancelled);
            LastReturnNotice = feedback.ReturnNotice(exitCode, launchClock.Elapsed.TotalSeconds, cancelled);
            UnityEngine.Debug.Log($"Launch result: {currentTablePath}; exit={exitCode}; seconds={launchClock.Elapsed.TotalSeconds:F1}; startupConfirmed={feedback.StartupCompleted}; cancelled={cancelled}; problem={feedback.Problem}");
            UnityEngine.Debug.Log($"Table exited: {Path.GetFileName(currentTablePath)}");
            isTableRunning = false;
            currentTablePath = null;
            currentProcess.Dispose();
            currentProcess = null;
            StartXR();
            OnTableExited?.Invoke();
        }

        /// <summary>
        /// Checks if a table is currently running
        /// </summary>
        public bool IsTableRunning()
        {
            return isTableRunning;
        }

        /// <summary>
        /// Gets the currently running table path
        /// </summary>
        public string GetCurrentTablePath()
        {
            return currentTablePath;
        }

        void Awake()
        {
            keyboard = Keyboard.current;

            // Load configuration
            LauncherConfig config = LauncherConfig.Instance;
            vpinballExecutable = config.vpinballExecutable;
            vpxProfiles = config.vpxProfiles ?? new VpxProfile[0];
            tableProfiles = config.tableProfiles ?? new TableProfile[0];

            UnityEngine.Debug.Log($"TableLauncher configured to use VPinballX at: {vpinballExecutable}");
            foreach (TableProfile entry in tableProfiles)
            {
                if (entry == null) continue;
                UnityEngine.Debug.Log($"Table '{entry.table}' uses VPX profile '{entry.profile}'");
            }
        }

        void Update()
        {
            if (isTableRunning && Time.unscaledTime >= nextLogRead)
            {
                nextLogRead = Time.unscaledTime + 0.5f;
                ReadRuntimeLog();
            }
            // Process completion is handled once, on the Unity thread.
            if (isTableRunning && currentProcess != null && currentProcess.HasExited)
            {
                UnityEngine.Debug.Log("Detected table exit via polling");
                FinishTable();
            }

            // Allow manual exit with Backspace - kills VPinballX and returns to
            // the menu. Polled via GetAsyncKeyState so it still works while
            // VPinballX has focus, which it always does while a table is up.
            bool backspacePressed = (GetAsyncKeyState(VK_BACK) & 0x8000) != 0;
            if (backspacePressed && !backspaceWasPressed)
            {
                backspaceWasPressed = true;
                if (isTableRunning)
                {
                    UnityEngine.Debug.Log("BACKSPACE pressed - Killing VPinballX process and returning to menu");
                    KillCurrentTable();
                }
            }
            else if (!backspacePressed)
            {
                backspaceWasPressed = false;
            }
        }

        /// <summary>
        /// Manually kills the current VPinballX process
        /// </summary>
        public void KillCurrentTable()
        {
            if (!isTableRunning) return;
            cancelled = true;
            if (currentProcess != null && !currentProcess.HasExited)
            {
                try
                {
                    UnityEngine.Debug.Log("Terminating VPinballX process");
                    VpxProcessTree.Kill(currentProcess);
                    currentProcess.WaitForExit(2000);
                }
                catch (System.Exception ex)
                {
                    UnityEngine.Debug.LogWarning($"Error killing process: {ex.Message}");
                }
            }

            if (currentProcess == null || currentProcess.HasExited) FinishTable();
        }

        private void ReadRuntimeLog()
        {
            if (feedback == null || runtimeLogPath == null) return;
            try
            {
                using (var stream = new FileStream(runtimeLogPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                {
                    if (stream.Length < runtimeLogOffset) { runtimeLogOffset = 0; pendingLogLine = ""; }
                    stream.Position = runtimeLogOffset;
                    byte[] bytes = new byte[(int)Math.Min(65536, stream.Length - runtimeLogOffset)];
                    int count = stream.Read(bytes, 0, bytes.Length);
                    runtimeLogOffset += count;
                    string[] lines = (pendingLogLine + System.Text.Encoding.UTF8.GetString(bytes, 0, count)).Split('\n');
                    for (int i = 0; i < lines.Length - 1; i++) feedback.Observe(lines[i]);
                    pendingLogLine = lines[lines.Length - 1];
                }
            }
            catch (IOException) { } // Logging is optional; process-exit recovery must still work.
            catch (UnauthorizedAccessException) { }
        }

        private void OnGUI()
        {
            // Desktop-only progress: Unity has released XR to VPX. Stop drawing once startup is confirmed.
            if (!isTableRunning || feedback == null || (feedback.StartupCompleted && feedback.Problem == null)) return;
            if (progressStyle == null)
                progressStyle = new GUIStyle(GUI.skin.box) { fontSize = 22, alignment = TextAnchor.MiddleCenter, wordWrap = true };
            string title = Path.GetFileNameWithoutExtension(currentTablePath);
            string stage = feedback.Problem ?? (launchClock.Elapsed.TotalSeconds >= 30 ? "Still waiting for VPX startup" : "Starting VPX");
            GUI.Box(new Rect((Screen.width - 680) / 2f, (Screen.height - 160) / 2f, 680, 160),
                $"{title}\n{stage} · {launchClock.Elapsed.TotalSeconds:0}s\nBackspace: stop and return to the launcher", progressStyle);
        }

        /// <summary>
        /// Waits for VPinballX window to appear and sets focus to it
        /// </summary>
        private IEnumerator FocusVPinballWindow()
        {
            UnityEngine.Debug.Log($"Waiting {focusDelaySeconds} seconds before focusing VPinballX window...");
            yield return new WaitForSeconds(focusDelaySeconds);

            if (currentProcess == null || currentProcess.HasExited)
            {
                UnityEngine.Debug.LogWarning("Process exited before window focus could be set");
                yield break;
            }

            // Try multiple times to find and focus the window
            bool focused = false;
            for (int attempt = 0; attempt < 10 && !focused; attempt++)
            {
                if (currentProcess == null || currentProcess.HasExited)
                {
                    break;
                }

                // Try to get the main window handle
                IntPtr mainWindowHandle = IntPtr.Zero;
                bool windowIsMinimized = false;

                try
                {
                    mainWindowHandle = currentProcess.MainWindowHandle;
                    if (mainWindowHandle != IntPtr.Zero)
                    {
                        windowIsMinimized = IsIconic(mainWindowHandle);
                    }
                    else
                    {
                        // MainWindowHandle not available yet, try refreshing
                        currentProcess.Refresh();
                        UnityEngine.Debug.Log($"Window handle not ready yet, attempt {attempt + 1}/10");
                    }
                }
                catch (Exception ex)
                {
                    UnityEngine.Debug.LogWarning($"Error getting window handle on attempt {attempt + 1}: {ex.Message}");
                }

                if (mainWindowHandle != IntPtr.Zero)
                {
                    UnityEngine.Debug.Log($"Found VPinballX main window handle: {mainWindowHandle}");

                    // If window is minimized, restore it
                    if (windowIsMinimized)
                    {
                        UnityEngine.Debug.Log("Window is minimized, restoring...");
                        try
                        {
                            ShowWindow(mainWindowHandle, SW_RESTORE);
                        }
                        catch (Exception ex)
                        {
                            UnityEngine.Debug.LogWarning($"Error restoring window: {ex.Message}");
                        }
                        yield return new WaitForSeconds(0.2f);
                    }

                    // Make window topmost temporarily to ensure it comes to front
                    try
                    {
                        SetWindowPos(mainWindowHandle, HWND_TOPMOST, 0, 0, 0, 0,
                                   SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
                    }
                    catch (Exception ex)
                    {
                        UnityEngine.Debug.LogWarning($"Error setting window topmost: {ex.Message}");
                    }

                    // Set focus
                    bool result = false;
                    try
                    {
                        result = SetForegroundWindow(mainWindowHandle);
                        if (result)
                        {
                            UnityEngine.Debug.Log("Successfully focused VPinballX window");
                            focused = true;
                        }
                        else
                        {
                            UnityEngine.Debug.LogWarning($"SetForegroundWindow failed on attempt {attempt + 1}");
                        }
                    }
                    catch (Exception ex)
                    {
                        UnityEngine.Debug.LogWarning($"Error setting foreground window: {ex.Message}");
                    }

                    // Remove topmost flag after a brief delay (outside try-catch)
                    if (result)
                    {
                        yield return new WaitForSeconds(0.1f);

                        try
                        {
                            SetWindowPos(mainWindowHandle, IntPtr.Zero, 0, 0, 0, 0,
                                       SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
                        }
                        catch (Exception ex)
                        {
                            UnityEngine.Debug.LogWarning($"Error removing topmost flag: {ex.Message}");
                        }
                    }
                }

                if (!focused)
                {
                    yield return new WaitForSeconds(0.5f);
                }
            }

            if (!focused)
            {
                UnityEngine.Debug.LogWarning("Could not focus VPinballX window after multiple attempts");
            }
        }

        /// <summary>
        /// Stops Unity's XR session
        /// </summary>
        private void StopXR()
        {
            var xrManager = XRGeneralSettings.Instance?.Manager;
            if (xrManager != null && xrManager.isInitializationComplete)
            {
                UnityEngine.Debug.Log("Stopping XR...");
                xrManager.StopSubsystems();
                xrManager.DeinitializeLoader();
                UnityEngine.Debug.Log("XR stopped");
            }
        }

        /// <summary>
        /// Starts Unity's XR session
        /// </summary>
        private void StartXR()
        {
            var xrManager = XRGeneralSettings.Instance?.Manager;
            if (xrManager != null && !xrManager.isInitializationComplete)
            {
                UnityEngine.Debug.Log("Starting XR...");
                StartCoroutine(StartXRCoroutine());
            }
        }

        private IEnumerator StartXRCoroutine()
        {
            UnityEngine.Debug.Log("Initializing XR...");
            yield return XRGeneralSettings.Instance.Manager.InitializeLoader();

            if (XRGeneralSettings.Instance.Manager.activeLoader != null)
            {
                UnityEngine.Debug.Log("XR Loader initialized, starting subsystems...");
                XRGeneralSettings.Instance.Manager.StartSubsystems();
                UnityEngine.Debug.Log("XR started successfully");
            }
            else
            {
                UnityEngine.Debug.LogError("Failed to initialize XR loader");
            }
        }

        void OnApplicationQuit()
        {
            TerminateTableProcess("application quit");
        }

        void OnDestroy()
        {
            TerminateTableProcess("launcher shutdown");

            // Clean up process monitoring
            if (currentProcess != null)
            {
                currentProcess.Dispose();
            }
        }

        /// <summary>
        /// Kills VPinballX on shutdown, without restarting XR or raising
        /// OnTableExited - there is no menu left to return to. Process.Dispose
        /// only releases the handle, so without this an orphaned VPinballX
        /// keeps running and holds the OpenXR runtime.
        /// </summary>
        private void TerminateTableProcess(string reason)
        {
            if (currentProcess == null)
            {
                return;
            }

            try
            {
                if (currentProcess.HasExited)
                {
                    return;
                }

                UnityEngine.Debug.Log($"Terminating VPinballX on {reason}");
                VpxProcessTree.Kill(currentProcess);
                currentProcess.WaitForExit(2000);
            }
            catch (System.Exception ex)
            {
                UnityEngine.Debug.LogWarning($"Error terminating VPinballX on {reason}: {ex.Message}");
            }
            finally
            {
                isTableRunning = false;
            }
        }
    }
}
