# Captures what a window actually drew, on Windows.
#
#   .\forms\screenshot.ps1 -Program .\ide\build\stainless-ide.exe -Out shots\ide.png
#   .\forms\screenshot.ps1 -Program .\samples\forms\build\buttons.exe -Arguments 1
#   .\forms\screenshot.ps1 -ProcessId 1234 -Out shots\now.png -Keep
#   .\forms\screenshot.ps1 -Program .\ide\build\stainless-ide.exe -Shots 3 -Every 1500
#
# **It asks the window to draw itself and never reads the screen.** That is the
# whole point of the tool and it buys three things at once:
#
#   - It works with no visible desktop and over a disconnected session, where
#     `CopyFromScreen` answers black.
#   - It captures the window even when something is in front of it, so a build
#     running in the background does not have to own the foreground.
#   - It captures *only* the program under test. A screen grab on a real
#     machine takes in whatever else that machine happens to be showing, which
#     is somebody's private business and has no place in a bug report.
#
# A self test proves the model and only a picture proves the view --
# forms/README.md has the long version, and `forms/` passed 116 checks for
# months while a control was one pixel wide. This is how the picture is taken.
#
# On Linux there is no equivalent: the box has no window manager, so a program
# is opened on a virtual screen and the screen is captured. forms/README.md has
# that recipe.

param(
    # The program to start and capture. Either this or -ProcessId.
    [string] $Program = "",

    # An already-running process to capture instead. Named this rather than
    # -Pid because `$Pid` is one of PowerShell's automatic variables and a
    # parameter of that name silently shadows it; `$Args` is the same trap and
    # cost an afternoon once, which is why the next one is -Arguments.
    [int] $ProcessId = 0,

    # Arguments for -Program.
    [string[]] $Arguments = @(),

    # Where the picture goes. With -Shots above 1 the number is inserted before
    # the extension: shots\ide.png becomes shots\ide-1.png, shots\ide-2.png.
    [string] $Out = "shots\window.png",

    # How long to wait for a window to appear, in seconds. The handle does not
    # exist the instant the process does, so this polls rather than sleeping.
    [int] $Settle = 10,

    # How many pictures, and how far apart in milliseconds. More than one is
    # for watching something change -- a build filling its output pane.
    [int] $Shots = 1,
    [int] $Every = 1000,

    # Also capture menus, drop-downs and tooltips. They are top-level windows
    # of their own and are *not* part of the main window's picture, so a
    # context menu is invisible without this.
    [switch] $Popups,

    # Pick the window by a fragment of its title, for a program with more than
    # one. Without it the process's main window is used.
    [string] $Title = "",

    # Leave the program running afterwards. Without it the process is ended,
    # because a program still holding its own binary makes the next build fail
    # with "permission denied" and report it as a compiler bug.
    [switch] $Keep,

    # Print the windows found and capture nothing.
    [switch] $List
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class WindowShot
{
    public delegate bool EnumProc(IntPtr window, IntPtr carried);

    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr w, IntPtr dc, uint flags);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr w, out RECT r);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr w);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr w);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr carried);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr w, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetClassNameW(IntPtr w, StringBuilder text, int max);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowTextW(IntPtr w, StringBuilder text, int max);
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr w, uint kind);

    public const uint Owner = 4;   // GW_OWNER

    /// <summary>
    /// Whether a window belongs to <paramref name="root"/> -- a menu it put
    /// up, a dialog it opened, a drop-down one of its combo boxes owns.
    ///
    /// **The process is not the test, which is what this replaces.** A GUI
    /// program started from a console has that console in the same process, so
    /// "every visible window of this process" pulled a terminal into the
    /// picture. Ownership is the relationship that actually means "this window
    /// is part of what that window is doing".
    ///
    /// The chain is walked rather than checked once: a menu opened from a
    /// dialog is owned by the dialog, which is owned by the window.
    /// </summary>
    public static bool BelongsTo(IntPtr window, IntPtr root)
    {
        IntPtr owner = GetWindow(window, Owner);
        for (int step = 0; step < 8 && owner != IntPtr.Zero; step++)
        {
            if (owner == root) return true;
            owner = GetWindow(owner, Owner);
        }
        return false;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    // PW_RENDERFULLCONTENT. Without it a window whose content is composited
    // rather than painted in the old way comes back blank.
    public const uint RenderFullContent = 2;

    public static List<IntPtr> VisibleWindowsOf(uint wanted)
    {
        var found = new List<IntPtr>();
        EnumWindows(delegate(IntPtr window, IntPtr carried)
        {
            uint owner;
            GetWindowThreadProcessId(window, out owner);
            if (owner == wanted && IsWindowVisible(window) && !IsIconic(window))
                found.Add(window);
            return true;
        }, IntPtr.Zero);
        return found;
    }

    public static string ClassOf(IntPtr window)
    {
        var text = new StringBuilder(256);
        GetClassNameW(window, text, text.Capacity);
        return text.ToString();
    }

    public static string TitleOf(IntPtr window)
    {
        var text = new StringBuilder(512);
        GetWindowTextW(window, text, text.Capacity);
        return text.ToString();
    }
}
"@

function Fail([string] $why)
{
    Write-Host $why -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------- the process

$started = $null

if ($ProcessId -ne 0)
{
    try { $process = Get-Process -Id $ProcessId }
    catch { Fail "there is no process $ProcessId" }
}
elseif ($Program -ne "")
{
    if (-not (Test-Path $Program)) { Fail "no such program: $Program" }

    if ($Arguments.Count -gt 0)
    {
        # Start-Process joins the list with spaces and quotes nothing, so an
        # argument with a space in it arrives at the program as several. Quoted
        # here rather than at every call site, because a caller that has to
        # know this is a caller that will one day forget.
        $quoted = $Arguments | ForEach-Object {
            if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
        }
        $process = Start-Process $Program -ArgumentList $quoted -PassThru
    }
    else
    {
        $process = Start-Process $Program -PassThru
    }
    $started = $process
}
else
{
    Fail "name a program with -Program, or a running one with -ProcessId"
}

# ---------------------------------------------------------------- the window
#
# Polled rather than slept on: a process exists before its window does, and how
# long that takes is the machine's business rather than something to guess at.

function FindWindow()
{
    $process.Refresh()

    if ($Title -ne "")
    {
        foreach ($window in [WindowShot]::VisibleWindowsOf($process.Id))
        {
            if ([WindowShot]::TitleOf($window) -like "*$Title*") { return $window }
        }
        return [IntPtr]::Zero
    }

    return $process.MainWindowHandle
}

$deadline = (Get-Date).AddSeconds($Settle)
$handle = [IntPtr]::Zero

while ((Get-Date) -lt $deadline)
{
    if ($process.HasExited) { Fail "the program exited before a window appeared" }
    $handle = FindWindow
    if ($handle -ne [IntPtr]::Zero) { break }
    Start-Sleep -Milliseconds 200
}

if ($handle -eq [IntPtr]::Zero)
{
    if ($started -ne $null) { $started.Kill() }
    Fail "no window appeared within $Settle seconds"
}

# A toolbar renders its buttons lazily and a capture taken the instant the
# window exists catches half of them. This is the beat that costs nothing and
# has already been the difference once.
Start-Sleep -Milliseconds 700

if ($List)
{
    foreach ($window in [WindowShot]::VisibleWindowsOf($process.Id))
    {
        $r = New-Object WindowShot+RECT
        [void][WindowShot]::GetWindowRect($window, [ref]$r)
        $size = "$($r.Right - $r.Left)x$($r.Bottom - $r.Top)"
        $mark = ""
        if ($window -eq $handle)
        {
            $mark = "  <- capturing this one"
        }
        elseif ([WindowShot]::BelongsTo($window, $handle))
        {
            $mark = "  <- and this one, with -Popups"
        }
        Write-Host ("0x{0:X}  {1,-20} {2,-12} {3}{4}" -f
                    [int64]$window, [WindowShot]::ClassOf($window), $size,
                    [WindowShot]::TitleOf($window), $mark)
    }
    if (-not $Keep -and $started -ne $null) { $started.Kill() }
    exit 0
}

# ---------------------------------------------------------------- the picture

function RectOf([IntPtr] $window)
{
    $r = New-Object WindowShot+RECT
    if (-not [WindowShot]::GetWindowRect($window, [ref]$r)) { return $null }
    return $r
}

function Capture([string] $path)
{
    $main = RectOf $handle
    if ($main -eq $null) { Fail "the window would not say where it is" }

    # Every window that goes in the picture, and the rectangle they cover
    # between them. A popup sits outside the main window as often as not -- a
    # menu near the right edge opens past it -- so the canvas is the union
    # rather than the main window's own size.
    $windows = @($handle)
    $left = $main.Left; $top = $main.Top
    $right = $main.Right; $bottom = $main.Bottom

    if ($Popups)
    {
        foreach ($other in [WindowShot]::VisibleWindowsOf($process.Id))
        {
            if ($other -eq $handle) { continue }

            # Owned by the window, not merely in the same process: a GUI
            # program launched from a console shares its process with that
            # console, and "every window of this process" put a terminal in
            # the picture.
            if (-not [WindowShot]::BelongsTo($other, $handle)) { continue }

            $r = RectOf $other
            if ($r -eq $null) { continue }
            if (($r.Right - $r.Left) -le 0 -or ($r.Bottom - $r.Top) -le 0) { continue }

            $windows += $other
            if ($r.Left   -lt $left)   { $left = $r.Left }
            if ($r.Top    -lt $top)    { $top = $r.Top }
            if ($r.Right  -gt $right)  { $right = $r.Right }
            if ($r.Bottom -gt $bottom) { $bottom = $r.Bottom }
        }
    }

    $width = $right - $left
    $height = $bottom - $top
    if ($width -le 0 -or $height -le 0) { Fail "the window has no size" }

    $canvas = New-Object System.Drawing.Bitmap $width, $height
    $surface = [System.Drawing.Graphics]::FromImage($canvas)
    $surface.Clear([System.Drawing.Color]::Transparent)

    foreach ($window in $windows)
    {
        $r = RectOf $window
        if ($r -eq $null) { continue }

        $w = $r.Right - $r.Left
        $h = $r.Bottom - $r.Top
        if ($w -le 0 -or $h -le 0) { continue }

        # Each window draws into a bitmap of its own and is then placed on the
        # canvas, because PrintWindow always draws at the origin of the device
        # context it is given and has no idea where the window sits.
        $one = New-Object System.Drawing.Bitmap $w, $h
        $into = [System.Drawing.Graphics]::FromImage($one)
        $dc = $into.GetHdc()
        $drew = [WindowShot]::PrintWindow($window, $dc, [WindowShot]::RenderFullContent)
        $into.ReleaseHdc($dc)
        $into.Dispose()

        if ($drew)
        {
            $surface.DrawImage($one, ($r.Left - $left), ($r.Top - $top), $w, $h)
        }
        else
        {
            Write-Host "  (0x{0:X} declined to draw itself)" -f [int64]$window
        }
        $one.Dispose()
    }

    $surface.Dispose()

    $folder = Split-Path -Parent $path
    if ($folder -ne "" -and -not (Test-Path $folder))
    {
        New-Item -ItemType Directory -Force $folder | Out-Null
    }

    $canvas.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $canvas.Dispose()
    Write-Host "wrote $path  (${width}x${height}, $($windows.Count) window(s))"
}

for ($i = 1; $i -le $Shots; $i++)
{
    $path = $Out
    if ($Shots -gt 1)
    {
        $stem = [System.IO.Path]::ChangeExtension($Out, $null).TrimEnd('.')
        $extension = [System.IO.Path]::GetExtension($Out)
        $path = "$stem-$i$extension"
    }

    Capture $path
    if ($i -lt $Shots) { Start-Sleep -Milliseconds $Every }
}

# ---------------------------------------------------------------- tidying up

if (-not $Keep -and $started -ne $null)
{
    # Killed rather than asked to close: the IDE asks about unsaved tabs on the
    # way out and would sit on the prompt for ever. A program left running
    # holds its own binary open, and the next build then fails to link with
    # "permission denied" -- which the compiler reports as a bug in itself.
    $started.Kill()
    $started.WaitForExit(5000) | Out-Null
}
