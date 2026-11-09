using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using IWinInstaller.App.Core;

namespace IWinInstaller.App.Modules.Install
{
    /// <summary>Un paso de «Después de instalar» que confirma el usuario.</summary>
    public sealed class GuideStep : ObservableObject
    {
        private bool _isDone;
        public GuideStep(int index, string text, bool done) { Index = index; Text = text; _isDone = done; }
        public int Index { get; private set; }
        public string Text { get; private set; }
        public bool IsDone { get { return _isDone; } set { Set(ref _isDone, value); } }
    }

    /// <summary>«Pasos y notas» de una opción: pasos marcables, nota propia y comprobación técnica.</summary>
    public sealed class GuideViewModel : ObservableObject
    {
        private string _userNote;
        private string _technical = "";
        private bool? _technicalOk;

        public GuideViewModel(string id, string name, IEnumerable<string> steps, IEnumerable<int> done, string note, string link, string linkLabel, string userNote)
        {
            Id = id; Name = name; Note = note ?? ""; Link = link ?? ""; LinkLabel = String.IsNullOrEmpty(linkLabel) ? "Abrir la página del fabricante" : linkLabel;
            _userNote = userNote ?? "";
            var doneSet = new HashSet<int>(done ?? Enumerable.Empty<int>());
            Steps = new ObservableCollection<GuideStep>((steps ?? Enumerable.Empty<string>()).Select((text, i) => new GuideStep(i, text, doneSet.Contains(i))));
        }

        public string Id { get; private set; }
        public string Name { get; private set; }
        public string Note { get; private set; }
        public string Link { get; private set; }
        public string LinkLabel { get; private set; }
        public bool HasLink { get { return Link.StartsWith("https://", StringComparison.Ordinal); } }
        public ObservableCollection<GuideStep> Steps { get; private set; }
        public string UserNote { get { return _userNote; } set { Set(ref _userNote, (value ?? "").Length > 2000 ? value.Substring(0, 2000) : (value ?? "")); } }
        public string Technical { get { return _technical; } set { Set(ref _technical, value ?? ""); } }
        public bool? TechnicalOk { get { return _technicalOk; } set { Set(ref _technicalOk, value); } }

        public int[] DoneIndexes { get { return Steps.Where(s => s.IsDone).Select(s => s.Index).ToArray(); } }
        public bool AllDone { get { return Steps.Count > 0 && Steps.All(s => s.IsDone); } }
        public string Summary
        {
            get
            {
                int left = Steps.Count(s => !s.IsDone);
                return left == 0 ? "Pasos confirmados por ti" : left + (left == 1 ? " paso pendiente" : " pasos pendientes");
            }
        }
        public void Refresh() { OnPropertyChanged("Summary"); OnPropertyChanged("AllDone"); }
    }
}
