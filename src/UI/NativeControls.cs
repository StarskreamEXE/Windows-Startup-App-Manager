using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace StartupManager
{
    public static class NativeTheme
    {
        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);

        [DllImport("user32.dll")]
        public static extern uint GetDpiForWindow(IntPtr window);

        public static void EnableDpiAwareness()
        {
            if (SetThreadDpiAwarenessContext(new IntPtr(-4)) == IntPtr.Zero)
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        }

        [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)]
        public static extern int SetWindowTheme(IntPtr window, string applicationName, string classNames);
    }

    public sealed class ZoomWheelFilter : IMessageFilter
    {
        private readonly Form owner;
        private int wheelRemainder;
        public event Action<int> ZoomRequested;

        public ZoomWheelFilter(Form owner)
        {
            this.owner = owner;
        }

        public bool PreFilterMessage(ref Message message)
        {
            if (message.Msg != 0x020A || owner.IsDisposed || !owner.Enabled)
                return false;
            if ((message.WParam.ToInt64() & 8) == 0)
            {
                wheelRemainder = 0;
                return false;
            }
            Control target = Control.FromChildHandle(message.HWnd);
            if (target == null || target.FindForm() != owner)
                return false;
            wheelRemainder += unchecked((short)(message.WParam.ToInt64() >> 16));
            int steps = wheelRemainder / 120;
            wheelRemainder %= 120;
            if (steps != 0 && ZoomRequested != null)
                ZoomRequested(steps);
            return true;
        }
    }
}
