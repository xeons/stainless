// The other half, which is the one that says so on Linux.
//
// Built for Windows, so the description must be CodeView -- which is what
// Visual Studio, WinDbg, minidumps and Windows Error Reporting read, and the
// only thing they read.
module Format;

int Main()
{
    int counted = 3;
    return counted - 3;
}
