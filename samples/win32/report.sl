// SPDX-License-Identifier: 0BSD
//
// What Windows will tell you about itself, through the bindings.
//
//   stainless run samples/win32/report.sl bindings/win32 \
//       -l advapi32 -l user32 -l gdi32 -l shell32 -l comdlg32
//
// The whole binding directory this time, which is the easy way in and wants
// every library: compiling a wrapper is what makes its library necessary, and
// the directory has one for each. Naming only the modules this uses would need
// just '-l advapi32', because everything else here is kernel32.
module Report;

import Standard.Console;
import Standard.Collections;
import Win32;
import Win32.AdvApi32;
import Win32.Kernel32;
import Win32.Environment;
import Win32.Files;
import Win32.Machine;
import Win32.Terminal;
import Win32.Clock;
import Win32.Registry;
import Win32.Tasks;

// ANSI, which the console understands once EnableAnsi has been called and which
// is inert text when it has not — so this degrades rather than breaking.
static readonly String Dim = "\x1b[90m";
static readonly String Bold = "\x1b[1m";
static readonly String Plain = "\x1b[0m";

void Row(String label, String value) {
    Console.WriteLine("  " + Dim + Pad(label, 14u) + Plain + value);
}

String Pad(String text, nuint width) {
    String padded = text;
    while (padded.ByteLength() < width) { padded = padded + " "; }
    return padded;
}

void Heading(String text) {
    Console.WriteLine("");
    Console.WriteLine(Bold + text + Plain);
}

static readonly String CurrentVersion =
    "SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion";

/// A string value from HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion,
/// or a dash.
String Version(String name) {
    var opened = Registry.OpenRead(AdvApi32.LocalMachine(), CurrentVersion);
    switch (opened) {
        case Fail why: return "-";
        case Ok held:
            var value = Registry.ReadString(held.Value, name);
            Registry.Close(held.Value);
            return value.ValueOr("-");
    }
}

/// The same, for a value stored as a REG_DWORD rather than a REG_SZ. Asking for
/// the wrong kind is refused rather than reinterpreted, which is why the update
/// build revision needs its own reader: it is a number, and its neighbours are
/// strings.
String VersionNumber(String name) {
    var opened = Registry.OpenRead(AdvApi32.LocalMachine(), CurrentVersion);
    switch (opened) {
        case Fail why: return "-";
        case Ok held:
            var value = Registry.ReadUInt(held.Value, name);
            Registry.Close(held.Value);
            if (!value.Ok) { return "-"; }
            return Text.FromInteger((long)value.Value);
    }
}

int Main() {
    Terminal.EnableAnsi();

    Heading("Windows");
    Row("edition", Version("ProductName"));
    Row("build", Version("CurrentBuild") + "." + VersionNumber("UBR"));
    Row("installed", Version("InstallationType"));
    Row("uptime", Text.FromInteger((long)(Clock.Uptime() / 3600000u)) + " hours");
    Row("local time", Clock.Format(Clock.Now()));
    Row("utc", Clock.Format(Clock.UtcNow()));

    Heading("Machine");
    var system = Machine.NativeInfo();
    Row("name", Environment.ComputerName());
    Row("processors", Text.FromInteger((long)system.ProcessorCount));
    Row("architecture", Machine.ArchitectureName(system.Architecture));
    Row("page size", Text.FromInteger((long)system.PageSize) + " bytes");

    var memory = Machine.Memory();
    Row("memory", Megabytes(memory.TotalPhysical) + " total, "
        + Megabytes(memory.AvailablePhysical) + " free ("
        + Text.FromInteger((long)memory.MemoryLoad) + "% used)");

    Heading("This process");
    Row("executable", Machine.ExecutablePath());
    Row("directory", Environment.CurrentDirectory());
    Row("user", Environment.Expand("%USERNAME%"));
    Row("temp", Files.TempPath());
    Row("command", Environment.CommandLine());

    Heading("Console");
    var size = Terminal.WindowSize();
    Row("window", Text.FromInteger((long)size.X) + " x " + Text.FromInteger((long)size.Y));
    Row("title", Terminal.Title());
    Console.Write("  " + Dim + Pad("colours", 14u) + Plain);
    Swatch();

    Heading("A child process");
    var ran = Tasks.Run("cmd.exe /c ver", "");
    Row("started", Text.FromBool(ran.Started));
    Row("exit code", Text.FromInteger((long)ran.ExitCode));
    Row("said", Trimmed(ran.Output));

    Heading("The system directory");
    var names = Files.Entries(Environment.SystemDirectory());
    Row("entries", Text.FromInteger((long)names.Count()));
    Console.WriteLine("");
    return 0;
}

String Megabytes(ulong bytes) {
    return Text.FromInteger((long)(bytes / 1048576u)) + " MB";
}

/// The eight console colours, set and put back. This one goes through
/// SetConsoleTextAttribute rather than through an escape sequence, so it shows
/// something even on a console where EnableAnsi failed.
void Swatch() {
    for (uint i = 0u; i < 8u; i = (uint)(i + 1u)) {
        Terminal.SetColour(i | Kernel32.ForegroundIntense);
        Console.Write("##");
    }
    Terminal.SetColour(Terminal.DefaultAttributes);
    Console.WriteLine("");
}

/// The first line with anything on it, so that a multi-line answer fits a row
/// and a leading blank line -- which `cmd /c ver` produces -- does not read as
/// an empty answer.
String Trimmed(String text) {
    nuint from = 0u;
    while (from < text.ByteLength() && IsBreak(text.Substring(from, 1u))) {
        from = from + 1u;
    }

    nuint to = from;
    while (to < text.ByteLength() && !IsBreak(text.Substring(to, 1u))) {
        to = to + 1u;
    }

    return text.Substring(from, to - from);
}

bool IsBreak(String one) { return one == "\r" || one == "\n"; }
