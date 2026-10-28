using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace FlowLocal.App;

/// <summary>Ties child processes to this app's lifetime with a Windows job object (kill-on-close).</summary>
internal static class ChildProcessJob
{
    private static IntPtr _job;

    public static void Attach(Process process)
    {
        try
        {
            if (_job == IntPtr.Zero)
            {
                _job = NativeMethods.CreateJobObject(IntPtr.Zero, null);
                // JOBOBJECT_EXTENDED_LIMIT_INFORMATION with JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE (0x2000).
                var size = IntPtr.Size == 8 ? 144 : 112;
                var info = Marshal.AllocHGlobal(size);
                for (var i = 0; i < size; i++) Marshal.WriteByte(info, i, 0);
                Marshal.WriteInt32(info, 16, 0x2000);   // BasicLimitInformation.LimitFlags
                NativeMethods.SetInformationJobObject(_job, 9, info, (uint)size);   // 9 = ExtendedLimitInformation
                Marshal.FreeHGlobal(info);
            }
            NativeMethods.AssignProcessToJobObject(_job, process.Handle);
        }
        catch (Exception e) { FlowLocal.Core.Log.Write($"job object failed: {e.Message}"); }
    }
}
