using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using IWinInstaller.App.Modules.Games;

namespace IWinInstaller.App.Modules.Rendimiento
{
    /// <summary>Un juego vigilado: id, nombre y procesos (el * final es prefijo).</summary>
    public sealed class ProfileTarget
    {
        public string Id { get; set; }
        public string Title { get; set; }
        public string[] Processes { get; set; }
        public bool Custom { get; set; }
    }

    public static class ProfileLists
    {
        public static readonly string[] Browsers = { "chrome", "msedge", "firefox", "brave", "opera", "opera_gx", "vivaldi", "arc" };
        /// <summary>Superposiciones que solo molestan al jugar; ninguna es el antivirus ni un lanzador de juegos.</summary>
        public static readonly string[] Overlays = { "GameBar", "GameBarFTServer", "nvsphelper64", "NVIDIA Overlay", "NVIDIA Share" };

        public static List<ProfileTarget> Targets(ProfileSettings settings)
        {
            var list = GameDefinitions.All
                .Select(d => new ProfileTarget { Id = d.Id, Title = d.Name, Processes = d.GameProcesses ?? new string[0] })
                .ToList();
            foreach (var custom in settings.Custom)
                list.Add(new ProfileTarget { Id = "custom:" + custom.Process.ToLowerInvariant(), Title = custom.Title, Processes = new[] { custom.Process }, Custom = true });
            return list;
        }
    }

    /// <summary>
    /// Perfil de juego: al detectar un juego en marcha cierra (con cortesía) navegadores y superposiciones, sube la prioridad del juego
    /// a «Alta» y activa Alto rendimiento; cuando el juego termina lo restaura todo. La sesión se guarda en disco para recuperarla
    /// si la app se cerró antes. Sin ningún proceso en segundo plano propio: lo mueve quien llame a Tick.
    /// </summary>
    public sealed class GameProfileEngine
    {
        private readonly IPerfHost _host;
        private readonly PerfStore _store;
        private readonly Func<DateTime> _utcNow;
        private ProfileSession _active;

        public GameProfileEngine(IPerfHost host, PerfStore store, Func<DateTime> utcNow = null)
        {
            _host = host; _store = store; _utcNow = utcNow ?? (() => DateTime.UtcNow);
        }

        public ProfileSession Active { get { return _active; } }

        /// <summary>Se avisa de cada cambio visible (activado, restaurado) con un texto para el usuario.</summary>
        public event Action<string> Log;
        public event Action<ProfileSession> Activated;
        public event Action<ProfileSession> Restored;

        private static bool Alive(ProfileSession session, IEnumerable<ProcInfo> processes)
        {
            return processes.Any(p => p.Id == session.Pid && (session.ProcessName == null || string.Equals(p.Name, session.ProcessName, StringComparison.OrdinalIgnoreCase)));
        }

        private void Say(string text) { var handler = Log; if (handler != null) handler(text); }

        /// <summary>Un paso: activa si hay un juego nuevo, restaura si el activo terminó.</summary>
        public void Tick(ProfileSettings settings)
        {
            var processes = _host.Processes();
            if (_active != null)
            {
                if (Alive(_active, processes)) return;
                Restore(processes);
                return;
            }
            if (!settings.Enabled) return;
            foreach (var target in ProfileLists.Targets(settings))
            {
                // Varios procesos con el mismo juego (lanzador, anti-trampas): el de más memoria es el juego
                var game = processes.Where(p => ProcessMatcher.MatchesAny(p.Name, target.Processes)).OrderByDescending(p => p.WorkingSetMb).FirstOrDefault();
                if (game == null) continue;
                Activate(target, game, settings.For(target.Id), processes);
                return;
            }
        }

        private void Activate(ProfileTarget target, ProcInfo game, ProfileOptions options, List<ProcInfo> processes)
        {
            var session = new ProfileSession { GameId = target.Id, Title = target.Title, Pid = game.Id, ProcessName = game.Name, StartedUtc = _utcNow() };
            // Se guarda primero lo mínimo: si la app se cierra a medias, el siguiente arranque sabe qué deshacer
            _store.SaveSession(session);
            var did = new List<string>();

            if (options.Priority)
            {
                var previous = _host.PriorityOf(game.Id);
                if (previous.HasValue && previous.Value != ProcessPriorityClass.High && _host.SetPriority(game.Id, ProcessPriorityClass.High))
                {
                    session.PreviousPriority = previous.Value.ToString(); session.PriorityChanged = true; did.Add("prioridad alta");
                }
            }
            if (options.PowerPlan)
            {
                string current = _host.ActivePowerScheme();
                if (current != null && current != PerfCatalog.HighPerformance && _host.PowerSchemeExists(PerfCatalog.HighPerformance)
                    && _host.SetPowerScheme(PerfCatalog.HighPerformance))
                {
                    session.PreviousPower = current; session.AppliedPower = PerfCatalog.HighPerformance; did.Add("Alto rendimiento");
                }
            }
            if (options.CloseOverlays) CloseGroup(processes, ProfileLists.Overlays, session, did, "superposiciones");
            if (options.CloseBrowsers) CloseGroup(processes, ProfileLists.Browsers, session, did, "navegador");
            _store.SaveSession(session);
            _active = session;
            Say(target.Title + ": perfil activo" + (did.Count > 0 ? " (" + string.Join(", ", did) + ")" : " (solo vigilando temperaturas)") + ". Se restaura al salir del juego.");
            var handler = Activated; if (handler != null) handler(session);
        }

        private void CloseGroup(List<ProcInfo> processes, string[] names, ProfileSession session, List<string> did, string label)
        {
            bool any = false;
            foreach (string name in names)
            {
                var matching = processes.Where(p => ProcessMatcher.Matches(p.Name, name)).ToList();
                if (matching.Count == 0) continue;
                bool requested = false;
                foreach (var p in matching.Where(m => m.HasWindow)) requested |= _host.CloseGracefully(p.Id);
                if (!requested) continue;
                any = true;
                string path = matching.Where(m => m.HasWindow).Select(m => _host.PathOf(m.Id)).FirstOrDefault(x => !string.IsNullOrEmpty(x));
                session.Closed.Add(new ClosedApp { Name = name, Path = path });
            }
            if (any) did.Add(label + " cerrados");
        }

        /// <summary>Deshace el perfil: prioridad (si el juego sigue), plan de energía (si nadie lo cambió) y reabre lo que se cerró.</summary>
        public void Restore(List<ProcInfo> processes = null)
        {
            var session = _active ?? _store.LoadSession();
            if (session == null) return;
            processes = processes ?? _host.Processes();
            if (session.PriorityChanged && session.PreviousPriority != null && Alive(session, processes))
            {
                ProcessPriorityClass previous;
                if (Enum.TryParse(session.PreviousPriority, out previous)) _host.SetPriority(session.Pid, previous);
            }
            if (session.AppliedPower != null && session.PreviousPower != null && _host.ActivePowerScheme() == session.AppliedPower
                && _host.PowerSchemeExists(session.PreviousPower))
                _host.SetPowerScheme(session.PreviousPower);
            int reopened = 0;
            foreach (var app in session.Closed)
            {
                if (string.IsNullOrEmpty(app.Path) || processes.Any(p => ProcessMatcher.Matches(p.Name, app.Name))) continue;
                if (_host.Launch(app.Path)) reopened++;
            }
            _active = null;
            _store.SaveSession(null);
            Say((session.Title ?? "El juego") + ": perfil restaurado" + (reopened > 0 ? " y " + reopened + " app(s) reabiertas" : "") + ".");
            var handler = Restored; if (handler != null) handler(session);
        }

        /// <summary>Al abrir la app: si quedó una sesión guardada y su juego ya no está, se restaura; si sigue, se retoma.</summary>
        public void RecoverStale()
        {
            if (_active != null) return;
            var session = _store.LoadSession();
            if (session == null) return;
            var processes = _host.Processes();
            if (Alive(session, processes)) { _active = session; return; }
            Restore(processes);
        }
    }
}
