using System;
using System.Diagnostics;

namespace IWinInstaller.App.Shell
{
    /// <summary>Lleva cada acción de una tarjeta (o, desde v4.8, de la paleta) a su destino.</summary>
    public sealed class ActionRouter
    {
        private readonly LegacyBridge _legacy;
        private readonly Action<string> _navigate;

        public ActionRouter(LegacyBridge legacy, Action<string> navigate)
        {
            _legacy = legacy;
            _navigate = navigate;
        }

        /// <summary>Devuelve false si la acción no existe en esta versión.</summary>
        public bool Run(string actionId)
        {
            switch (actionId)
            {
                case "windowsupdate.open": return OpenUri("ms-settings:windowsupdate");
                case "maintenance.clean":
                case "maintenance.battery":
                case "maintenance.health": _navigate("maintenance"); return true;
                case "updates.open": _navigate("updates"); return true;
                case "install.open":
                case "install.resume": _navigate("install"); return true;
                case "security.open": _navigate("security"); return true;
                case "classic.open":
                    _legacy.Open();
                    return true;
                default:
                    if (actionId != null && actionId.StartsWith("nav.", StringComparison.Ordinal)) { _navigate(actionId.Substring(4)); return true; }
                    return false;
            }
        }

        private static bool OpenUri(string uri)
        {
            try { Process.Start(new ProcessStartInfo(uri) { UseShellExecute = true }); return true; }
            catch (System.ComponentModel.Win32Exception) { return false; }
        }
    }
}
