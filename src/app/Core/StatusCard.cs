using System;

namespace IWinInstaller.App.Core
{
    /// <summary>Estado de una tarjeta del Inicio. «Unknown» nunca se presenta como correcto.</summary>
    public enum StatusState { Unknown, Ok, Attention, NotApplicable }

    /// <summary>Una tarjeta del Inicio: qué se comprobó, cómo está y qué acción lo resuelve.</summary>
    public sealed class StatusCard : ObservableObject
    {
        private StatusState _state = StatusState.Unknown;
        private string _summary = "Comprobando…";
        private string _reason = "";
        private string _actionId = "";
        private DateTime? _checkedAt;
        private bool _isLoading = true;

        public StatusCard(string area, string title)
        {
            Area = area;
            Title = title;
        }

        public string Area { get; private set; }
        public string Title { get; private set; }
        public StatusState State { get { return _state; } private set { if (Set(ref _state, value)) { OnPropertyChanged("StateText"); OnPropertyChanged("IsVisible"); } } }
        public string Summary { get { return _summary; } private set { Set(ref _summary, value); } }
        public string Reason { get { return _reason; } private set { if (Set(ref _reason, value)) OnPropertyChanged("HasReason"); } }
        public string ActionId { get { return _actionId; } private set { if (Set(ref _actionId, value)) OnPropertyChanged("HasAction"); } }
        public DateTime? CheckedAt { get { return _checkedAt; } private set { Set(ref _checkedAt, value); } }
        public bool IsLoading { get { return _isLoading; } private set { Set(ref _isLoading, value); } }

        public bool HasReason { get { return !String.IsNullOrWhiteSpace(Reason); } }
        public bool HasAction { get { return !String.IsNullOrWhiteSpace(ActionId); } }
        public bool IsVisible { get { return State != StatusState.NotApplicable; } }

        public string StateText
        {
            get
            {
                switch (State)
                {
                    case StatusState.Ok: return "Correcto";
                    case StatusState.Attention: return "Requiere atención";
                    case StatusState.NotApplicable: return "No aplica";
                    default: return IsLoading ? "Comprobando" : "No se pudo comprobar";
                }
            }
        }

        /// <summary>Aplica un resultado. Un estado desconocido sin motivo recibe uno genérico.</summary>
        public void Apply(StatusState state, string summary, string reason, string actionId)
        {
            if (state == StatusState.Unknown && String.IsNullOrWhiteSpace(reason))
                reason = "La comprobación no devolvió datos.";
            IsLoading = false;
            Summary = summary ?? "";
            Reason = reason ?? "";
            ActionId = actionId ?? "";
            CheckedAt = DateTime.Now;
            State = state;
            OnPropertyChanged("StateText");
        }

        public static StatusState ParseState(string value)
        {
            switch ((value ?? "").Trim().ToLowerInvariant())
            {
                case "ok": return StatusState.Ok;
                case "attention": return StatusState.Attention;
                case "notapplicable": return StatusState.NotApplicable;
                default: return StatusState.Unknown;
            }
        }
    }
}
