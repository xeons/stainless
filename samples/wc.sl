// SPDX-License-Identifier: 0BSD
//
// `wc`: lines, words and bytes, for each file named or for standard input.
//
//   stainless run samples/wc.sl -- samples/wc.sl
//   stainless run samples/wc.sl -- -l samples/*.sl
//   echo hello world | stainless run samples/wc.sl
//
// The point of the sample is the shape rather than the counting: a program
// that reads its arguments, decides what to do from them, reads a file or
// standard input, and sets an exit code. None of that was expressible before
// `Main` could take a `String[]`.
module Wc;

import Standard.Console;
import Standard.File;
import Standard.IO;
import Standard.Collections;

/// What was asked for. All three when no flag says otherwise, which is what
/// `wc` itself does.
public class Wanted {
    public bool Lines { get; set; }
    public bool Words { get; set; }
    public bool Bytes { get; set; }

    public Wanted() {
        Lines = false;
        Words = false;
        Bytes = false;
    }

    public bool Nothing() { return !Lines && !Words && !Bytes; }

    public void Everything() {
        Lines = true;
        Words = true;
        Bytes = true;
    }
}

/// One file's tally.
public struct Count {
    public long Lines;
    public long Words;
    public long Bytes;
}

/// Counts as `wc` does: a line is a newline, and a word is a run of anything
/// that is not a space. The last line counts only if it ends with a newline,
/// which is why a file with no trailing newline reports one fewer than a
/// reader might expect.
Count Tally(String text) {
    Count found;
    found.Lines = 0;
    found.Words = 0;
    found.Bytes = (long)text.ByteLength();

    bool inWord = false;

    for (nuint i = 0u; i < text.ByteLength(); i += 1u) {
        byte at = text.ByteAt(i);

        if (at == 10u) { found.Lines += 1; }

        bool space = at == 32u || at == 9u || at == 10u || at == 13u || at == 11u || at == 12u;
        if (space) {
            inWord = false;
        } else if (!inWord) {
            inWord = true;
            found.Words += 1;
        }
    }

    return found;
}

String Column(long value) { return Text.FromInteger(value).PadLeft(8u); }

void Report(Wanted wanted, Count found, String label) {
    var line = new StringBuilder();

    if (wanted.Lines) { line.Append(Column(found.Lines)); }
    if (wanted.Words) { line.Append(Column(found.Words)); }
    if (wanted.Bytes) { line.Append(Column(found.Bytes)); }

    if (label.ByteLength() > 0u) {
        line.Append(" ");
        line.Append(label);
    }

    Console.WriteLine(line.ToText());
}

Count Add(Count left, Count right) {
    Count total;
    total.Lines = left.Lines + right.Lines;
    total.Words = left.Words + right.Words;
    total.Bytes = left.Bytes + right.Bytes;
    return total;
}

int Main(String[] args) {
    var wanted = new Wanted();
    var files = new List<String>();
    bool bad = false;

    // A `--` of its own ends the flags, so a file really named `-l` is still
    // reachable. Anything else beginning with a dash is a flag or a mistake.
    bool flagsOver = false;

    foreach (var argument in args) {
        if (!flagsOver && argument == "--") { flagsOver = true; continue; }

        if (!flagsOver && argument.StartsWith("-") && argument.ByteLength() > 1u) {
            if (argument == "-l") { wanted.Lines = true; }
            else if (argument == "-w") { wanted.Words = true; }
            else if (argument == "-c") { wanted.Bytes = true; }
            else if (argument == "-h" || argument == "--help") {
                Console.WriteLine("usage: wc [-l] [-w] [-c] [--] [file ...]");
                return 0;
            } else {
                Console.WriteError("wc: unknown option " + argument);
                bad = true;
            }
            continue;
        }

        files.Add(argument);
    }

    if (bad) { return 2; }
    if (wanted.Nothing()) { wanted.Everything(); }

    // Nothing named means standard input, which is what makes it a filter.
    if (files.Count() == 0u) {
        Report(wanted, Tally(Console.ReadToEnd()), "");
        return 0;
    }

    Count total;
    total.Lines = 0;
    total.Words = 0;
    total.Bytes = 0;

    int failures = 0;

    foreach (var path in files) {
        var read = File.ReadAllText(path);
        if (!read.Ok) {
            Console.WriteError("wc: " + path + ": " + IO.Describe(read.Error));
            failures += 1;
            continue;
        }

        var found = Tally(read.Value);
        total = Add(total, found);
        Report(wanted, found, path);
    }

    // A total only when there was more than one file to total, as `wc` does.
    if (files.Count() > 1u) { Report(wanted, total, "total"); }

    if (failures > 0) { return 1; }
    return 0;
}
