using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Threading;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace IWinInstaller.App.Modules.Install
{
    /// <summary>
    /// Iconos de las apps: favicon de su web con la misma caché que la ventana clásica
    /// (%LOCALAPPDATA%\iWinInstaller\iconos). Un icono que falla deja las iniciales; nunca cierra la app.
    /// </summary>
    public static class IconLoader
    {
        public static string CacheDirectory
        {
            get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "iWinInstaller", "iconos"); }
        }

        public static void Start(IEnumerable<CatalogItem> items, Dispatcher ui)
        {
            try { ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12; } catch (NotSupportedException) { }
            Directory.CreateDirectory(CacheDirectory);
            var bySite = items.Where(i => !String.IsNullOrEmpty(i.Entry.Icon) && !i.Entry.Icon.StartsWith("glyph:", StringComparison.Ordinal))
                .GroupBy(i => i.Entry.Icon).ToList();
            // Cuatro descargas como máximo, como en la ventana clásica
            for (int worker = 0; worker < Math.Min(4, bySite.Count); worker++)
            {
                int lane = worker;
                ThreadPool.QueueUserWorkItem(_ =>
                {
                    for (int index = lane; index < bySite.Count; index += 4)
                    {
                        if (ui.HasShutdownStarted) return;
                        try
                        {
                            var image = Load(bySite[index].Key);
                            if (image == null) continue;
                            var group = bySite[index].ToList();
                            ui.BeginInvoke(new Action(() => { foreach (var item in group) item.Image = image; }));
                        }
                        catch (Exception) { /* opcional: se conservan las iniciales */ }
                    }
                });
            }
        }

        private static ImageSource Load(string site)
        {
            string name = site.Replace("/", "_").Replace(":", "_");
            string file = Path.Combine(CacheDirectory, name + ".png"), none = Path.Combine(CacheDirectory, name + ".none");
            if (!File.Exists(file) && !(File.Exists(none) && File.GetLastWriteTime(none) > DateTime.Now.AddDays(-7)))
            {
                byte[] data = null;
                string host = site.Split('/')[0];
                foreach (string url in new[] { "https://www.google.com/s2/favicons?sz=64&domain_url=https://" + site, "https://icons.duckduckgo.com/ip3/" + host + ".ico" })
                {
                    try { data = Download(url); if (data != null && data.Length > 0) break; } catch (WebException) { data = null; } catch (IOException) { data = null; }
                }
                if (data != null && data.Length > 0) File.WriteAllBytes(file, data); else File.WriteAllText(none, "");
            }
            if (!File.Exists(file)) return null;
            var bitmap = new BitmapImage();
            bitmap.BeginInit();
            bitmap.CacheOption = BitmapCacheOption.OnLoad;
            bitmap.DecodePixelWidth = 64;
            bitmap.StreamSource = new MemoryStream(File.ReadAllBytes(file));
            bitmap.EndInit();
            bitmap.Freeze();
            return bitmap;
        }

        private static byte[] Download(string url)
        {
            var request = (HttpWebRequest)WebRequest.Create(url);
            request.Timeout = 5000; request.ReadWriteTimeout = 5000; request.UserAgent = "iWinInstaller";
            using (var response = request.GetResponse())
            using (var input = response.GetResponseStream())
            using (var output = new MemoryStream())
            {
                var buffer = new byte[8192]; int count;
                while ((count = input.Read(buffer, 0, buffer.Length)) > 0)
                {
                    if (output.Length + count > 1048576) return null;
                    output.Write(buffer, 0, count);
                }
                return output.ToArray();
            }
        }
    }
}
