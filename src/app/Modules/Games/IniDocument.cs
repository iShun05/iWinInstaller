using System;
using System.Collections.Generic;
using System.Text;

namespace IWinInstaller.App.Modules.Games
{
    /// <summary>
    /// Archivo .ini de Unreal (GameUserSettings.ini) editado por líneas: solo cambia las líneas que se tocan y
    /// conserva el resto byte a byte, la codificación, el BOM y los saltos de línea. Secciones y claves sin
    /// distinguir mayúsculas. Las líneas con prefijo de Unreal (+, -, ., !) y los comentarios no se tocan.
    /// </summary>
    public sealed class IniDocument
    {
        private sealed class Line
        {
            public string Text;
            public string NewLine;
        }

        private readonly List<Line> _lines = new List<Line>();
        private readonly Encoding _encoding;
        private readonly byte[] _preamble;
        private readonly string _defaultNewLine;

        private IniDocument(Encoding encoding, byte[] preamble, string text)
        {
            _encoding = encoding;
            _preamble = preamble;
            int crlf = 0, lf = 0, start = 0;
            for (int i = 0; i < text.Length; i++)
            {
                if (text[i] != '\n') continue;
                bool cr = i > 0 && text[i - 1] == '\r';
                if (cr) crlf++; else lf++;
                _lines.Add(new Line { Text = text.Substring(start, (cr ? i - 1 : i) - start), NewLine = cr ? "\r\n" : "\n" });
                start = i + 1;
            }
            if (start < text.Length) _lines.Add(new Line { Text = text.Substring(start), NewLine = "" });
            _defaultNewLine = lf > crlf ? "\n" : "\r\n";
        }

        public static IniDocument Parse(byte[] bytes)
        {
            if (bytes == null) bytes = new byte[0];
            if (bytes.Length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF)
                return new IniDocument(new UTF8Encoding(false), new byte[] { 0xEF, 0xBB, 0xBF }, Encoding.UTF8.GetString(bytes, 3, bytes.Length - 3));
            if (bytes.Length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE)
                return new IniDocument(new UnicodeEncoding(false, false), new byte[] { 0xFF, 0xFE }, Encoding.Unicode.GetString(bytes, 2, bytes.Length - 2));
            if (bytes.Length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF)
                return new IniDocument(new UnicodeEncoding(true, false), new byte[] { 0xFE, 0xFF }, Encoding.BigEndianUnicode.GetString(bytes, 2, bytes.Length - 2));
            return new IniDocument(new UTF8Encoding(false), new byte[0], new UTF8Encoding(false).GetString(bytes));
        }

        public byte[] ToBytes()
        {
            var sb = new StringBuilder();
            foreach (var line in _lines) sb.Append(line.Text).Append(line.NewLine);
            byte[] body = _encoding.GetBytes(sb.ToString());
            var result = new byte[_preamble.Length + body.Length];
            Buffer.BlockCopy(_preamble, 0, result, 0, _preamble.Length);
            Buffer.BlockCopy(body, 0, result, _preamble.Length, body.Length);
            return result;
        }

        /// <summary>Valor de la primera clave de la sección, o null si no existe.</summary>
        public string Get(string section, string key)
        {
            int start, end;
            if (!FindSection(section, out start, out end)) return null;
            int index = FindKey(key, start, end);
            if (index < 0) return null;
            string text = _lines[index].Text;
            return text.Substring(text.IndexOf('=') + 1).Trim();
        }

        /// <summary>Cambia la primera clave de la sección; si falta la añade y si falta la sección la crea al final.</summary>
        public void Set(string section, string key, string value)
        {
            int start, end;
            if (!FindSection(section, out start, out end))
            {
                if (_lines.Count > 0 && _lines[_lines.Count - 1].NewLine.Length == 0) _lines[_lines.Count - 1].NewLine = _defaultNewLine;
                if (_lines.Count > 0 && _lines[_lines.Count - 1].Text.Trim().Length > 0) _lines.Add(new Line { Text = "", NewLine = _defaultNewLine });
                _lines.Add(new Line { Text = "[" + section + "]", NewLine = _defaultNewLine });
                _lines.Add(new Line { Text = key + "=" + value, NewLine = _defaultNewLine });
                return;
            }
            int index = FindKey(key, start, end);
            if (index >= 0)
            {
                string text = _lines[index].Text;
                int eq = text.IndexOf('=');
                _lines[index].Text = text.Substring(0, eq + 1) + value;
                return;
            }
            // Tras la última línea con contenido de la sección
            int insertAt = end;
            while (insertAt > start + 1 && _lines[insertAt - 1].Text.Trim().Length == 0) insertAt--;
            var previous = _lines[insertAt - 1];
            string newLine = _defaultNewLine;
            if (previous.NewLine.Length == 0)
            {
                // La sección acababa el archivo sin salto final: se conserva así
                previous.NewLine = _defaultNewLine;
                newLine = "";
            }
            _lines.Insert(insertAt, new Line { Text = key + "=" + value, NewLine = newLine });
        }

        /// <summary>Línea de cabecera de la sección (start) y primera línea de la siguiente sección o el final (end).</summary>
        private bool FindSection(string section, out int start, out int end)
        {
            start = -1; end = _lines.Count;
            for (int i = 0; i < _lines.Count; i++)
            {
                string t = _lines[i].Text.Trim();
                if (!(t.StartsWith("[", StringComparison.Ordinal) && t.EndsWith("]", StringComparison.Ordinal))) continue;
                if (start >= 0) { end = i; return true; }
                if (string.Equals(t.Substring(1, t.Length - 2), section, StringComparison.OrdinalIgnoreCase)) start = i;
            }
            return start >= 0;
        }

        private int FindKey(string key, int start, int end)
        {
            for (int i = start + 1; i < end; i++)
            {
                string t = _lines[i].Text.TrimStart();
                if (t.Length == 0 || "+-.!;#".IndexOf(t[0]) >= 0) continue;
                int eq = t.IndexOf('=');
                if (eq <= 0) continue;
                if (string.Equals(t.Substring(0, eq).Trim(), key, StringComparison.OrdinalIgnoreCase)) return i;
            }
            return -1;
        }
    }
}
