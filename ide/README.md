# An IDE for Stainless, written in Stainless

> **An extreme rough draft**, like everything else here — and younger than most
> of it. What works is a docked window in the Visual Studio arrangement, an
> editor with real syntax highlighting, a project tree, a build that runs the
> compiler, and an error line that takes you to the line it names.

It editing its own source, on each backend, is in
[the root README](../README.md#what-it-is-far-enough-along-to-build) —
[Windows](../docs/images/ide-windows.png) and
[Linux](../docs/images/ide-linux.png).

```
dotnet build Stainless.slnx      # the compiler, which the IDE drives
stainless build --project ide    # the IDE, on either system
```

**The same line on both**, which it was not until
[ide/stainless.json](stainless.json) existed. What each system needs — the
Win32 bindings and seven libraries here, the GTK bindings and six there — is a
platform section in the project file rather than two command lines in a page
nobody re-reads ([packages.md §2.1](../docs/packages.md#21-what-one-platform-adds)).
What used to be printed here for Linux was four lines of `-l` flags, and it
drifted.

`build.ps1` is still there for what a project file does not cover, which is
running the tests afterwards:

```
.\ide\build.ps1 -Test            # build the IDE and run its tests
.\ide\build.ps1 -Run -Open samples\shapes.sl
```

It is a native binary with no VM, no GC and no web view — the same as anything
else this compiler produces. The window is [forms/](../forms/README.md), the
text is drawn by the program itself, and the whole of it is Stainless. Both
backends render it: the Win32 one from the start, and the GTK one since the
six faults in [forms/README.md](../forms/README.md)'s *What running it found*
were fixed — the IDE is what found every one of them.

---

## What works

- **A real code editor.** Line numbers, the current line, selection by keyboard
  and by drag, a caret the platform blinks, scroll bars, a rule at column 80,
  and a light and a dark theme.
- **Tabs.** Several files open at once, each with its own document and its own
  caret; a tab is marked when its file has been changed. Several paths on the
  command line each get one.
- **Cut, copy and paste**, through the real system clipboard, shared with every
  other program on the desktop.
- **Text size**, from the View menu or with Ctrl and the mouse wheel, applying
  to every tab at once because it is a property of how you read rather than of
  which file you are looking at.
- **Syntax highlighting**, from a Stainless lexer written in Stainless — a line
  at a time, so editing line 400 of a 4000-line file lexes one line.
- **Movement and editing** that behave the way they should: word movement with
  Ctrl, `Home` alternating between the first non-blank and column zero, a
  remembered column across vertical movement, and Tab indenting a selection
  rather than replacing it.
- **Double-click selects a word**, or a run of spaces, or a run of punctuation —
  three runs rather than two, so `//` and `=>` come out whole.
- **Build and run**, which builds the *project* when there is one, on a thread
  that is not the one drawing the window. Double-click a diagnostic and the
  caret goes to it — which is newer than it looks, because `Control.DoubleClick`
  was declared in `forms/` and raised by nothing until this was chased down, so
  the click had never worked on any pane. The diagnostic is read from the
  compiler's own JSON
  (`--diagnostics json`) rather than parsed back out of the message meant for a
  person, which is what it used to be.
- **Undo and redo**, with Ctrl+Z and Ctrl+Y. Typing a word is one undo rather
  than seven: consecutive insertions merge while the caret keeps moving
  forward, and a newline, a click or a paste each start a new one. Undoing back
  to the last save clears the asterisk, because the file on disk is what is in
  front of you again — which a latched "modified" flag cannot say.
- **Open, save, save-as**, with the file's own line endings kept.
- **Find and replace**, in a modeless window so the text stays reachable while
  it is open — Find Next, Replace, Replace All, and Match case. It searches
  whichever tab is in front *at the moment a button is pressed* rather than the
  one that was in front when it opened, and it is kept rather than rebuilt, so
  the last search survives closing it.
- **Closing a tab asks**, with Save, Discard and Cancel — three answers, because
  Cancel is the one people reach for when they hit close by mistake and is the
  one a two-button prompt cannot say. Closing the window asks about every edited
  tab in turn.
- **A project build saves every edited tab**, not only the one in front, because
  the compiler reads the directories the project names and an unsaved change in
  another tab is one it will not see.
- **Docked tool windows**, in the Visual Studio arrangement: a Solution
  Explorer down the left, an Error List and an Output pane tabbed together
  along the bottom, and the editors in the middle. Splitters size the wells,
  the close box hides a pane and the pin auto-hides it to a labelled strip on
  its edge that slides back out on hover. Where everything is — which edge,
  pinned or not, how wide — is remembered between runs.
- **Project properties**, a tabbed window over `stainless.json` — General,
  Build, References and Paths, grouped as [docs/packages.md](../docs/packages.md)
  describes the format rather than by what fits on a page. Modal, and nothing
  reaches the project until OK; the file is re-read afterwards, because the
  writer emits only what differs from a default and the model the window goes on
  using should be what a fresh start would get.
- **A Solution Explorer** over the project: its `sources` roots walked on disk,
  a References node listing dependencies and linker libraries, and a
  double-click that opens a file. It shows what the *build* will see rather
  than a file list kept in step by hand, because a Stainless project names
  directories rather than files.
- **An Error List**, one row per diagnostic with severity, code, message, file
  and line, beside the raw Output. Double-clicking either goes to the same
  place, through one model rather than two.
- **A context menu in the Solution Explorer** — Open, Add new file, Rename,
  Delete, Reveal in Explorer and Refresh — acting on the node under the
  *pointer* rather than the one that happened to be selected, since neither
  Windows nor GTK moves the selection on a right-click. A new file is seeded
  with the module its neighbours declare, because a directory here is a module
  and a file that said nothing would fail to compile for a reason that has
  nothing to do with what was being written.

  There is no *Remove from project*, and that is the format rather than an
  omission: a project names directories and the compiler compiles what is in
  them, so there is no list a file can be taken out of. Delete is the honest
  name for the only thing that works, and it asks.
- **Output arrives as the compiler writes it**, a line at a time, rather than
  in one piece when the build ends. Lines are reassembled before they are
  shown: what a pipe hands over is a count of bytes and not of lines, so a
  diagnostic routinely arrives in halves and showing each piece as it came
  would leave the Error List holding half a JSON object.
- **A toolbar** — Build, Rebuild, Clean, Run, Stop — and a **configuration
  picker**. Debug builds `-g -O0` and Release `--no-debug -O2`, passed as flags
  rather than written into `stainless.json`: the compiler takes a flag in
  preference to the project's own `optimize` and `debug`, which is what makes
  the choice possible without rewriting the file every time it changes. Stop is
  pressable only while something is running, and kills rather than asks — a
  compiler halfway through an object file has nothing to tidy that Clean will
  not do better.

- **A debugger.** F9 sets a breakpoint, F5 starts, F10 and F11 step, Shift+F5
  stops. The margin draws a disc beside each breakpoint and an arrow beside the
  line the program is stopped on; Locals, Watch, Call Stack, Breakpoints and
  Debug Output are five more panes in the bottom well.

  **A breakpoint that binds elsewhere says so.** A line with no code on it --
  a blank, a comment, a brace -- resolves to the first statement at or after
  it, and the glyph moves to the line chosen. The Breakpoints pane reads
  `fixture.sl, line 40 (asked for 39)`.

  **Breakpoints are a file and a line, so they outlive the process.** They
  survive Stop, Restart and a rebuild that moved everything, and they can be
  set before anything has been compiled.

  **A hover says what a local is worth.** Point at one while the program is
  stopped and its value is on the status line. It is answered out of the stop
  the window is already holding — the thread that may read a debuggee is the
  session's, and it is busy — so it costs nothing and cannot be asked for
  anything the Locals pane does not have.

  **Watch takes `a`, `a.b.c`, `a[3]`, `a[i]`, `*p` and a number**, and nothing
  else: no arithmetic, no casts, and never a call into the program being
  debugged. Add one from the Debug menu or the pane's own menu; double-click a
  row to correct it. A watch outlives the session the way a breakpoint does,
  and one that is out of scope keeps its row and says so rather than
  disappearing and coming back as the program steps.

  The expression is turned down where it was typed rather than at the next
  stop, because parsing one needs no process -- which is also what lets
  `sldb --selftest` cover the grammar with no binary at all.

  **A breakpoint may carry a condition**, which is one comparison: `i == 7`,
  `total > 100`, `node.Next != 0`. Set it from the Debug menu or the
  Breakpoints pane's own menu; the pane shows it beside the line. It is read
  when the breakpoint is planted, so a condition changed mid-session takes
  effect next time you start, and the window says so. A condition that cannot
  be read where it fires stops anyway and says why -- losing a stop is worse
  than an extra one.

  The engine is `debug/`, which has no idea a window exists -- see
  [debug/README.md](../debug/README.md). What crosses between it and this
  window is a `Snapshot`: numbers and text, read while the program was stopped.
  The window never calls into the engine, because every call into a debuggee
  must come from the one thread that launched it.

  **Debug builds pass `--debug-format dwarf`.** The engine reads DWARF, and an
  ordinary `-g` build on Windows writes CodeView into a `.pdb`. The cost is
  that `.pdb`, so Visual Studio, WinDbg, minidumps and Windows Error Reporting
  see an unsymbolised binary; build Release when that matters.

- **Form files.** A `.slfm` describes a form's controls, their properties
  and their handlers, and `slforms` generates the half of the form's class
  that builds them — [docs/slfm.md](../docs/slfm.md) is the format. The reader
  keeps comments and order, so the designer and a text editor can take turns
  on one file.
- **A form designer.** Opening a `.slfm` shows the form: its real controls,
  made by the program as they will be at run time, under a transparent
  overlay that takes the pointer. Click to select, drag to move, drag a handle
  to resize, all snapped to an 8-pixel grid; the arrows nudge a pixel, Shift
  and the arrows resize, Delete removes, Escape selects the container. F12
  switches to the file's text and back.

  **Lazarus's arrangement.** The controls are in design mode
  (`WindowedControl.IsDesigning`, its `csDesigning`) so they never turn hot or
  pressed, and after one paints the overlay draws the handles again — which
  is `TDesigner.PaintControl` and the redraw after it.

  **The text is the document.** Every change is written back into the tab's
  text as an edit, so saving, the edited mark and undo are the editor's own;
  switching from the text to the designer reads it again, so a hand edit is
  what the designer shows. Saving a form, and every build, writes its
  generated `.designer.sl`.

## What does not exist yet

Named honestly, since the point of the page is to say where the edges are.

- **No completion, no go-to-definition, no hover types, no live errors.** What
  an editor can know from one line is what it knows; everything else needs the
  binder, and the binder is in the compiler. The plan is a `stainless serve`
  mode speaking JSON, with the lexer staying as the fast path and the fallback.
  `--diagnostics json` is the first stone of it and already carries what a
  squiggle needs — a code, a place, and a length to underline — which is why
  the editor does not have to guess at any of that any more.
- **A hover reads the status line, not a tooltip.** Pointing at a local while
  the program is stopped shows its value in the status bar's last panel.
  `forms/` has no tooltip control, and one is a control on two backends rather
  than a debugger feature. It answers a local and nothing else: a field or an
  element is an expression, and the pointer has not selected one — put it in
  Watch.
- **The debugger needs a project.** A loose file is compiled to a path the
  compiler chooses and this window never learns, so F5 asks for a project to be
  opened first.
- **Nothing shows another frame's variables.** Double-clicking a call-stack row
  goes to its line; Locals still shows the frame the program is in. Reading
  another frame's locals needs its frame base, which only the session's own
  thread may ask for.
- **A frame in a shared library is a guess.** The call stack is walked from the
  program's own unwind information, which covers the program and not `libc` or
  `kernel32`; above those the frame pointer is what there is, and a frame
  recovered that way is marked in `sldb unwind` and not in the pane.
- **No Threads pane.** The target seam does not enumerate threads, and a
  Stainless program has one unless it starts more.
- **The function keys need an editor to have the focus.** `forms/` has no menu
  shortcuts, so F5 and F9 are handled by the editor and passed up. The Debug
  menu works from anywhere.
- **A divider drags, imprecisely, and shows no cursor.** The well does not
  land where the pointer is, and the pointer does not change shape over a
  divider to say it can be dragged. Both are in `forms/`, where a splitter
  is a windowless control on a panel -- see *What running it found* there.
- **Panes do not float and cannot be dragged between edges.** A pane's edge is
  read from the layout file and honoured, so hand-editing
  `%APPDATA%/Stainless/ide/layout.json` moves one today — but there is no drag,
  and nothing floats into a window of its own. Both need a drag with a
  dock-target preview and one of them needs a second top-level window; neither
  is what separates an editor from an IDE. *Reset layout* on the View menu says
  it takes effect next time, and that is honest rather than lazy: a control
  belongs to the parent it was constructed with and `forms/` cannot move it, so
  putting a pane back on an edge it was not built on is the one thing that
  cannot happen live.
- **The designer has no Toolbox and no Properties grid.** A control is added
  by writing it in the text; the designer shows, moves, sizes and deletes it.
  What it shows of a control is `Text`, `Bounds`, `Width`, `Height`, `Dock`
  and `Enabled`; anything else is kept in the file and not previewed, until a
  grid reads properties through reflection. There is one selection, not
  several, and no rubber band.
- **Overlapping controls stack differently on the two backends.** A control
  made later is in front on GTK and behind on Win32, where a new child window
  goes to the bottom — and where the Tab order comes from that same order, so
  it cannot simply be flipped. The designer shows what each platform does.
- **No Properties *pane*.** Project properties are a dialog, which is the right
  shape for editing a file; a docked property grid over a selected control is a
  designer feature and waits for one. The name is reserved in the layout file
  and the right-hand well is built and empty until then.
- **`sources`, `defines` and `libraries` are edited as one space-separated
  line each.** Short lists of short words, where a text field shows the whole of
  it at once and three buttons round a list box does not — but a path with a
  space in it cannot be written that way, and nothing quotes yet.
- **Dependencies are shown, not edited.** A dependency is a name, a source, a
  version requirement and a link mode; editing one properly is its own dialog,
  and a half-editor that dropped the fields it did not show would be worse than
  a list.

- **Undo does not reach across files.** Each document has its own stack, which
  is right, and there is no single "undo the last thing I did anywhere".
- **No keyboard shortcut for text size.** `+` and `-` are OEM virtual keys and
  `Forms`' `Key` enum does not name them yet, so it is the menu or Ctrl and the
  wheel. Cut, copy and paste do have their usual keys.
- **A configuration is Debug or Release and nothing else.** `stainless.json`
  holds one `optimize` and one `debug` and has no notion of a named
  configuration, so a picker offering a third would be offering something the
  format cannot hold. Named configurations are a change to the project format
  first and to this second.

---

## How it is put together

```
ide/stainless.json          what the IDE is made of, on either system
ide/src/Lang/Lexer.sl       Stainless, lexed one line at a time
ide/src/Editor/Document.sl  the text: lines, and what each lexed to
ide/src/Editor/Theme.sl     what each kind of token is drawn in
ide/src/Editor/CodeEditor.sl the control that draws it and edits it
ide/src/Project/Project.sl  stainless.json, read and written
ide/src/Build/Diagnostics.sl what the compiler said, out of its JSON
ide/src/Shell/Layout.sl     which pane is where, and how wide -- no controls
ide/src/Shell/DockHost.sl   the wells, the splitters and the auto-hide strips
ide/src/App/Shell.sl        the window: menu, panes, editors, status
ide/src/App/FindDialog.sl   find and replace, over whichever tab is in front
ide/src/App/ProjectDialog.sl stainless.json, edited in four pages
ide/src/Debug/Breakpoints.sl where to stop, as files and lines -- no controls
ide/src/Debug/Session.sl    the thread that owns the debuggee, and its queue
ide/src/Designer/FormDocument.sl  .slfm, read and written, comments and all
ide/src/Designer/FormGenerator.sl .slfm into the generated .designer.sl
ide/src/Designing/DesignedControls.sl a form file's controls, made for real
ide/src/Designing/DesignSurface.sl    the designer: live controls, and the overlay
ide/slforms/                the generator on its own, for a build with no IDE
ide/src/Main.sl             the command line
ide/tests/lextest.sl        the scanner, on lines that are awkward on purpose
ide/tests/buildtest.sl      the diagnostic reader, on real compiler output
ide/tests/projecttest.sl    the project reader, on files that are awkward
ide/tests/docktest.sl       the layout model, on files a newer build wrote
ide/tests/debugtest.sl      breakpoints: toggling, binding, paths, and edits
ide/tests/formtest.sl       form files: round trips, refusals, edits, output
ide/tests/fixture/          a two-file project, which is the smallest thing
                            that fails if Build ever compiles one file again
```

**Several of those are modules rather than parts of the window**, and the reason is
the same each time: `Ide.Project`, `Ide.Build`, `Ide.Designer`, `Ide.Shell`'s
`Layout.sl` and `Ide.Debugging`'s `Breakpoints.sl` mention no control, so a console harness can
test them without linking a widget set or opening a display. `BuildMessage` was a struct at the bottom of
`Shell.sl` and moving it is what made `buildtest.sl` possible at all.

`Ide.Shell` is deliberately split down that line rather than by subject: a
layout is a list of placements and three sizes, and *that* can be checked
without a screen — it round-trips, a width of 40000 is capped, and a file from a
build with different panes does not take the window down. What cannot be checked
that way is whether any of it appears, which is what the screenshots are for.

Three decisions carry most of it.

**The lexer is not the compiler's.** That one reads a whole file, reports
errors, resolves `#if` and produces tokens a parser can use. An editor wants to
know what colour the bytes on *one* line are, thirty times a second, while the
text is half-written and frequently not valid at all. So this one takes a line
and a state, answers tokens and a state, and treats nothing as an error.

**The document is a list of lines.** The argument for a rope or a gap buffer is
that inserting into the middle of one enormous string is O(n) — and it is, but a
*line* is not enormous. What that buys is that every position in the editor is a
row and a column with no translation anywhere, and each line caches the tokens
it lexed to, so painting never lexes.

**The editor assumes a fixed-width font.** With one, a column is a
multiplication and a click is a division, and painting a screen is one
`DrawString` per token with nothing measured. With a proportional font every one
of those becomes a measurement that has to be redone for every line above the
one being drawn.

### What this needed from Forms

**A clipboard.** `Forms.Clipboard` over a seam on the widget set, of which the
editor uses `GetText`, `SetText` and `HasText`. The same class carries HTML,
pictures, files and a program's own formats, several at once through
`ClipboardData`.

**A way to close a tab.** `TabControl` could add pages and never remove one, so
`RemovePage` is new. The interesting part is that every page after the removed
one is renumbered — a `TabPage` remembers which tab it is behind, and leaving
that stale would have shown up much later as renaming the wrong tab.

`CustomControl` — a control that draws every pixel of itself and takes the
keyboard — did not exist and now does, in
[forms/src/Controls/Containers.sl](../forms/src/Controls/Containers.sl). A
`PaintBox` draws but has no window, so nothing can give it the focus and no
keystroke reaches it; a `Panel` has a window and gives up the focus on purpose.
The new control has a registered window class on Win32 and a windowed
`GtkFixed` on GTK, answers `WM_GETDLGCODE` so the arrow keys and Tab reach it
rather than moving the focus, paints through an off-screen buffer on Windows,
and carries a caret — the system's on Win32, drawn and blinked by the peer on
GTK, since GTK has none of its own.

[samples/forms/drawn.sl](../samples/forms/drawn.sl) is that control on its own,
without the rest of an IDE around it.
