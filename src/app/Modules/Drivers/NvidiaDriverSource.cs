using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Net;
using System.Text;
using System.Threading;
using IWinInstaller.App.Modules.Games;

namespace IWinInstaller.App.Modules.Drivers
{
    /// <summary>
    /// Última versión Game Ready para una GPU concreta, con el mismo servicio que usa la app de NVIDIA
    /// (consulta por id de dispositivo PCI). No está documentado: si cambia o falla, la fila pasa a «comprobar a mano».
    /// Solo envía el id de la GPU y la versión de Windows.
    /// </summary>
    public static class NvidiaDriverSource
    {
        private const string Endpoint = "https://gfwsl.geforce.com/nvidia_web_services/controller.gfeclientcontent.NG.php/com.nvidia.services.GFEClientContent_NG.getDispDrvrByDevid/";

        public static string BuildUrl(string pciDeviceId, int osBuild, bool is64Bit)
        {
            if (String.IsNullOrEmpty(pciDeviceId) || pciDeviceId.Length != 4) throw new ArgumentException("Id de GPU no válido", "pciDeviceId");
            string json = "{\"dIDa\":[\"" + pciDeviceId.ToUpperInvariant() + "_10DE\"],\"osC\":\"10.0\",\"osB\":\"" + osBuild.ToString(CultureInfo.InvariantCulture)
                + "\",\"is6\":\"" + (is64Bit ? "1" : "0") + "\",\"lg\":\"1033\",\"iLp\":\"0\",\"prvMd\":\"0\",\"gcV\":\"3.27.0.112\",\"gIsB\":\"0\",\"dch\":\"1\",\"upCRD\":\"0\",\"isCRD\":\"0\"}";
            return Endpoint + json.Replace("{", "%7B").Replace("}", "%7D").Replace("\"", "%22");
        }

        /// <summary>Lee la respuesta; null si NVIDIA no reconoce la GPU o no hay versión.</summary>
        public static NvidiaRelease Parse(string body)
        {
            var root = MiniJson.TryParseObject(body);
            if (root == null) return null;
            var criteria = Child(root, "criteria");
            var supported = Child(criteria, "IsSupported");
            if (supported != null && !String.Equals(MiniJson.GetString(supported, "state"), "true", StringComparison.OrdinalIgnoreCase)) return null;
            var attributes = Child(root, "DriverAttributes");
            string version = MiniJson.GetString(attributes, "Version") ?? MiniJson.GetString(Child(criteria, "IsDispDriverNewer"), "latestDispDriverVersion");
            if (DriverRules.CompareVersions(version, "0") == null) return null;
            DateTime date;
            string released = MiniJson.GetString(attributes, "ReleaseDateTime");
            string details = MiniJson.GetString(attributes, "DetailsURL");
            return new NvidiaRelease
            {
                Version = version,
                Name = MiniJson.GetString(attributes, "Name"),
                Date = released != null && released.Length >= 10 && DateTime.TryParseExact(released.Substring(0, 10), "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out date) ? date : (DateTime?)null,
                DetailsUrl = details != null && details.StartsWith("https://www.nvidia.com/", StringComparison.OrdinalIgnoreCase) ? details : null
            };
        }

        public static NvidiaRelease Fetch(string pciDeviceId, int osBuild, bool is64Bit, CancellationToken token)
        {
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
            var request = (HttpWebRequest)WebRequest.Create(BuildUrl(pciDeviceId, osBuild, is64Bit));
            request.Timeout = 15000; request.ReadWriteTimeout = 15000;
            request.UserAgent = "iWinInstaller";
            using (token.Register(request.Abort))
            using (var response = request.GetResponse())
            using (var stream = response.GetResponseStream())
            using (var reader = new StreamReader(stream, Encoding.UTF8))
            {
                var buffer = new char[512 * 1024];
                int read = reader.ReadBlock(buffer, 0, buffer.Length); // la respuesta ronda 5 KB; tope por si acaso
                return Parse(new string(buffer, 0, read));
            }
        }

        private static Dictionary<string, object> Child(Dictionary<string, object> data, string key)
        {
            object value;
            return data != null && data.TryGetValue(key, out value) ? value as Dictionary<string, object> : null;
        }
    }
}
