using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace IWinInstaller.App.Modules.Tools
{
    /// <summary>Un monitor activo.</summary>
    public sealed class MonitorInfo
    {
        public string Device { get; set; }
        public string Name { get; set; }
        public bool Primary { get; set; }
        public string Label { get; set; }
        public override string ToString() { return Label; }
    }

    /// <summary>Un modo de pantalla (resolución y frecuencia).</summary>
    public struct DisplayMode
    {
        public int Width, Height, Hz;
        public DisplayMode(int width, int height, int hz) { Width = width; Height = height; Hz = hz; }
    }

    /// <summary>Resolución y frecuencia de cada monitor (user32), igual que la ventana clásica.</summary>
    public static class DisplaySettings
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct DEVMODE
        {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
            public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
            public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
            public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
            public short dmLogPixels;
            public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
            public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct DISPLAY_DEVICE
        {
            public int cb;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
            public int StateFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
        }

        [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool EnumDisplayDevices(string device, int index, ref DISPLAY_DEVICE info, int flags);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool EnumDisplaySettings(string device, int mode, ref DEVMODE info);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int ChangeDisplaySettingsEx(string device, ref DEVMODE info, IntPtr hwnd, int flags, IntPtr param);

        private const int Current = -1, AttachedToDesktop = 1, PrimaryDevice = 4;
        private const int PelsWidth = 0x80000, PelsHeight = 0x100000, Frequency = 0x400000;
        private const int Test = 2, UpdateRegistry = 1;

        private static DEVMODE New() { var mode = new DEVMODE(); mode.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE)); return mode; }

        public static List<MonitorInfo> Monitors()
        {
            var list = new List<MonitorInfo>();
            var device = new DISPLAY_DEVICE(); device.cb = Marshal.SizeOf(device);
            for (int i = 0; EnumDisplayDevices(null, i, ref device, 0); i++)
            {
                if ((device.StateFlags & AttachedToDesktop) != 0)
                {
                    string name = device.DeviceString;
                    var monitor = new DISPLAY_DEVICE(); monitor.cb = Marshal.SizeOf(monitor);
                    if (EnumDisplayDevices(device.DeviceName, 0, ref monitor, 0) && !String.IsNullOrEmpty(monitor.DeviceString)) name = monitor.DeviceString;
                    bool primary = (device.StateFlags & PrimaryDevice) != 0;
                    list.Add(new MonitorInfo { Device = device.DeviceName, Name = name, Primary = primary, Label = (list.Count + 1) + ". " + name + (primary ? " (principal)" : "") });
                }
                device = new DISPLAY_DEVICE(); device.cb = Marshal.SizeOf(device);
            }
            return list;
        }

        public static DisplayMode? CurrentMode(string device)
        {
            var mode = New();
            if (!EnumDisplaySettings(device, Current, ref mode)) return null;
            return new DisplayMode(mode.dmPelsWidth, mode.dmPelsHeight, mode.dmDisplayFrequency);
        }

        /// <summary>Modos admitidos a la profundidad de color actual, sin repetir.</summary>
        public static List<DisplayMode> Modes(string device)
        {
            var current = New(); EnumDisplaySettings(device, Current, ref current);
            var seen = new HashSet<string>(); var list = new List<DisplayMode>();
            var mode = New();
            for (int i = 0; EnumDisplaySettings(device, i, ref mode); i++)
            {
                if (mode.dmBitsPerPel == current.dmBitsPerPel && mode.dmPelsWidth >= 640 && mode.dmDisplayFrequency > 1 &&
                    seen.Add(mode.dmPelsWidth + "x" + mode.dmPelsHeight + "@" + mode.dmDisplayFrequency))
                    list.Add(new DisplayMode(mode.dmPelsWidth, mode.dmPelsHeight, mode.dmDisplayFrequency));
                mode = New();
            }
            return list;
        }

        /// <summary>0 = aplicado, 1 = requiere reiniciar, negativo = rechazado. Se prueba antes de aplicar.</summary>
        public static int Apply(string device, DisplayMode target)
        {
            var mode = New();
            if (!EnumDisplaySettings(device, Current, ref mode)) return -99;
            mode.dmPelsWidth = target.Width; mode.dmPelsHeight = target.Height; mode.dmDisplayFrequency = target.Hz;
            mode.dmFields = PelsWidth | PelsHeight | Frequency;
            int test = ChangeDisplaySettingsEx(device, ref mode, IntPtr.Zero, Test, IntPtr.Zero);
            if (test != 0) return test;
            return ChangeDisplaySettingsEx(device, ref mode, IntPtr.Zero, UpdateRegistry, IntPtr.Zero);
        }
    }
}
