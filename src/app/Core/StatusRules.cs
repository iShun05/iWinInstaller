using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

namespace IWinInstaller.App.Core
{
    /// <summary>Resultado de una comprobación antes de aplicarlo a su tarjeta.</summary>
    public sealed class StatusResult
    {
        public StatusResult(StatusState state, string summary, string reason = "", string actionId = "")
        {
            State = state; Summary = summary; Reason = reason ?? ""; ActionId = actionId ?? "";
        }
        public StatusState State { get; private set; }
        public string Summary { get; private set; }
        public string Reason { get; private set; }
        public string ActionId { get; private set; }

        public static StatusResult Unknown(string summary, string reason) { return new StatusResult(StatusState.Unknown, summary, reason); }

        /// <summary>Copia con otro motivo (p. ej. el mensaje de error real de Windows).</summary>
        public StatusResult WithReason(string reason) { return new StatusResult(State, Summary, String.IsNullOrWhiteSpace(reason) ? Reason : reason, ActionId); }
    }

    /// <summary>Salud de un disco tal como la expone Windows (MSFT_PhysicalDisk).</summary>
    public sealed class DiskHealthInfo
    {
        public string Name { get; set; }
        /// <summary>0 correcto, 1 aviso, 2 en mal estado, 5 desconocido.</summary>
        public int HealthStatus { get; set; }
    }

    /// <summary>Reglas puras de las tarjetas del Inicio: sin acceso al sistema, fáciles de probar.</summary>
    public static class StatusRules
    {
        private static readonly CultureInfo Es = new CultureInfo("es-ES");

        /// <summary>Espacio del disco del sistema: atención por debajo del 10 % o de 15 GB libres.</summary>
        public static StatusResult DiskSpace(long freeBytes, long totalBytes)
        {
            if (totalBytes <= 0 || freeBytes < 0) return StatusResult.Unknown("No se pudo leer el disco del sistema", "Windows no devolvió el tamaño del disco.");
            double freeGb = freeBytes / 1073741824.0;
            double percent = 100.0 * freeBytes / totalBytes;
            string summary = String.Format(Es, "{0:0.#} GB libres ({1:0} %)", freeGb, percent);
            if (percent < 10 || freeGb < 15)
                return new StatusResult(StatusState.Attention, summary, "Queda poco espacio: Windows y las actualizaciones necesitan margen.", "maintenance.clean");
            return new StatusResult(StatusState.Ok, summary, "", "maintenance.clean");
        }

        /// <summary>Desgaste de la batería: atención a partir del 40 %. Sin batería, la tarjeta no aplica.</summary>
        public static StatusResult Battery(long designedCapacity, long fullChargeCapacity)
        {
            if (designedCapacity <= 0 && fullChargeCapacity <= 0)
                return new StatusResult(StatusState.NotApplicable, "Sin batería");
            if (designedCapacity <= 0 || fullChargeCapacity <= 0)
                return StatusResult.Unknown("No se pudo leer la batería", "Windows no informa de la capacidad de diseño o de carga completa.");
            double wear = Math.Max(0, 100.0 * (designedCapacity - fullChargeCapacity) / designedCapacity);
            string summary = String.Format(Es, "Desgaste {0:0} % (capacidad {1:0} %)", wear, 100 - wear);
            if (wear >= 40)
                return new StatusResult(StatusState.Attention, summary, "La batería conserva menos del 60 % de su capacidad original.", "maintenance.battery");
            return new StatusResult(StatusState.Ok, summary, "", "maintenance.battery");
        }

        /// <summary>Salud de los discos físicos: cualquier aviso o fallo pide atención.</summary>
        public static StatusResult DiskHealth(IList<DiskHealthInfo> disks)
        {
            if (disks == null) return StatusResult.Unknown("No se pudo leer la salud de los discos", "Windows no expone el estado de los discos en este equipo.");
            if (disks.Count == 0) return new StatusResult(StatusState.NotApplicable, "Sin discos con estado de salud");
            var bad = disks.Where(d => d.HealthStatus == 1 || d.HealthStatus == 2).ToList();
            if (bad.Count > 0)
            {
                string names = String.Join(", ", bad.Select(d => d.Name + (d.HealthStatus == 2 ? " (en mal estado)" : " (aviso)")));
                return new StatusResult(StatusState.Attention, "Revisa: " + names, "Haz una copia de seguridad de lo importante cuanto antes.", "maintenance.health");
            }
            if (disks.All(d => d.HealthStatus == 5))
                return StatusResult.Unknown("Salud de los discos desconocida", "Los discos no informan de su estado.");
            return new StatusResult(StatusState.Ok, disks.Count == 1 ? "Disco en buen estado" : disks.Count + " discos en buen estado", "", "maintenance.health");
        }

        /// <summary>Reinicio pendiente de Windows o de una instalación.</summary>
        public static StatusResult Reboot(bool? pending)
        {
            if (!pending.HasValue) return StatusResult.Unknown("No se pudo comprobar si falta reiniciar", "No se pudieron leer las claves de reinicio de Windows.");
            return pending.Value
                ? new StatusResult(StatusState.Attention, "Reinicio pendiente", "Windows o una instalación terminarán de aplicarse al reiniciar.")
                : new StatusResult(StatusState.Ok, "Sin reinicio pendiente");
        }
    }
}
