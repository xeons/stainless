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

/// Taking paths apart and putting them together.
///
/// Purely textual: nothing here touches a disk, and none of it asks whether the
/// path exists.
///
/// **What counts as a separator is the platform's business, not a preference.**
/// Windows accepts both `\` and `/` everywhere, so both are read apart there and
/// a path from a config file or a URL works either way. Linux and macOS accept
/// only `/` -- and a backslash there is not a separator being generously
/// allowed, it is an ordinary character that a filename may contain. Treating
/// `report\2026.csv` as two parts on Linux is not lenient, it is wrong.
///
/// So the questions this module answers have different answers on different
/// platforms, and it says which rather than picking one.
module Standard.Path;

import Standard.Collections;

#if WINDOWS

/// What `Join` writes between two parts.
public const char Separator = '\\';

/// The other one, accepted everywhere a separator is looked for.
public const char AltSeparator = '/';

bool IsSeparator(byte value)
{
    return value == 92 || value == 47;      // '\' and '/'
}

#else

/// What `Join` writes between two parts.
public const char Separator = '/';

/// The same one: there is no second separator outside Windows.
public const char AltSeparator = '/';

bool IsSeparator(byte value)
{
    return value == 47;                     // '/', and nothing else
}

#endif

/// The index just past the last separator, or 0 when there is none.
nuint AfterLastSeparator(String path)
{
    var bytes = path.ToPointer();
    nuint size = path.ByteLength();

    nuint at = 0;
    for (nuint i = 0; i < size; i++)
    {
        if (IsSeparator(bytes[i]))
            at = i + 1;
    }
    return at;
}

/// Joins two parts with a single separator, whichever way each one ends or
/// starts. An empty part contributes nothing.
public String Join(String left, String right)
{
    if (left.ByteLength() == 0)
        return right;
    if (right.ByteLength() == 0)
        return left;

    var leftBytes = left.ToPointer();
    var rightBytes = right.ToPointer();

    bool endsWith = IsSeparator(leftBytes[left.ByteLength() - 1]);
    bool startsWith = IsSeparator(rightBytes[0]);

    if (endsWith && startsWith)
        return left + right.Substring(1, right.ByteLength() - 1);
    if (endsWith || startsWith)
        return left + right;

    return left + SeparatorText() + right;
}

/// `Separator` as text, since that is what joining needs.
String SeparatorText()
{
    byte one = (byte)Separator;
    return Text.FromBytes(&one, 1);
}

/// Three parts joined left to right, with the same rule at each step.
public String Join(String first, String second, String third)
{
    return Join(Join(first, second), third);
}

/// The last part: `a/b/c.txt` gives `c.txt`.
public String FileName(String path)
{
    nuint at = AfterLastSeparator(path);
    return path.Substring(at, path.ByteLength() - at);
}

/// Everything before the last part, without its trailing separator. A path
/// with no separator gives the empty string.
///
/// A root keeps its separator, because without it the answer names somewhere
/// else: `/foo` gives `/`, and on Windows `C:\foo` gives `C:\`, where `C:`
/// alone would be that drive's current directory.
public String DirectoryName(String path)
{
    nuint at = AfterLastSeparator(path);
    if (at == 0)
        return "";

    if (at == 1 || IsDriveRoot(path, at))
        return path.Substring(0, at);
    return path.Substring(0, at - 1);
}

#if WINDOWS

/// Whether the first `length` bytes are a drive letter's root, as in `C:\`.
bool IsDriveRoot(String path, nuint length)
{
    return length == 3 && path.ToPointer()[1] == 58;
}

#else

/// A drive letter is an ordinary name outside Windows.
bool IsDriveRoot(String path, nuint length) => false;

#endif

/// Where the extension's dot is in the last part `name`, or the length of
/// `name` when there is no dot. A dot that starts the name is not one.
nuint ExtensionDotAt(String name)
{
    var bytes = name.ToPointer();
    nuint size = name.ByteLength();

    for (nuint i = size; i > 1; i--)
    {
        if (bytes[i - 1] == 46)
            return i - 1;
    }
    return size;
}

/// The extension, with its dot: `notes.txt` gives `.txt`. No dot in the last
/// part, a dot that starts it, or a dot that ends it gives the empty string.
public String Extension(String path)
{
    var name = FileName(path);
    nuint dot = ExtensionDotAt(name);
    nuint size = name.ByteLength();
    if (dot + 1 >= size)
        return "";
    return name.Substring(dot, size - dot);
}

/// The last part with its extension removed. A trailing dot goes with it.
public String WithoutExtension(String path)
{
    var name = FileName(path);
    return name.Substring(0, ExtensionDotAt(name));
}

/// The path with a different extension. `with` may be written with or without
/// its leading dot. Nothing before the last part is touched.
public String WithExtension(String path, String with)
{
    var stem = path.Substring(0, AfterLastSeparator(path)) + WithoutExtension(path);
    if (with.ByteLength() == 0)
        return stem;
    if (with.ToPointer()[0] == 46)
        return stem + with;
    return $"{stem}.{with}";
}

/// True when the path starts at a root, so that joining it onto another would
/// be a mistake.
///
/// `/x` is rooted everywhere. `\x` and `C:\x` are rooted on Windows and are
/// ordinary relative names elsewhere, where a colon and a backslash are both
/// characters a filename may contain.
public bool IsRooted(String path)
{
    nuint size = path.ByteLength();
    if (size == 0)
        return false;

    var bytes = path.ToPointer();
    if (IsSeparator(bytes[0]))
        return true;

#if WINDOWS
    // A drive letter, as in `C:`.
    return size >= 2 && bytes[1] == 58;
#else
    return false;
#endif
}

/// Whether two paths name the same file, as text.
///
/// It settles the two differences the platform itself creates: Windows accepts
/// `/` and `\` interchangeably and matches names without regard to case,
/// Linux does neither. A compiler joining a directory to a file name writes
/// `C:\src\obj/Text.sl`, one separator from each half, and `==` says that is
/// a different file from `C:\src\obj\Text.sl`.
///
/// Nothing is opened, followed or resolved. A caller that needs `..` or a
/// relative path resolved MUST do that first.
///
/// Only ASCII letters are case-folded. Windows folds more, with a table that
/// has changed between releases, so two paths differing only in the case of a
/// non-ASCII letter are reported as different.
public bool SamePath(String left, String right)
{
    if (left.ByteLength() != right.ByteLength())
        return false;

    var a = left.ToPointer();
    var b = right.ToPointer();
    nuint size = left.ByteLength();

    for (nuint i = 0u; i < size; i++)
    {
        if (a[i] == b[i])
            continue;
        if (!SameByteInAPath(a[i], b[i]))
            return false;
    }
    return true;
}

#if WINDOWS

/// Two bytes that differ but do not make two paths differ.
bool SameByteInAPath(byte left, byte right)
{
    return (IsSeparator(left) && IsSeparator(right))
        || LowerAscii(left) == LowerAscii(right);
}

byte LowerAscii(byte value) => value >= 65 && value <= 90 ? (byte)(value + 32) : value;

#else

/// Outside Windows a path is bytes: two that differ differ.
bool SameByteInAPath(byte left, byte right) => false;

#endif

/// The parts, with the separators dropped and empty parts skipped.
public List<String> Split(String path)
{
    var parts = new List<String>();
    var bytes = path.ToPointer();
    nuint size = path.ByteLength();

    nuint start = 0;
    for (nuint i = 0; i <= size; i++)
    {
        bool boundary = i == size || IsSeparator(bytes[i]);
        if (!boundary)
            continue;

        if (i > start)
            parts.Add(path.Substring(start, i - start));
        start = i + 1;
    }

    return parts;
}
