// Stainless - an experimental systems language.
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

// Taking paths apart and putting them together.
//
// Purely textual: nothing here touches a disk, and none of it asks whether the
// path exists. Both separators are accepted when reading a path apart, because
// Windows accepts both and a path that came from a config file or a URL may
// use either; `Separator` is what gets written when one is joined.
module Standard.Path;

import Standard.Collections;

/// What `Join` writes between two parts.
public const char Separator = '\\';

/// The other one, accepted everywhere a separator is looked for.
public const char AltSeparator = '/';

bool IsSeparator(byte value) {
    return value == 92 || value == 47;      // '\' and '/'
}

/// The index just past the last separator, or 0 when there is none.
nuint AfterLastSeparator(String path) {
    var bytes = path.ToPointer();
    nuint size = path.ByteLength();

    nuint at = 0;
    for (nuint i = 0; i < size; i = i + 1) {
        if (IsSeparator(bytes[i])) { at = i + 1; }
    }
    return at;
}

/// Joins two parts with a single separator, whichever way each one ends or
/// starts. An empty part contributes nothing.
public String Join(String left, String right) {
    if (left.ByteLength() == 0) { return right; }
    if (right.ByteLength() == 0) { return left; }

    var leftBytes = left.ToPointer();
    var rightBytes = right.ToPointer();

    bool endsWith = IsSeparator(leftBytes[left.ByteLength() - 1]);
    bool startsWith = IsSeparator(rightBytes[0]);

    if (endsWith && startsWith) { return left + right.Substring(1, right.ByteLength() - 1); }
    if (endsWith || startsWith) { return left + right; }

    return left + "\\" + right;
}

public String Join(String first, String second, String third) {
    return Join(Join(first, second), third);
}

/// The last part: `a/b/c.txt` gives `c.txt`.
public String FileName(String path) {
    nuint at = AfterLastSeparator(path);
    return path.Substring(at, path.ByteLength() - at);
}

/// Everything before the last part, without its trailing separator. A path
/// with no separator gives the empty string.
public String DirectoryName(String path) {
    nuint at = AfterLastSeparator(path);
    if (at == 0) { return ""; }

    // Keep a lone leading separator, which is the root rather than nothing.
    if (at == 1) { return path.Substring(0, 1); }
    return path.Substring(0, at - 1);
}

/// The extension, with its dot: `notes.txt` gives `.txt`. No dot in the last
/// part, or a dot that starts it, gives the empty string.
public String Extension(String path) {
    var name = FileName(path);
    var bytes = name.ToPointer();
    nuint size = name.ByteLength();

    for (nuint i = size; i > 1; i = i - 1) {
        if (bytes[i - 1] == 46) { return name.Substring(i - 1, size - i + 1); }
    }
    return "";
}

/// The last part with its extension removed.
public String WithoutExtension(String path) {
    var name = FileName(path);
    var suffix = Extension(name);
    return name.Substring(0, name.ByteLength() - suffix.ByteLength());
}

/// The path with a different extension. `with` may be written with or without
/// its leading dot.
public String WithExtension(String path, String with) {
    var stem = Join(DirectoryName(path), WithoutExtension(path));
    if (with.ByteLength() == 0) { return stem; }
    if (with.ToPointer()[0] == 46) { return stem + with; }
    return stem + "." + with;
}

/// True when the path starts at a root, so that joining it onto another would
/// be a mistake. `/x`, `\x` and `C:\x` are all rooted.
public bool IsRooted(String path) {
    nuint size = path.ByteLength();
    if (size == 0) { return false; }

    var bytes = path.ToPointer();
    if (IsSeparator(bytes[0])) { return true; }

    // A drive letter, as in `C:`.
    return size >= 2 && bytes[1] == 58;
}

/// The parts, with the separators dropped and empty parts skipped.
public List<String> Split(String path) {
    var parts = new List<String>();
    var bytes = path.ToPointer();
    nuint size = path.ByteLength();

    nuint start = 0;
    for (nuint i = 0; i <= size; i = i + 1) {
        bool boundary = i == size || IsSeparator(bytes[i]);
        if (!boundary) { continue; }

        if (i > start) { parts.Add(path.Substring(start, i - start)); }
        start = i + 1;
    }

    return parts;
}
