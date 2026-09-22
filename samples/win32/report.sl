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

// ANSI, which the console understands once EnableAnsiEscapes has been called
// and which is inert text when it has not — so this degrades rather than
// breaking.
static readonly String Dim = "\x1b[90m";
static readonly String Bold = "\x1b[1m";
static readonly String Plain = "\x1b[0m";

void PrintRow(String label, String value)
{
    Console.WriteLine("  " + Dim + PadText(label, 14u) + Plain + value);
}

String PadText(String text, nuint width)
{
    String padded = text;
    while (padded.ByteLength() < width)
        padded += " ";
    return padded;
}

void PrintHeading(String text)
{
    Console.WriteLine("");
    Console.WriteLine(Bold + text + Plain);
}

static readonly String CurrentVersion =
    "SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion";

/// A string value from HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion,
/// or a dash.
String ReadVersionString(String name)
{
    var opened = Registry.OpenKeyForReading(AdvApi32.LocalMachine(), CurrentVersion);
    switch (opened)
    {
        case Fail why: return "-";
        case Ok held:
            var value = Registry.ReadString(held.Value, name);
            Registry.CloseKey(held.Value);
            return value.ValueOr("-");
    }
}

/// The same, for a value stored as a REG_DWORD rather than a REG_SZ. Asking for
/// the wrong kind is refused rather than reinterpreted, which is why the update
/// build revision needs its own reader: it is a number, and its neighbours are
/// strings.
String ReadVersionNumber(String name)
{
    var opened = Registry.OpenKeyForReading(AdvApi32.LocalMachine(), CurrentVersion);
    switch (opened)
    {
        case Fail why: return "-";
        case Ok held:
            var value = Registry.ReadUInt(held.Value, name);
            Registry.CloseKey(held.Value);
            if (!value.Ok)
                return "-";
            return Text.FromInteger((long)value.Value);
    }
}

int Main()
{
    Terminal.EnableAnsiEscapes();

    PrintHeading("Windows");
    PrintRow("edition", ReadVersionString("ProductName"));
    PrintRow("build", ReadVersionString("CurrentBuild") + "." + ReadVersionNumber("UBR"));
    PrintRow("installed", ReadVersionString("InstallationType"));
    ulong hours = Clock.GetUptimeMilliseconds() / 3600000u;
    PrintRow("uptime", Text.FromInteger((long)hours) + " hours");
    PrintRow("local time", Clock.FormatSystemTime(Clock.GetLocalNow()));
    PrintRow("utc", Clock.FormatSystemTime(Clock.GetUtcNow()));

    PrintHeading("Machine");
    var system = Machine.QueryNativeSystemInfo();
    PrintRow("name", Environment.GetComputerName());
    PrintRow("processors", Text.FromInteger((long)system.ProcessorCount));
    PrintRow("architecture", Machine.GetArchitectureName(system.Architecture));
    PrintRow("page size", Text.FromInteger((long)system.PageSize) + " bytes");

    var memory = Machine.QueryMemoryStatus();
    PrintRow("memory", FormatMegabytes(memory.TotalPhysical) + " total, "
        + FormatMegabytes(memory.AvailablePhysical) + " free ("
        + Text.FromInteger((long)memory.MemoryLoad) + "% used)");

    PrintHeading("This process");
    PrintRow("executable", Machine.GetExecutablePath());
    PrintRow("directory", Environment.GetCurrentDirectory());
    PrintRow("user", Environment.ExpandEnvironmentVariables("%USERNAME%"));
    PrintRow("temp", Files.GetTempPath());
    PrintRow("command", Environment.GetCommandLine());

    PrintHeading("Console");
    var size = Terminal.GetWindowSize();
    PrintRow("window", Text.FromInteger((long)size.X) + " x " + Text.FromInteger((long)size.Y));
    PrintRow("title", Terminal.GetTitle());
    Console.Write("  " + Dim + PadText("colours", 14u) + Plain);
    PrintColourSwatch();

    PrintHeading("A child process");
    var ran = Tasks.RunProcess("cmd.exe /c ver", "");
    PrintRow("started", Text.FromBool(ran.Started));
    PrintRow("exit code", Text.FromInteger((long)ran.ExitCode));
    PrintRow("said", FindFirstNonBlankLine(ran.Output));

    PrintHeading("The system directory");
    var names = Files.GetDirectoryEntries(Environment.GetSystemDirectory());
    PrintRow("entries", Text.FromInteger((long)names.Count));
    Console.WriteLine("");
    return 0;
}

String FormatMegabytes(ulong bytes)
{
    return Text.FromInteger((long)(bytes / 1048576u)) + " MB";
}

/// The eight console colours, set and put back. This one goes through
/// SetConsoleTextAttribute rather than through an escape sequence, so it shows
/// something even on a console where EnableAnsiEscapes failed.
void PrintColourSwatch()
{
    for (uint i = 0u; i < 8u; i = (uint)(i + 1u))
    {
        Terminal.SetColour(i | Kernel32.ForegroundIntense);
        Console.Write("##");
    }
    Terminal.SetColour(Terminal.DefaultAttributes);
    Console.WriteLine("");
}

/// The first line with anything on it, so that a multi-line answer fits a row
/// and a leading blank line -- which `cmd /c ver` produces -- does not read as
/// an empty answer.
String FindFirstNonBlankLine(String text)
{
    foreach (var line in text.SplitLines())
    {
        if (line.Trim().ByteLength() > 0u)
            return line.Trim();
    }
    return "";
}
