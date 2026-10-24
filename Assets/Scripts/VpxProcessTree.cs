using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace VRLauncher
{
    /// <summary>Rescue/shutdown must stop the VPX child as well as a windowless wrapper.</summary>
    internal static class VpxProcessTree
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct Entry
        {
            public uint size, usage, pid;
            public IntPtr heap;
            public uint module, threads, parent;
            public int priority;
            public uint flags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string name;
        }
        [DllImport("kernel32.dll")] private static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint pid);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern bool Process32FirstW(IntPtr snapshot, ref Entry entry);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern bool Process32NextW(IntPtr snapshot, ref Entry entry);
        [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr handle);

        public static void Kill(Process root)
        {
            DateTime started = root.StartTime;
            var entries = new List<Entry>();
            IntPtr snapshot = CreateToolhelp32Snapshot(2, 0);
            if (snapshot != new IntPtr(-1))
            {
                try
                {
                    var entry = new Entry { size = (uint)Marshal.SizeOf(typeof(Entry)) };
                    if (Process32FirstW(snapshot, ref entry))
                        do { entries.Add(entry); } while (Process32NextW(snapshot, ref entry));
                }
                finally { CloseHandle(snapshot); }
            }
            var ids = new List<int> { root.Id };
            for (int i = 0; i < ids.Count; i++)
                foreach (var entry in entries)
                    if (entry.parent == (uint)ids[i] && !ids.Contains((int)entry.pid)) ids.Add((int)entry.pid);
            for (int i = ids.Count - 1; i >= 0; i--)
            {
                try
                {
                    using (Process child = Process.GetProcessById(ids[i]))
                        if (child.StartTime >= started && !child.HasExited) child.Kill();
                }
                catch (ArgumentException) { } // It already exited.
                catch (InvalidOperationException) { }
                catch (System.ComponentModel.Win32Exception ex) { UnityEngine.Debug.LogWarning("Could not stop launch process: " + ex.Message); }
            }
        }
    }
}
