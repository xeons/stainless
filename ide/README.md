# An IDE for Stainless, written in Stainless

> **An extreme rough draft**, like everything else here — and younger than most
> of it. What works is a docked window in the Visual Studio arrangement, an
> editor with real syntax highlighting, a project tree, a build that runs the
> compiler, and an error line that takes you to the line it names.

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

## What does not exist yet

Named honestly, since the point of the page is to say where the edges are.

- **No completion, no go-to-definition, no hover types, no live errors.** What
  an editor can know from one line is what it knows; everything else needs the
  binder, and the binder is in the compiler. The plan is a `stainless serve`
  mode speaking JSON, with the lexer staying as the fast path and the fallback.
  `--diagnostics json` is the first stone of it and already carries what a
  squiggle needs — a code, a place, and a length to underline — which is why
  the editor does not have to guess at any of that any more.
- **No debugger.** The compiler already emits DWARF and CodeView under `-g`, so
  the intended shape is gdb and lldb driven over the MI2 protocol rather than a
  second debugger written here.
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
- **The build's output arrives all at once**, at the end. The build itself no
  longer blocks the window — it runs on `Background.Run`, which is the thread
  and the queue `Forms` has had for this all along — but `Process.Run` captures
  both streams and answers when the child exits, so there is nothing to report
  from as it goes. A build that streams wants a `Standard.Process` handing back
  its pipes as they fill, which is a change below the IDE rather than in it.

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
ide/src/Main.sl             the command line
ide/tests/lextest.sl        the scanner, on lines that are awkward on purpose
ide/tests/buildtest.sl      the diagnostic reader, on real compiler output
ide/tests/projecttest.sl    the project reader, on files that are awkward
ide/tests/docktest.sl       the layout model, on files a newer build wrote
ide/tests/fixture/          a two-file project, which is the smallest thing
                            that fails if Build ever compiles one file again
```

**Four of those are modules rather than parts of the window**, and the reason is
the same each time: `Ide.Project`, `Ide.Build` and `Ide.Shell`'s `Layout.sl`
mention no control, so a console harness can test them without linking a widget
set or opening a display. `BuildMessage` was a struct at the bottom of
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

**A clipboard.** `Forms.Clipboard` — `GetText`, `SetText`, `HasText` — over a
new seam on the widgetset: `CF_UNICODETEXT` through `GlobalAlloc` on Win32,
`gtk_clipboard_*` on GTK. Text only so far; a clipboard carries any number of
formats at once and negotiating between them is a design rather than a method.

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
