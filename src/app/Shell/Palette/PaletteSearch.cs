using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

namespace IWinInstaller.App.Shell.Palette
{
    /// <summary>Una acción que se puede encontrar en la paleta.</summary>
    public sealed class PaletteAction
    {
        public PaletteAction(string id, string title, string module, string keywords)
        {
            Id = id; Title = title; Module = module; Keywords = keywords ?? "";
            Search = PaletteSearch.Normalize(title + " " + module + " " + Keywords);
            TitleSearch = PaletteSearch.Normalize(title);
        }
        /// <summary>«nav.updates», «install.search:git»… lo ejecuta el ActionRouter.</summary>
        public string Id { get; private set; }
        public string Title { get; private set; }
        public string Module { get; private set; }
        public string Keywords { get; private set; }
        internal string Search { get; private set; }
        internal string TitleSearch { get; private set; }
    }

    /// <summary>Búsqueda de la paleta: sin tildes ni mayúsculas, todas las palabras y prioridad al título.</summary>
    public static class PaletteSearch
    {
        /// <summary>Minúsculas sin tildes: «Resolución» y «resolucion» coinciden.</summary>
        public static string Normalize(string text)
        {
            if (String.IsNullOrEmpty(text)) return "";
            var decomposed = text.ToLowerInvariant().Normalize(NormalizationForm.FormD);
            var builder = new StringBuilder(decomposed.Length);
            foreach (char c in decomposed)
                if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark) builder.Append(c);
            return builder.ToString().Normalize(NormalizationForm.FormC);
        }

        public static List<PaletteAction> Find(IEnumerable<PaletteAction> actions, string query, int max = 12)
        {
            var words = Normalize(query).Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
            if (words.Length == 0) return actions.Where(a => a.Id.StartsWith("nav.", StringComparison.Ordinal)).Take(max).ToList();
            return actions
                .Where(a => words.All(w => a.Search.Contains(w)))
                .OrderByDescending(a => Score(a, words))
                .ThenBy(a => a.Title.Length)
                .Take(max)
                .ToList();
        }

        /// <summary>Más puntos si el título empieza por la búsqueda o contiene sus palabras.</summary>
        internal static int Score(PaletteAction action, string[] words)
        {
            int score = 0;
            string first = words[0];
            if (action.TitleSearch.StartsWith(first, StringComparison.Ordinal)) score += 100;
            foreach (var word in words)
            {
                if (action.TitleSearch.Contains(word)) score += 20;
                if (action.TitleSearch.Split(' ').Any(t => t.StartsWith(word, StringComparison.Ordinal))) score += 10;
            }
            // Las acciones de la app (pocas) van antes que las apps del catálogo con palabras parecidas
            if (!action.Id.StartsWith("install.search:", StringComparison.Ordinal)) score += 150;
            return score;
        }
    }

    /// <summary>Acciones fijas de la app con sinónimos en español.</summary>
    public static class ActionRegistry
    {
        public static List<PaletteAction> BuiltIn()
        {
            return new List<PaletteAction>
            {
                new PaletteAction("nav.home", "Inicio · estado del PC", "Inicio", "estado resumen salud tarjetas comprobar"),
                new PaletteAction("nav.install", "Instalar aplicaciones", "Instalar", "catalogo perfiles programas apps descargar"),
                new PaletteAction("nav.updates", "Actualizaciones de apps", "Actualizaciones", "actualizar versiones nuevas upgrade winget excluir programar"),
                new PaletteAction("nav.system", "Resolución y frecuencia de la pantalla", "Sistema", "monitor hz hercios refresco pantalla resolucion frecuencia"),
                new PaletteAction("nav.system", "Energía: pantalla, suspensión e hibernación", "Sistema", "energia suspender dormir hibernar apagar pantalla bateria plan"),
                new PaletteAction("nav.maintenance", "Liberar espacio en disco", "Mantenimiento", "limpiar limpieza temporales cache papelera espacio disco lleno"),
                new PaletteAction("nav.maintenance", "Reparar Windows (DISM y SFC)", "Mantenimiento", "reparar sfc dism errores sistema archivos corruptos"),
                new PaletteAction("nav.maintenance", "Salud de discos y batería", "Mantenimiento", "smart disco ssd bateria desgaste salud informe equipo"),
                new PaletteAction("nav.security", "Seguridad y antivirus", "Seguridad", "defender antivirus virus amenazas analisis firmas proteccion"),
                new PaletteAction("nav.remote", "Vincular equipos por SSH", "Acceso remoto", "ssh mac remoto terminal tailscale clave vincular conectar"),
                new PaletteAction("nav.settings", "Ajustes de iWinInstaller", "Ajustes", "configuracion opciones version diagnostico actividad registro"),
                new PaletteAction("nav.settings", "Exportar diagnóstico", "Ajustes", "diagnostico log registro error informe soporte"),
                new PaletteAction("nav.settings", "Actualizar iWinInstaller", "Ajustes", "version nueva actualizar app automatica"),
                new PaletteAction("install.report", "Informe de la última instalación", "Instalar", "fallos errores informe reintentar"),
                new PaletteAction("install.resume", "Reanudar lote pendiente", "Instalar", "continuar pausa pendiente lote"),
                new PaletteAction("windowsupdate.open", "Abrir Windows Update", "Windows", "parches actualizaciones windows update"),
                new PaletteAction("classic.open", "Abrir la ventana clásica", "Ajustes", "anterior antigua clasica")
            };
        }
    }
}
