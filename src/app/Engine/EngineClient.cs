using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace IWinInstaller.App.Engine
{
    /// <summary>Resultado de un comando del motor (contrato en specs/001-centro-de-control/contracts/engine.md).</summary>
    public sealed class EngineResult
    {
        public const int Success = 0, InvalidRequest = 2, Cancelled = 3, ElevationDenied = 4, InternalError = 10, TimedOut = 11;
        public int ExitCode { get; set; }
        public Dictionary<string, object> Response { get; set; }
        public List<EngineEvent> Events { get; set; }
        public string Error { get; set; }
        public bool Ok { get { return ExitCode == Success && Response != null; } }
    }

    /// <summary>Lanza el motor PowerShell con -EngineCommand y lee su respuesta y sus eventos.</summary>
    public sealed class EngineClient
    {
        private readonly string _root;
        private readonly string _workRoot;

        public EngineClient(string appRoot, string workRoot = null)
        {
            _root = appRoot;
            _workRoot = workRoot ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "iWinInstaller", "engine");
        }

        public string ScriptPath { get { return Path.Combine(_root, "iWinInstaller.ps1"); } }

        /// <summary>PowerShell 5.1 nativo, también desde un proceso de 32 bits en Windows de 64 bits.</summary>
        public static string PowerShellPath()
        {
            string windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
            if (Environment.Is64BitOperatingSystem && !Environment.Is64BitProcess)
                return Path.Combine(windows, "Sysnative", "WindowsPowerShell", "v1.0", "powershell.exe");
            return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
        }

        public Task<EngineResult> RunAsync(string command, IDictionary<string, object> request, Action<EngineEvent> onEvent, TimeSpan timeout, CancellationToken cancellation, EngineOperation operation = null)
        {
            return Task.Run(() => Run(command, request, onEvent, timeout, cancellation, operation));
        }

        private EngineResult Run(string command, IDictionary<string, object> request, Action<EngineEvent> onEvent, TimeSpan timeout, CancellationToken cancellation, EngineOperation operation)
        {
            var result = new EngineResult { Events = new List<EngineEvent>(), ExitCode = EngineResult.InternalError };
            string work = Path.Combine(_workRoot, Guid.NewGuid().ToString("N"));
            try
            {
                Directory.CreateDirectory(work);
                if (operation != null) operation.Attach(work);
                string requestPath = Path.Combine(work, "request.json");
                string responsePath = Path.Combine(work, "response.json");
                string eventsPath = Path.Combine(work, "events.jsonl");
                var body = new Dictionary<string, object>(request ?? new Dictionary<string, object>());
                body["contract"] = 1;
                File.WriteAllText(requestPath, new JavaScriptSerializer().Serialize(body), new UTF8Encoding(false));

                var start = new ProcessStartInfo(PowerShellPath(),
                    "-NoProfile -ExecutionPolicy Bypass -File \"" + ScriptPath + "\" -EngineCommand " + command +
                    " -EngineRequest \"" + requestPath + "\" -EngineResponse \"" + responsePath + "\" -EngineEvents \"" + eventsPath + "\"");
                start.UseShellExecute = false;
                start.CreateNoWindow = true;
                start.WorkingDirectory = _root;

                var reader = new EventFileReader(eventsPath);
                var timer = Stopwatch.StartNew();
                using (var process = Process.Start(start))
                {
                    while (!process.WaitForExit(150))
                    {
                        Deliver(reader.ReadNew(), result, onEvent);
                        if (cancellation.IsCancellationRequested || timer.Elapsed > timeout)
                        {
                            try { process.Kill(); } catch (InvalidOperationException) { } catch (System.ComponentModel.Win32Exception) { }
                            result.ExitCode = cancellation.IsCancellationRequested ? EngineResult.Cancelled : EngineResult.TimedOut;
                            result.Error = cancellation.IsCancellationRequested ? "Cancelado." : "El motor no respondió a tiempo.";
                            return result;
                        }
                    }
                    Deliver(reader.ReadNew(), result, onEvent);
                    result.ExitCode = process.ExitCode;
                }
                if (File.Exists(responsePath))
                    result.Response = new JavaScriptSerializer { MaxJsonLength = 64 * 1024 * 1024 }.DeserializeObject(File.ReadAllText(responsePath, Encoding.UTF8)) as Dictionary<string, object>;
                if (result.ExitCode != EngineResult.Success && result.Error == null)
                    result.Error = LastErrorText(result.Events) ?? ("El motor terminó con el código " + result.ExitCode + ".");
            }
            catch (Exception e)
            {
                result.ExitCode = EngineResult.InternalError;
                result.Error = e.Message;
            }
            finally
            {
                try { Directory.Delete(work, true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
            }
            return result;
        }

        private static void Deliver(IEnumerable<EngineEvent> events, EngineResult result, Action<EngineEvent> onEvent)
        {
            foreach (var engineEvent in events)
            {
                result.Events.Add(engineEvent);
                if (onEvent != null) onEvent(engineEvent);
            }
        }

        private static string LastErrorText(List<EngineEvent> events)
        {
            for (int i = events.Count - 1; i >= 0; i--)
                if (events[i].Type == "log" && events[i].Level == "error" && !String.IsNullOrWhiteSpace(events[i].Text)) return events[i].Text;
            return null;
        }
    }

    /// <summary>Lee un archivo JSONL mientras otro proceso lo escribe; guarda la línea a medias para la siguiente lectura.</summary>
    public sealed class EventFileReader
    {
        private readonly string _path;
        private long _position;
        private string _partial = "";

        public EventFileReader(string path) { _path = path; }

        public List<EngineEvent> ReadNew()
        {
            var events = new List<EngineEvent>();
            if (!File.Exists(_path)) return events;
            string chunk;
            try
            {
                using (var stream = new FileStream(_path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                {
                    if (stream.Length <= _position) return events;
                    stream.Position = _position;
                    var buffer = new byte[stream.Length - _position];
                    int read = stream.Read(buffer, 0, buffer.Length);
                    _position += read;
                    chunk = new UTF8Encoding(false).GetString(buffer, 0, read);
                }
            }
            catch (IOException) { return events; }
            string text = _partial + chunk;
            int end = text.LastIndexOf('\n');
            if (end < 0) { _partial = text; return events; }
            _partial = text.Substring(end + 1);
            foreach (string line in text.Substring(0, end).Split('\n'))
            {
                var engineEvent = EngineEvent.Parse(line.TrimEnd('\r'));
                if (engineEvent != null) events.Add(engineEvent);
            }
            return events;
        }
    }
}
