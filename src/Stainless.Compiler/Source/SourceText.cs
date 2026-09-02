// Stainless - an experimental systems language.
// Copyright (C) 2026 Brandon Scott
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

namespace Stainless.Source;

/// <summary>A single Stainless source file, plus the line table used for diagnostics.</summary>
public sealed class SourceText
{
    public string Path { get; }
    public string Text { get; }
    private readonly int[] _lineStarts;

    public SourceText(string path, string text)
    {
        Path = path;
        Text = text;
        var starts = new List<int> { 0 };
        for (int i = 0; i < text.Length; i++)
            if (text[i] == '\n') starts.Add(i + 1);
        _lineStarts = starts.ToArray();
    }

    public static SourceText FromFile(string path) => new(path, File.ReadAllText(path));

    /// <summary>Maps an absolute offset to a 1-based (line, column) pair.</summary>
    public (int Line, int Column) GetLineColumn(int position)
    {
        int lo = 0, hi = _lineStarts.Length - 1;
        while (lo < hi)
        {
            int mid = (lo + hi + 1) / 2;
            if (_lineStarts[mid] <= position) lo = mid; else hi = mid - 1;
        }
        return (lo + 1, position - _lineStarts[lo] + 1);
    }

    public string GetLine(int lineNumber)
    {
        int idx = lineNumber - 1;
        if (idx < 0 || idx >= _lineStarts.Length) return "";
        int start = _lineStarts[idx];
        int end = idx + 1 < _lineStarts.Length ? _lineStarts[idx + 1] : Text.Length;
        return Text[start..end].TrimEnd('\r', '\n');
    }
}

/// <summary>A half-open range of characters within a <see cref="SourceText"/>.</summary>
public readonly record struct SourceSpan(SourceText File, int Start, int End)
{
    public int Length => End - Start;
    public static SourceSpan Merge(SourceSpan a, SourceSpan b) =>
        new(a.File, Math.Min(a.Start, b.Start), Math.Max(a.End, b.End));
    public override string ToString()
    {
        var (line, col) = File.GetLineColumn(Start);
        return $"{File.Path}({line},{col})";
    }
}
