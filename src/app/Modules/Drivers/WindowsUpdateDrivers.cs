using System;
using System.Collections.Generic;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;

namespace IWinInstaller.App.Modules.Drivers
{
    /// <summary>
    /// Drivers y firmware que Windows Update ofrece para este equipo (API oficial Microsoft.Update.Session).
    /// Solo busca: nunca descarga ni instala. Windows Update solo ofrece un driver si lo considera mejor que el instalado.
    /// </summary>
    public static class WindowsUpdateDrivers
    {
        public const string Criteria = "IsInstalled=0 and Type='Driver' and IsHidden=0";

        public static List<WindowsUpdateOffer> Search(TimeSpan timeout)
        {
            List<WindowsUpdateOffer> offers = null;
            Exception error = null;
            // La API COM de Windows Update se usa desde un hilo STA propio
            var thread = new Thread(() => { try { offers = SearchCore(); } catch (Exception e) { error = e; } }) { IsBackground = true, Name = "Windows Update (drivers)" };
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
            if (!thread.Join(timeout)) throw new TimeoutException("Windows Update no respondió a tiempo.");
            if (error != null)
            {
                var inner = (error as TargetInvocationException)?.InnerException ?? error;
                if (inner is COMException || inner is TimeoutException || inner is InvalidOperationException || inner is UnauthorizedAccessException) throw inner;
                throw new InvalidOperationException(inner.Message, inner);
            }
            return offers;
        }

        private static List<WindowsUpdateOffer> SearchCore()
        {
            var type = Type.GetTypeFromProgID("Microsoft.Update.Session");
            if (type == null) throw new InvalidOperationException("Windows Update no está disponible en este equipo.");
            object session = Activator.CreateInstance(type);
            var offers = new List<WindowsUpdateOffer>();
            try
            {
                Set(session, "ClientApplicationID", "iWinInstaller");
                object searcher = Call(session, "CreateUpdateSearcher");
                object result = Call(searcher, "Search", Criteria);
                object updates = Get(result, "Updates");
                int count = Convert.ToInt32(Get(updates, "Count"));
                for (int i = 0; i < count; i++)
                {
                    object update = updates.GetType().InvokeMember("Item", BindingFlags.GetProperty, null, updates, new object[] { i });
                    object date = Get(update, "DriverVerDate");
                    offers.Add(new WindowsUpdateOffer
                    {
                        Title = Convert.ToString(Get(update, "Title")),
                        DriverClass = Convert.ToString(Get(update, "DriverClass")),
                        HardwareId = Convert.ToString(Get(update, "DriverHardwareID")),
                        Provider = Convert.ToString(Get(update, "DriverProvider")),
                        Date = date is DateTime && ((DateTime)date).Year > 1990 ? ((DateTime)date).Date : (DateTime?)null,
                        Optional = Convert.ToBoolean(Get(update, "BrowseOnly"))
                    });
                }
            }
            finally { if (Marshal.IsComObject(session)) Marshal.FinalReleaseComObject(session); }
            return offers;
        }

        private static object Get(object target, string name) { return target.GetType().InvokeMember(name, BindingFlags.GetProperty, null, target, null); }
        private static void Set(object target, string name, object value) { target.GetType().InvokeMember(name, BindingFlags.SetProperty, null, target, new[] { value }); }
        private static object Call(object target, string name, params object[] args) { return target.GetType().InvokeMember(name, BindingFlags.InvokeMethod, null, target, args); }
    }
}
