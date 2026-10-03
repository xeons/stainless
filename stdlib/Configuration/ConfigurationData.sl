// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This file is part of the Stainless runtime library. It is free
// software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any
// later version.
//
// It is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// As an additional permission under section 7 of that License, compiling
// a program with Stainless does not by itself place that program under
// the GNU General Public License. See LICENSE.RUNTIME.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

module Standard.Configuration;

import Standard.Collections;

/// The keys and values of a built configuration, shared by every section of it.
internal sealed class ConfigurationData
{
    /// By lowered key.
    public Dictionary<String, String> Values = new Dictionary<String, String>();

    /// Each lowered key as it was first written, in the order first written.
    public Dictionary<String, String> Spellings = new Dictionary<String, String>();

    public List<String> Order = new List<String>();

    public void SetValue(String key, String value)
    {
        String lowered = key.ToLowerAscii();
        if (!Spellings.ContainsKey(lowered))
        {
            Spellings.SetValue(lowered, key);
            Order.Add(lowered);
        }
        Values.SetValue(lowered, value);
    }

    public String? GetValue(String key)
    {
        var found = Values.TryGetValue(key.ToLowerAscii());
        if (found.HasValue)
            return found.GetValue();
        return null;
    }

    /// The parts directly below `path`, as first spelled, in the order first
    /// written; the whole tree's first parts for an empty path.
    public List<String> GetChildKeys(String path)
    {
        String prefix = path.ByteLength() == 0u ? "" : path.ToLowerAscii() + ":";
        var seen = new Dictionary<String, bool>();
        var children = new List<String>();
        for (nuint i = 0u; i < Order.Count; i++)
        {
            String lowered = Order[i];
            if (!lowered.StartsWith(prefix) || lowered.ByteLength() == prefix.ByteLength())
                continue;
            String rest = lowered.Substring(prefix.ByteLength());
            long colon = rest.IndexOf(":");
            String part = colon < 0 ? rest : rest.Substring(0u, (nuint)colon);
            if (seen.ContainsKey(part))
                continue;
            seen.SetValue(part, true);
            String spelled = Spellings.GetValue(lowered);
            children.Add(spelled.Substring(prefix.ByteLength(), part.ByteLength()));
        }
        return children;
    }
}
