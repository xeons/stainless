# An IDE for Stainless, written in Stainless

> **An extreme rough draft**, like everything else here — and younger than most
> of it. What works is an editor with real syntax highlighting, a build that
> runs the compiler, and an error line that takes you to the line it names.

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
- **Build and run**, which builds the *project* when there is one, on a thread
  that is not the one drawing the window. Double-click a diagnostic and the
  caret goes to it — and the diagnostic is read from the compiler's own JSON
  (`--diagnostics json`) rather than parsed back out of the message meant for a
  person, which is what it used to be.
- **Undo and redo**, with Ctrl+Z and Ctrl+Y. Typing a word is one undo rather
  than seven: consecutive insertions merge while the caret keeps moving
  forward, and a newline, a click or a paste each start a new one. Undoing back
  to the last save clears the asterisk, because the file on disk is what is in
  front of you again — which a latched "modified" flag cannot say.
- **Open, save, save-as**, with the file's own line endings kept.

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
- **No project tree.** The project itself is read now — `stainless.json`, the
  same file the compiler reads, found by walking up from whatever file was
  opened — and Build builds *it* rather than the file in front, which is what
  makes a program of two files buildable from here at all. What is missing is
  somewhere to show it: a file is still reached through Open rather than
  browsed to. A diagnostic in a file that is not open does open it, which is
  what tabs made possible.
- **Undo does not reach across files.** Each document has its own stack, which
  is right, and there is no single "undo the last thing I did anywhere".
- **No keyboard shortcut for text size.** `+` and `-` are OEM virtual keys and
  `Forms`' `Key` enum does not name them yet, so it is the menu or Ctrl and the
  wheel. Cut, copy and paste do have their usual keys.
- **Closing a tab does not ask.** Unsaved work goes without a prompt, which
  wants a dialog and a decision about what "discard" means.
- **The build's output arrives all at once**, at the end. The build itself no
  longer blocks the window — it runs on `Background.Run`, which is the thread
  and the queue `Forms` has had for this all along — but `Process.Run` captures
  both streams and answers when the child exits, so there is nothing to report
  from as it goes. A build that streams wants a `Standard.Process` handing back
  its pipes as they fill, which is a change below the IDE rather than in it.
- **A project build saves only the file in front.** It should save every edited
  tab, and that wants a decision about tabs that have never had a name.

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
ide/src/App/Shell.sl        the window: menu, editor, output, status
ide/src/Main.sl             the command line
ide/tests/lextest.sl        the scanner, on lines that are awkward on purpose
ide/tests/buildtest.sl      the diagnostic reader, on real compiler output
ide/tests/projecttest.sl    the project reader, on files that are awkward
ide/tests/fixture/          a two-file project, which is the smallest thing
                            that fails if Build ever compiles one file again
```

**Three of those are modules rather than parts of the window**, and the reason
is the same each time: `Ide.Project` and `Ide.Build` mention no control, so a
console harness can test them without linking a widget set or opening a
display. `BuildMessage` was a struct at the bottom of `Shell.sl` and moving it
is what made `buildtest.sl` possible at all.

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
