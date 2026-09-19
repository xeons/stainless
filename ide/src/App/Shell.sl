// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

// The window: tabbed editors, an output pane, a menu and a status bar.
//
// **What is here and what is not.** Several files open at once, a build that
// runs the compiler and shows what it said, and an error line that takes you to
// the line it names -- in whichever tab holds that file, opening it if none
// does. There is no project tree yet and no debugger; each is a pane and a
// model beside the ones that are here rather than a change to them, which is
// why this is laid out as docked panes from the start.
module Ide.App;

import Standard.Console;
import Standard.Text;
import Standard.Collections;
import Standard.IO;
import Standard.File;
import Standard.Json;
import Standard.Process;
import Standard.Path;
import Standard.Directory;
import Standard.Env;
import Standard.Threading;
import Forms;
import Forms.Drawing;
import Forms.Platform;
import Ide.Lang;
import Ide.Editor;
import Ide.Project;
import Ide.Build;
import Ide.Shell;

/// One open file: the tab it is behind, and the editor on it.
///
/// **A class holding two controls, rather than a `CodeEditor` that knows its
/// own tab.** An editor that held its `TabPage` would be an editor that could
/// only exist inside a tab control, and the next pane to want one -- a diff
/// view, a preview -- would have to be handed a fake one.
public class EditorTab
{
    public TabPage Page;
    public CodeEditor Editor;

    public EditorTab(TabPage page, CodeEditor editor)
    {
        Page = page;
        Editor = editor;
    }
}

/// What a node of the Solution Explorer stands for on disk.
///
/// **A class beside the tree rather than a field on `TreeNode`**, for the
/// reason the two parallel lists this replaces already gave: `TreeNode` carries
/// no tag, and adding one would put a field on every node of every tree in
/// `forms/` for the sake of this one window.
///
/// Two parallel lists became three the moment the context menu had to tell a
/// directory from a file, which is where parallel arrays stop being the
/// cheaper answer and start being three things that can fall out of step.
public class TreeEntry
{
    public TreeNode Node;
    public String FullPath;

    /// Whether `FullPath` names a directory. A file opens, renames and
    /// deletes; a directory is where a new file is added.
    public bool IsFolder;

    public TreeEntry(TreeNode node, String path, bool folder)
    {
        Node = node;
        FullPath = path;
        IsFolder = folder;
    }
}

/// What a build is made for: something to step through, or something to ship.
///
/// **Two, not a list read from the project.** `stainless.json` has no notion of
/// a named configuration -- it has an `optimize` and a `debug`, one of each --
/// so a picker offering more than two would be offering something the format
/// cannot hold. These are the two shapes anyone actually wants, and each is
/// spelled as the flags it means rather than stored anywhere.
public enum Configuration { Debug, Release }

/// The main window.
public class Shell : Form
{
    TabControl _book;
    List<EditorTab> _open;

    /// The wells, the splitters and the strips. Everything but the menu and the
    /// status bar lives inside it.
    DockHost _dock;
    /// Where the panes are and how wide, read at startup and written at exit.
    DockLayout _arrangement;

    ListBox _output;
    ListView _errors;
    TreeView _tree;
    StatusBar _status;
    MainMenu _bar;

    MenuItem _themeItem;

    /// The find window, made the first time it is asked for and kept after
    /// that -- so the last search and the Match case tick survive closing it.
    /// Null until then: a window nobody has asked for should not be built.
    FindDialog? _finder;

    /// The size every editor's text is, kept here rather than on an editor
    /// because it is a preference of the program's and not of one file's.
    int _textSize;
    bool _dark;

    /// Where the compiler is. Found once at startup.
    String _compiler;

    /// What the last build reported, one entry per line of its output.
    List<BuildMessage> _messages;

    /// For each row of the Error List, which `_messages` entry it came from.
    ///
    /// A parallel list rather than a second copy of the diagnostic, because the
    /// two lists show the same build: Output has a row per *line* and the Error
    /// List a row per *diagnostic*, so the indices differ and one of them has to
    /// carry the mapping. Keeping the diagnostic in one place is what stops the
    /// two from ever disagreeing about where a double-click goes.
    List<nuint> _errorLines;

    /// What every node of the tree stands for on disk, so that a double-click
    /// knows what to open and the context menu knows what it was opened on.
    List<TreeEntry> _treeItems;

    /// What the Solution Explorer's context menu was opened on, held only for
    /// as long as the menu is up.
    ///
    /// **`SelectedNode` is not an answer to that question.** A menu item's
    /// handler is given the item and nothing else, and a right-click on no node
    /// at all leaves the previous selection exactly where it was -- so a
    /// handler reading the selection would act on a row the menu was never
    /// about. Both backends raise the item before `Show` returns, so this lives
    /// for the length of one call and is cleared after it.
    TreeEntry? _menuTarget;

    /// The project in front, and the file it was read from. Null when the
    /// window is showing loose files, which is still a thing it does: a
    /// scratch `.sl` with a `Main` is a program, and asking for a project
    /// before one can be compiled would be a worse editor than this was.
    ProjectFile? _project;
    String _projectPath;

    /// Whether a build is running. One at a time, and the menu says so rather
    /// than queueing: two compilers writing the same object directory is the
    /// failure that looks like a scatter of unrelated errors.
    bool _building;

    /// The part of each of the compiler's streams that has arrived without the
    /// newline that would end it.
    ///
    /// **A pump hands over bytes, not lines.** What has arrived when it
    /// answers is however much had been written, which routinely ends halfway
    /// through a line -- so showing each piece as it came would split a
    /// diagnostic in two and leave the Error List holding half a JSON object.
    /// The whole lines are shown and the remainder waits here for the rest of
    /// itself, which never arrives for the last one: the end of the build
    /// flushes whatever is left.
    String _errorTail;
    String _outputTail;

    /// The strip across the top: the commands, and what they build for.
    CoolBar _strip;
    ToolBar _tools;
    ComboBox _configuration;
    ToolButton _stopButton;

    /// The compiler, while it is running, so that Cancel has something to
    /// stop.
    ///
    /// **Written on the UI thread and read there**, though the worker is what
    /// creates it: the worker posts it across rather than assigning, so the
    /// only thread that ever touches this field is the one Cancel runs on.
    /// What genuinely does cross threads is the call into `Kill`, and that is
    /// safe for the reason it is useful -- the worker is blocked in `Read`,
    /// killing the child closes its pipes, and the read it was blocked in
    /// comes back empty and ends the loop.
    Running? _child;

    public Shell()
    {
        base(WindowBorder.Sizable);
        Text = "Stainless";
        SetBounds(0, 0, 1000, 700);

        _open = new List<EditorTab>();
        _messages = new List<BuildMessage>();
        _errorLines = new List<nuint>();
        _treeItems = new List<TreeEntry>();
        _menuTarget = null;
        _project = null;
        _projectPath = "";
        _finder = null;
        _building = false;
        _child = null;
        _errorTail = "";
        _outputTail = "";
        _compiler = FindCompiler();
        _textSize = 10;
        _dark = false;

        _status = new StatusBar(this);
        _status.Dock = DockStyle.Bottom;
        // Four, and the third is why. The error count used to be written into
        // the same panel as the message, so "Built." appeared and was replaced
        // by "3 errors" on the same line in the same instant -- which read as
        // the build having said only the second thing.
        _status.AddPanel(420);      // the path
        _status.AddPanel(200);      // what just happened
        _status.AddPanel(110);      // how many errors
        _status.AddPanel(0);        // where the caret is

        // The commands, on a band shared with the configuration picker.
        //
        // **A `CoolBar` rather than a `ToolBar` alone**, because the picker is
        // a `ComboBox` and a toolbar has no way to hold one: a band is a row
        // entry pointing at an ordinary child, which is what puts two
        // different controls on one row. `samples/forms/buttons.sl` is the
        // same arrangement.
        //
        // Made before the dock host so that it takes its bite out of the
        // client area first; the host fills what is left.
        _strip = new CoolBar(this);
        _strip.Dock = DockStyle.Top;

        _configuration = new ComboBox(_strip);
        _configuration.Height = 24;
        _configuration.Add("Debug");
        _configuration.Add("Release");
        _configuration.SelectedIndex = 0;
        _configuration.SelectedIndexChanged += this.OnConfigurationChanged;

        // **The picker first, and the commands after it.** `CoolBar` draws the
        // last band of a row out to the far edge whatever width it asked for,
        // which is right for a rebar and wrong for a drop-down: a combo box
        // stretched across half the window looks like a mistake. A toolbar
        // does not mind, because its buttons sit at the left and the rest of
        // the band is bar.
        var chosen = new CoolBand(_strip);
        chosen.Text = "Configuration";
        chosen.Control = _configuration;
        chosen.Width = 230;

        _tools = new ToolBar(_strip);
        _tools.Height = 26;
        _tools.Add("Build").Click += this.OnBuild;
        _tools.Add("Rebuild").Click += this.OnRebuild;
        _tools.Add("Clean").Click += this.OnClean;
        _tools.AddSeparator();
        _tools.Add("Run").Click += this.OnRun;
        _stopButton = _tools.Add("Stop");
        _stopButton.Click += this.OnStop;

        // No caption: the buttons already say what they do, and a band reading
        // "Build" beside a button reading "Build" is twice the width for none
        // of the information.
        var commands = new CoolBand(_strip);
        commands.Text = "";
        commands.Break = false;     // share the row with the picker
        commands.Control = _tools;
        commands.Width = 380;

        _strip.Height = _strip.PreferredSize.Height;
        ShowWhatIsRunning();

        // The layout is read before anything is built, because where a pane
        // goes is decided as it is made -- a control's parent is fixed at
        // construction and `forms/` cannot move it afterwards.
        _arrangement = ReadLayout(LayoutPath());
        _dock = new DockHost(this, _arrangement);
        _dock.Dock = DockStyle.Fill;

        var solution = _dock.Add(Panes.Solution, "Solution Explorer", DockEdge.Left);
        _tree = new TreeView(solution);
        _tree.Dock = DockStyle.Fill;
        _tree.DoubleClick += this.OnTreeChosen;
        _tree.MouseUp += this.OnTreeMouse;

        var errors = _dock.Add(Panes.Errors, "Error List", DockEdge.Bottom);
        _errors = new ListView(errors);
        _errors.Dock = DockStyle.Fill;
        _errors.View = ListViewStyle.Details;
        _errors.SetFullRowSelect(true, true);
        // Widths that add up to less than the bottom well starts at, so that
        // every column is visible without scrolling on a first run. Description
        // is the one that gives, because it is also the one the platform lets
        // you widen by dragging when a message is long.
        _errors.AddColumn("", 22);
        _errors.AddColumn("Code", 70);
        _errors.AddColumn("Description", 380);
        _errors.AddColumn("File", 140);
        _errors.AddColumn("Line", 50, HorizontalAlignment.Right);
        _errors.DoubleClick += this.OnErrorChosen;

        var output = _dock.Add(Panes.Output, "Output", DockEdge.Bottom);
        _output = new ListBox(output);
        _output.Dock = DockStyle.Fill;
        _output.DoubleClick += this.OnOutputChosen;

        _book = new TabControl(_dock.Documents);
        _book.Dock = DockStyle.Fill;
        _book.SelectedIndexChanged += this.OnTabChanged;

        // Once, after every pane exists, rather than after each -- see
        // `DockHost.Arrange`.
        _dock.Arrange();

        BuildMenu();
        NewFile();
        ShowProjectTree();
        Say("Ready.");
    }

    // ------------------------------------------------------------- the tabs

    /// The editor of whichever tab is showing, or null when none is.
    public CodeEditor? Current
    {
        get
        {
            int at = _book.SelectedIndex;
            if (at < 0 || (nuint)at >= _open.Count)
                return null;
            return _open[(nuint)at].Editor;
        }
    }

    /// The editor in front, making one if somehow there is none.
    ///
    /// Kept under this name because the command line and the self test both had
    /// it before there were tabs, and both mean "the one being edited".
    public CodeEditor Editor
    {
        get
        {
            var now = Current;
            if (now == null)
                return AddTab(new Document()).Editor;
            return (CodeEditor)now;
        }
    }

    public nuint TabCount => _open.Count;

    /// Brings the first tab to the front and gives it the keyboard.
    ///
    /// For the command line, which opens each file it was given in turn and
    /// would otherwise leave the last one showing -- where a shell expanding
    /// `*.sl` means the first.
    public void ShowFirstTab()
    {
        if (_open.IsEmpty)
            return;
        _book.SelectedIndex = 0;
        _open[0u].Editor.Focus();
    }

    /// Makes a tab, puts an editor on it, and brings it to the front.
    EditorTab AddTab(Document document)
    {
        var page = new TabPage(_book, "");
        var editor = new CodeEditor(page);
        editor.Dock = DockStyle.Fill;
        editor.SetDocument(document);
        editor.FontSize = _textSize;
        editor.Palette = _dark ? Theme.Dark() : Theme.Light();
        editor.CaretMoved += this.OnCaretMoved;
        editor.Edited += this.OnEdited;

        var tab = new EditorTab(page, editor);
        _open.Add(tab);

        _book.SelectedIndex = page.Index;
        Relabel(tab);
        Retitle();
        return tab;
    }

    /// The tab a file is already open in, or null.
    ///
    /// **Compared by the path as it was given.** Two spellings of one file -- a
    /// relative path and an absolute one, or two capitalisations on Windows --
    /// would open it twice. Settling that needs a canonical form from the
    /// platform, which `Standard.Path` does not offer yet.
    EditorTab? TabFor(String path)
    {
        if (path.ByteLength() == 0u)
            return null;
        foreach (var tab in _open)
        {
            if (tab.Editor.Contents.Location == path)
                return tab;
        }
        return null;
    }

    /// Opens a file, or brings its tab forward when it is already open.
    public bool OpenFile(String path)
    {
        var already = TabFor(path);
        if (already != null)
        {
            _book.SelectedIndex = ((EditorTab)already).Page.Index;
            Say(path + " is already open.");
            return true;
        }

        var document = new Document();
        if (!document.Load(path))
            return false;

        // An untouched, unnamed, empty first tab is a placeholder rather than a
        // document, so opening a file replaces it instead of sitting beside it.
        var spare = Current;
        bool replacing = _open.Count == 1u && spare != null && IsBlank((CodeEditor)spare);
        var stale = replacing ? _open[0u] : null;

        var tab = AddTab(document);
        if (stale != null)
            CloseTab((EditorTab)stale);
        tab.Editor.Focus();

        // A file usually arrives with a project above it, and finding it here
        // is what makes Build mean "build this program" without anyone having
        // opened the project by hand.
        AdoptProjectFor(path);

        Say("Opened " + path);
        return true;
    }

    bool IsBlank(CodeEditor editor)
    {
        return editor.Contents.Location.ByteLength() == 0u
            && !editor.Contents.Edited
            && editor.Contents.LineCount == 1u
            && editor.Contents.LengthAt(0u) == 0u;
    }

    void NewFile()
    {
        var tab = AddTab(new Document());
        tab.Editor.Focus();
    }

    /// Shuts a tab, and makes sure one is always left.
    void CloseTab(EditorTab tab)
    {
        _book.RemovePage(tab.Page);
        for (nuint i = 0u; i < _open.Count; i++)
        {
            if (_open[i] == tab)
            {
                _open.RemoveAt(i);
                break;
            }
        }
        // A window with no editor in it has nowhere to type, so closing the
        // last tab opens an empty one rather than leaving a hole.
        if (_open.IsEmpty)
        {
            NewFile();
            return;
        }
        Retitle();
        OnCaretMoved(this);
    }

    /// What a tab says: the file's name, and a mark when it has been changed.
    void Relabel(EditorTab tab)
    {
        tab.Page.Caption = (tab.Editor.Contents.Edited ? "* " : "")
                         + NameOf(tab.Editor.Contents.Location);
    }

    String NameOf(String path)
    {
        if (path.ByteLength() == 0u)
            return "Untitled";
        String name = path.AfterLast(Separator());
        return name.ByteLength() == 0u ? path : name;
    }

    void OnTabChanged(Control sender)
    {
        Retitle();
        var now = Current;
        if (now != null)
        {
            ((CodeEditor)now).Focus();
            OnCaretMoved(this);
        }
    }

    // ------------------------------------------------------------- the menu

    void BuildMenu()
    {
        _bar = new MainMenu();

        var file = _bar.Add("&File");
        file.Add("&New").Click += this.OnNew;
        file.Add("&Open...").Click += this.OnOpen;
        file.Add("Open &project...").Click += this.OnOpenProject;
        file.Add("C&lose project").Click += this.OnCloseProject;
        file.Add("P&roperties...").Click += this.OnProjectProperties;
        file.Add("&Save").Click += this.OnSave;
        file.Add("Save &As...").Click += this.OnSaveAs;
        file.Add(MenuItem.Separator());
        file.Add("&Close tab").Click += this.OnCloseTab;
        file.Add(MenuItem.Separator());
        file.Add("E&xit").Click += this.OnExit;

        var edit = _bar.Add("&Edit");
        edit.Add("&Undo").Click += this.OnUndo;
        edit.Add("&Redo").Click += this.OnRedo;
        edit.Add(MenuItem.Separator());
        edit.Add("Cu&t").Click += this.OnCut;
        edit.Add("&Copy").Click += this.OnCopy;
        edit.Add("&Paste").Click += this.OnPaste;
        edit.Add(MenuItem.Separator());
        edit.Add("Select &all").Click += this.OnSelectAll;
        edit.Add(MenuItem.Separator());
        edit.Add("&Find and replace...").Click += this.OnFind;
        edit.Add("Find &next").Click += this.OnFindNext;

        var build = _bar.Add("&Build");
        build.Add("&Build").Click += this.OnBuild;
        build.Add("Re&build").Click += this.OnRebuild;
        build.Add("&Run").Click += this.OnRun;
        build.Add("&Stop").Click += this.OnStop;
        build.Add(MenuItem.Separator());
        build.Add("&Clean").Click += this.OnClean;
        build.Add(MenuItem.Separator());
        build.Add("&Clear output").Click += this.OnClearOutput;

        var view = _bar.Add("&View");
        // The panes first, which is where Visual Studio puts them and where
        // someone goes after closing one by accident -- a closed pane is hidden
        // rather than destroyed, so this brings back the same tree with the
        // same project already in it.
        view.Add("&Solution Explorer").Click += this.OnShowSolution;
        view.Add("&Error List").Click += this.OnShowErrors;
        view.Add("&Output").Click += this.OnShowOutput;
        view.Add(MenuItem.Separator());
        view.Add("&Reset layout").Click += this.OnResetLayout;
        view.Add(MenuItem.Separator());

        _themeItem = view.Add("&Dark theme");
        _themeItem.Click += this.OnToggleTheme;
        view.Add(MenuItem.Separator());

        var size = view.Add("&Text size");
        size.Add("&Larger").Click += this.OnLarger;
        size.Add("&Smaller").Click += this.OnSmaller;
        size.Add(MenuItem.Separator());
        size.Add("&Reset").Click += this.OnResetSize;

        Menu = _bar;
    }

    // ------------------------------------------------------------- the file

    void OnNew(MenuItem sender)
    {
        NewFile();
        Say("A new file.");
    }

    void OnOpen(MenuItem sender)
    {
        var dialog = new OpenDialog();
        dialog.Title = "Open";
        dialog.AddFilter("Stainless source", "*.sl");
        dialog.AddFilter("Every file", "*");

        var chosen = dialog.Show(this);
        if (!chosen.Ok)
            return;
        if (!OpenFile(chosen.Value))
            Say("Could not read " + chosen.Value);
    }

    void OnSave(MenuItem sender)
    {
        var now = Current;
        if (now != null)
            SaveTo((CodeEditor)now, ((CodeEditor)now).Contents.Location);
    }

    void OnSaveAs(MenuItem sender)
    {
        var now = Current;
        if (now != null)
            SaveTo((CodeEditor)now, "");
    }

    void OnCloseTab(MenuItem sender)
    {
        int at = _book.SelectedIndex;
        if (at < 0 || (nuint)at >= _open.Count)
            return;
        var tab = _open[(nuint)at];
        if (!MayClose(tab))
            return;
        CloseTab(tab);
    }

    /// Offers to save a tab that has been edited. Answers whether closing it
    /// should go ahead.
    ///
    /// **Three answers, not two.** Yes saves and closes, No discards and
    /// closes, and Cancel leaves everything as it was -- which is the one a
    /// two-button prompt cannot express and the one people reach for when they
    /// realise they hit close by mistake. `YesNoCancel` is what every editor
    /// uses here for exactly that reason.
    ///
    /// **A tab that has never been named still asks.** It has no path, so
    /// saying yes opens the Save As dialog, and cancelling *that* has to cancel
    /// the close too -- otherwise declining to choose a filename throws the
    /// work away, which is the same accident the prompt exists to prevent.
    ///
    /// True for a tab with nothing to lose, so the caller never has to ask
    /// whether it was edited first.
    bool MayClose(EditorTab tab)
    {
        if (!tab.Editor.Contents.Edited)
            return true;

        String name = NameOf(tab.Editor.Contents.Location);
        if (name == "")
            name = "this file";

        var answer = Application.ShowMessage(
            "Save the changes to " + name + " before closing it?",
            "Stainless", MessageButtons.YesNoCancel, MessageIcon.Question);

        if (answer == DialogResult.Yes)
            return SaveTo(tab.Editor, tab.Editor.Contents.Location);

        // Anything that is not an explicit Yes or No keeps the tab. A dialog
        // that failed to open answers `None`, and treating that as "discard"
        // would lose work because a window manager was busy.
        return answer == DialogResult.No;
    }

    /// Every edited tab, asked about in turn. False as soon as one is
    /// cancelled, leaving the rest untouched -- which is what cancelling the
    /// whole operation means.
    bool MayCloseAll()
    {
        // Backwards, because saying No to a tab closes it and shortens the
        // list under the loop. Going forwards would skip the tab that slid
        // into the index just visited, which is the classic way to lose one.
        for (nuint i = _open.Count; i > 0u; i--)
        {
            nuint at = i - 1u;
            if (at >= _open.Count)
                continue;
            if (!MayClose(_open[at]))
                return false;
        }
        return true;
    }

    /// Saves an editor to `path`, or asks for one when it is empty. Answers
    /// whether it was written.
    bool SaveTo(CodeEditor editor, String path)
    {
        String target = path;
        if (target.ByteLength() == 0u)
        {
            var dialog = new SaveDialog();
            dialog.Title = "Save as";
            dialog.AddFilter("Stainless source", "*.sl");
            dialog.FileName = editor.Contents.Location;
            var chosen = dialog.Show(this);
            if (!chosen.Ok)
                return false;
            target = chosen.Value;
        }

        if (!editor.Contents.Save(target))
        {
            Say("Could not write " + target);
            return false;
        }
        RelabelFor(editor);
        Retitle();
        Say("Saved " + target);
        return true;
    }

    /// Updates the tab an editor is on, whichever one that is.
    void RelabelFor(CodeEditor editor)
    {
        foreach (var tab in _open)
        {
            if (tab.Editor == editor)
            {
                Relabel(tab);
                return;
            }
        }
    }

    void OnExit(MenuItem sender) => Close();


    // -------------------------------------------------------- the clipboard

    void OnUndo(MenuItem sender)
    {
        var now = Current;
        if (now == null)
            return;
        if (!((CodeEditor)now).Undo())
            Say("Nothing to undo.");
    }

    void OnRedo(MenuItem sender)
    {
        var now = Current;
        if (now == null)
            return;
        if (!((CodeEditor)now).Redo())
            Say("Nothing to redo.");
    }

    void OnCut(MenuItem sender)
    {
        var now = Current;
        if (now != null)
            ((CodeEditor)now).Cut();
    }

    void OnCopy(MenuItem sender)
    {
        var now = Current;
        if (now != null)
            ((CodeEditor)now).Copy();
    }

    void OnPaste(MenuItem sender)
    {
        var now = Current;
        if (now != null)
            ((CodeEditor)now).Paste();
    }

    void OnSelectAll(MenuItem sender)
    {
        var now = Current;
        if (now != null)
            ((CodeEditor)now).SelectAll();
    }

    // ---------------------------------------------------------- the display

    void OnToggleTheme(MenuItem sender)
    {
        _dark = !_themeItem.Checked;
        _themeItem.Checked = _dark;
        var palette = _dark ? Theme.Dark() : Theme.Light();
        foreach (var tab in _open)
            tab.Editor.Palette = palette;
    }

    void OnLarger(MenuItem sender) => Resize(1);
    void OnSmaller(MenuItem sender) => Resize(-1);
    void OnResetSize(MenuItem sender) => Resize(DefaultTextSize - _textSize);

    /// Changes the text size in every tab at once.
    ///
    /// **Every tab, not the one in front.** A size is a property of how this
    /// person reads and not of which file they are looking at, so an editor
    /// that resized one tab would make switching tabs change the size of the
    /// text.
    public void Resize(int by)
    {
        if (by == 0)
            return;
        var now = Current;
        if (now == null)
            return;

        // Asked of an editor rather than worked out here, so the clamping lives
        // in one place: the editor refuses a size out of range, and whatever it
        // ended up with is the answer the rest follow.
        ((CodeEditor)now).ResizeFont(by);
        _textSize = ((CodeEditor)now).FontSize;
        foreach (var tab in _open)
            tab.Editor.FontSize = _textSize;
        Say("Text size " + Standard.Text.FromInteger(_textSize) + ".");
    }

    // --------------------------------------------------------- the compiler

    /// Where `stainless` is: beside this program first, and on the path after.
    String FindCompiler()
    {
        String self = Env.Program();
        long cut = self.LastIndexOf(Separator());
        if (cut > 0)
        {
            String beside = self.Substring(0u, (nuint)cut) + Separator()
                          + "stainless" + Extension;
            if (File.Exists(beside))
                return beside;
        }
        return "stainless";
    }

    /// One line ending, as the compiler writes them on this platform.
    String Newline()
    {
        #if WINDOWS
        return "\r\n";
        #else
        return "\n";
        #endif
    }

    String Separator()
    {
        #if WINDOWS
        return "\\";
        #else
        return "/";
        #endif
    }

    String Extension
    {
        get
        {
            #if WINDOWS
            return ".exe";
            #else
            return "";
            #endif
        }
    }

    void OnBuild(MenuItem sender) => Compile(false);
    void OnBuild(Control sender) => Compile(false);
    void OnRun(MenuItem sender) => Compile(true);
    void OnRun(Control sender) => Compile(true);

    // ------------------------------------------------------------ the project

    /// Opens a project file, or a directory holding one.
    void OnOpenProject(MenuItem sender)
    {
        var dialog = new OpenDialog();
        dialog.Title = "Open project";
        dialog.AddFilter("Stainless projects", "stainless.json");
        dialog.AddFilter("All files", "*");

        var chosen = dialog.Show(this);
        if (!chosen.Ok)
            return;

        OpenProject(chosen.Value);
    }

    void OnCloseProject(MenuItem sender)
    {
        if (_project == null)
        {
            Say("No project is open.");
            return;
        }

        _project = null;
        _projectPath = "";
        Retitle();
        ShowProjectTree();
        Say("Project closed. Building compiles the file in front.");
    }

    /// Reads a project and takes it as the one in front.
    ///
    /// **A failure is shown and does not close what was open.** A project file
    /// being edited is broken for as long as it takes to type the next line,
    /// and an editor that dropped the project on every keystroke's worth of
    /// invalid JSON would be unusable.
    public bool OpenProject(String path)
    {
        var read = Project.Read(path);
        if (!read.Ok)
        {
            Show(read.Error);
            Say("That project could not be read.");
            return false;
        }

        _project = read.Value;
        _projectPath = path;
        Retitle();
        ShowProjectTree();

        var project = (ProjectFile)read.Value;
        Say("Project " + project.Name + " " + project.Version + ".");
        return true;
    }

    /// Looks for a project above a file that has just been opened, and adopts
    /// it when there is one and none is open already.
    ///
    /// Silent either way. Opening a file is not asking a question, and a
    /// message saying no project was found would be noise on every scratch
    /// file -- while a project quietly found is what makes Build do the right
    /// thing without anyone having said so.
    void AdoptProjectFor(String path)
    {
        if (_project != null || path.ByteLength() == 0u)
            return;

        String found = Project.Find(Path.DirectoryName(path));
        if (found == "")
            return;

        var read = Project.Read(found);
        if (!read.Ok)
            return;

        _project = read.Value;
        _projectPath = found;
        Retitle();
        ShowProjectTree();
    }

    /// What the compiler is being asked to do, for the status line.
    String ProjectName()
    {
        if (_project == null)
            return "";
        return ((ProjectFile)_project).Name;
    }

    void OnClearOutput(MenuItem sender)
    {
        ClearOutput();
    }

    /// Saves what needs saving, then runs the compiler off the UI thread.
    ///
    /// **What is built is the project when there is one**, through
    /// `--project`, which is the flag that exists so a build can be asked for
    /// from somewhere other than the project's own directory. Without a
    /// project it is the file in front, which is what this did for every file
    /// before -- and which cannot build a program of two, so the project is
    /// the answer rather than a convenience.
    ///
    /// **The window stays alive while it runs**, which it did not before: the
    /// compiler ran on the UI thread and the window stopped answering for as
    /// long as the build took. `Background.Run` takes a closure that runs off
    /// the thread and one that runs back on it with the answer, which is
    /// exactly this shape.
    ///
    /// **And the output arrives as it is written**, which needed the change to
    /// `Standard.Process` this comment used to ask for: `Open` hands back a
    /// child whose two streams can be read while it is still writing them,
    /// where `Run` answers only once it has exited. A build now says what it
    /// is doing while it does it.
    void Compile(bool thenRun)
    {
        if (_building)
        {
            Say("A build is already running.");
            return;
        }

        if (!SaveBeforeBuilding())
            return;

        ClearOutput();

        var arguments = BuildArguments(thenRun);
        Say(thenRun ? "Running..." : "Building...");
        Start(arguments, thenRun ? "Ran." : "Built.");
    }

    void OnClean(MenuItem sender) => Clean();
    void OnClean(Control sender) => Clean();

    void Clean()
    {
        if (_building)
        {
            Say("A build is already running.");
            return;
        }

        if (_project == null)
        {
            Say("Clean needs a project; there is nothing else to clean.");
            return;
        }

        ClearOutput();
        Say("Cleaning...");

        if (CleanObjects())
            Say("Cleaned.");
    }

    /// Removes the object directory, and answers whether it may be built into
    /// again. False means something was refused and has already been said.
    ///
    /// Split out of `OnClean` so that Rebuild is a clean and then a build
    /// rather than a second copy of the guard -- and the guard is the half
    /// that matters, since what this deletes is a directory tree named by a
    /// file a person edits.
    bool CleanObjects()
    {
        if (_project == null)
            return false;

        // `stainless` has no clean of its own: what a clean removes is the
        // object directory, and the build stamp inside it is what makes the
        // next build do all the work again. Removed here rather than by asking
        // for a flag that does not exist.
        var project = (ProjectFile)_project;
        String rubbish = project.Resolve(project.ObjectDirectory);

        if (!IsInsideProject(project, rubbish))
        {
            Show("refusing to clean '" + rubbish + "', which is outside the project");
            Say("Clean refused.");
            return false;
        }

        if (!Directory.Exists(rubbish))
            return true;

        nuint removed = RemoveTree(rubbish);
        Show("removed " + Standard.Text.FromInteger((long)removed) + " files from " + rubbish);
        return true;
    }

    /// Everything again from nothing: the object directory goes, and then the
    /// whole program is compiled.
    ///
    /// **Not `Clean` followed by `Build` from the menu**, which would clear the
    /// output pane twice and lose what the clean said.
    void OnRebuild(MenuItem sender) => Rebuild();

    void OnRebuild(Control sender) => Rebuild();

    void Rebuild()
    {
        if (_building)
        {
            Say("A build is already running.");
            return;
        }

        if (!SaveBeforeBuilding())
            return;

        ClearOutput();

        if (_project != null && !CleanObjects())
            return;

        Say("Rebuilding...");
        Start(BuildArguments(false), "Rebuilt.");
    }

    /// Stops the build that is running. Nothing to say when none is.
    ///
    /// **Killed rather than asked.** `Stop` is polite on Linux and cannot be
    /// on Windows -- `Process.Stop`'s own comment says so -- and a compiler
    /// halfway through writing an object file has nothing to tidy that a
    /// rebuild will not do better. What this leaves behind is a partial object
    /// directory, which is what Clean is for.
    void OnStop(MenuItem sender) => Stop();
    void OnStop(Control sender) => Stop();

    void Stop()
    {
        var running = _child;
        if (running == null)
        {
            Say("Nothing is building.");
            return;
        }

        ((Running)running).Kill();
        Say("Stopping...");
    }

    /// Whether a path the project named is somewhere this may delete.
    ///
    /// **A clean deletes a directory tree, and the path comes out of a file.**
    /// `objectDirectory` is an ordinary string a project may say anything in,
    /// `".."` included, and a typo there should not cost somebody their source.
    /// So the resolved directory has to sit under the project's own and be
    /// longer than it -- which refuses the project directory itself as well as
    /// anything above it.
    bool IsInsideProject(ProjectFile project, String directory)
    {
        String root = project.Directory;
        if (root == "" || directory == "")
            return false;
        if (directory.ByteLength() <= root.ByteLength())
            return false;
        return directory.StartsWith(root);
    }

    /// Deletes a directory and everything under it, answering how many files
    /// went. Deepest first, since a directory is only removable once empty.
    nuint RemoveTree(String directory)
    {
        nuint removed = 0u;

        var inside = Directory.Directories(directory);
        if (inside.Ok)
        {
            foreach (var child in inside.Value)
                removed = removed + RemoveTree(child);
        }

        var files = Directory.Files(directory);
        if (files.Ok)
        {
            foreach (var file in files.Value)
            {
                if (File.Delete(file) == IOError.None)
                    removed++;
            }
        }

        Directory.Delete(directory);
        return removed;
    }

    /// Everything that needs saving, saved, or false when something could not
    /// be and the build should not start.
    ///
    /// **Every edited tab when a project is open, not only the one in front.**
    /// A project build compiles the directories the project names, so a change
    /// sitting unsaved in another tab is a change the compiler will not see --
    /// and the failure that produces is the worst kind: the build succeeds, or
    /// fails in a file you are not looking at, and the source on screen does not
    /// match what was compiled. Without a project the build is of one file, so
    /// only that one is saved.
    ///
    /// **A tab that has never had a name is where this had to make a decision.**
    /// The file in front gets the Save As dialog, because building it is a
    /// direct instruction about that file. Any *other* unnamed tab is skipped
    /// rather than prompted for: a build is not the moment to be asked to name
    /// three scratch buffers, and an unnamed tab is in no directory the project
    /// names, so the compiler was never going to read it.
    bool SaveBeforeBuilding()
    {
        var now = Current;
        if (now == null)
            return false;
        var editor = (CodeEditor)now;

        String path = editor.Contents.Location;
        if (path.ByteLength() == 0u)
        {
            if (!SaveTo(editor, ""))
                return false;
        }
        else if (editor.Contents.Edited && !editor.Contents.Save(path))
        {
            Say("Could not write " + path);
            return false;
        }
        RelabelFor(editor);

        if (_project != null && !SaveEveryOtherTab(editor))
            return false;

        Retitle();
        return true;
    }

    /// The edited tabs that are not the one in front. False if one refused to
    /// be written, naming it -- a build against a stale file on disk is worse
    /// than no build.
    bool SaveEveryOtherTab(CodeEditor except)
    {
        foreach (var tab in _open)
        {
            var editor = tab.Editor;
            if (editor == except || !editor.Contents.Edited)
                continue;

            String path = editor.Contents.Location;
            if (path.ByteLength() == 0u)
                continue;

            if (!editor.Contents.Save(path))
            {
                Say("Could not write " + path);
                return false;
            }
            Relabel(tab);
        }
        return true;
    }

    /// What the compiler is asked, which is the project when there is one.
    /// Which configuration the picker is showing.
    Configuration Chosen()
    {
        if (_configuration.SelectedIndex == 1)
            return Configuration.Release;
        return Configuration.Debug;
    }

    String[] BuildArguments(bool thenRun)
    {
        var arguments = new List<String>();
        arguments.Add(thenRun ? "run" : "build");

        // JSON, because the alternative is reading a format meant for a person
        // and guessing which part of it was the file name. `BuildMessage` says
        // what that cost.
        arguments.Add("--diagnostics");
        arguments.Add("json");

        // **The picker decides, and the project does not.** `stainless.json`
        // holds one `optimize` and one `debug` and has no notion of a named
        // configuration, so the only way to offer the choice without rewriting
        // the file every time it changes is to pass the flags -- which the
        // compiler takes in preference to the project's own, and which is what
        // that precedence is for. A project saying `optimize: 3` is still
        // built at -O0 in Debug, because that is what choosing Debug means.
        //
        // `--no-debug` exists because of this line: `-g` could only ever turn
        // debug information on, so a Release build of a project whose `debug`
        // is true had no way to say what it meant.
        if (Chosen() == Configuration.Release)
        {
            arguments.Add("--no-debug");
            arguments.Add("-O2");
        }
        else
        {
            arguments.Add("-g");
            arguments.Add("-O0");
        }

        if (_project != null)
        {
            arguments.Add("--project");
            arguments.Add(_projectPath);
            return arguments.ToArray();
        }

        var now = Current;
        if (now != null)
            arguments.Add(((CodeEditor)now).Contents.Location);
        return arguments.ToArray();
    }

    void OnConfigurationChanged(Control sender)
    {
        Say(Chosen() == Configuration.Release
            ? "Release: optimised, and nothing for a debugger."
            : "Debug: unoptimised, and described to a debugger.");
    }

    /// Enables what can be done now and disables what cannot.
    ///
    /// Stop is the one that matters: a Stop that is always pressable is one
    /// that does nothing most of the time, and a toolbar is the place a person
    /// looks to find out whether anything is happening.
    void ShowWhatIsRunning()
    {
        _stopButton.Enabled = _building;
    }

    /// Runs the compiler on a thread and reports back on the UI one, in
    /// pieces, as they arrive.
    ///
    /// **Everything the worker needs is read before it starts.** The closure
    /// captures two strings and an array, and touches no control: a control
    /// read from another thread is the bug this arrangement exists to avoid,
    /// and `Forms` says so where `Background.Run` is declared.
    ///
    /// **A thread of its own rather than `Background.Run`**, which is the only
    /// reason this is not three lines: that posts one answer when the work is
    /// done, and the whole point here is that there are many. `Application.Post`
    /// is what it uses underneath, so this is the same mechanism with the loop
    /// opened up rather than a second way of doing it.
    void Start(String[] arguments, String success)
    {
        _building = true;
        ShowWhatIsRunning();
        String compiler = _compiler;

        var worker = new Thread(() =>
        {
            var opened = Open(compiler, arguments);
            if (opened.Fail)
            {
                Application.Post(() => Failed());
                return;
            }

            var child = opened.Value;

            // Handed across rather than assigned, so that the field Cancel
            // reads is only ever written by the thread Cancel runs on.
            Application.Post(() => Holding(child));

            while (child.Read())
            {
                // Taken here and captured by value, so each post carries its
                // own piece: `Thread`'s doc comment is explicit that a closure
                // holds a copy of what it named, which is what makes a loop
                // that posts from inside itself safe.
                String errors = child.TakeErrors();
                String output = child.TakeOutput();
                Application.Post(() => Arrived(errors, output));
            }

            int code = child.Wait().ValueOr(-1);
            Application.Post(() => Ended(code, success));
        });
        worker.Detach();
    }

    /// The build's child, handed over by the worker that made it.
    void Holding(Running child)
    {
        _child = child;
        ShowWhatIsRunning();
    }

    /// The compiler could not be started at all, back on the UI thread.
    void Failed()
    {
        _building = false;
        _child = null;
        ShowWhatIsRunning();
        Show("could not start '" + _compiler + "' -- is it on the path?");
        Say("The compiler could not be started.");
    }

    /// A piece of each stream, on the UI thread.
    ///
    /// The compiler writes diagnostics to the error stream and the program's
    /// own output to the other, so the two are read differently and shown in
    /// that order -- which is the order they were written in when the build
    /// fails, and near enough when it does not.
    void Arrived(String errors, String output)
    {
        _errorTail = ShowComplete(_errorTail + errors, true);
        _outputTail = ShowComplete(_outputTail + output, false);
    }

    /// Shows every whole line in `text`, and answers the part after the last
    /// newline -- which is not a whole line yet, and waits for the rest.
    String ShowComplete(String text, bool diagnostics)
    {
        if (text.ByteLength() == 0u)
            return "";

        String tidy = text.Replace("\r\n", "\n");
        long cut = tidy.LastIndexOf("\n");
        if (cut < 0)
            return tidy;

        foreach (var line in tidy.Substring(0u, (nuint)cut).Split("\n"))
        {
            if (diagnostics)
                Show(line);
            else
                ShowRaw(line);
        }
        return tidy.Substring((nuint)cut + 1u);
    }

    /// The child has exited and every byte of it has been handed over.
    void Ended(int code, String success)
    {
        _building = false;
        _child = null;
        ShowWhatIsRunning();

        // Whatever came without a newline after it is still a line, and this
        // is the last chance to say so: a compiler that does not end its
        // output with one would otherwise have its final diagnostic dropped.
        if (_errorTail.ByteLength() != 0u)
            Show(_errorTail);
        if (_outputTail.ByteLength() != 0u)
            ShowRaw(_outputTail);
        _errorTail = "";
        _outputTail = "";

        Say(code == 0
            ? success
            : "Failed, with " + Standard.Text.FromInteger(code) + ".");
        _status.SetPanelText(2, CountErrors());
    }

    /// Every line of one of the compiler's two streams.
    ///
    /// `diagnostics` says which. The error stream carries the compiler's own
    /// JSON and is read as such; the other carries whatever the program
    /// printed and is nobody's to interpret -- a `run` whose program prints a
    /// line beginning with a brace is printing a line beginning with a brace.
    void ShowAll(String text, bool diagnostics)
    {
        if (text.ByteLength() == 0u)
            return;
        foreach (var line in text.Replace("\r\n", "\n").Split("\n"))
        {
            if (diagnostics)
                Show(line);
            else
                ShowRaw(line);
        }
    }

    /// Adds one line of the compiler's output to the pane.
    ///
    /// **The list shows what a person reads and the model keeps what a click
    /// needs**, which is why the two are built together: the line the compiler
    /// sent is JSON, and nobody wants to read that.
    ///
    /// A diagnostic also goes to the Error List, which is the same information
    /// in the shape a person scans rather than reads -- a column each for the
    /// code, the message and the place, sortable by the platform, with the
    /// linker's own complaints and whatever a `run` printed left in Output
    /// where they belong.
    void Show(String line)
    {
        var message = BuildMessage.Parse(line);
        _output.Add(message.Describe());
        _messages.Add(message);

        if (message.IsDiagnostic)
            AddError(message);
    }

    /// Empties both panes and the model under them.
    ///
    /// One method rather than the three lines repeated at each of the four
    /// places a build starts: the Error List was added after two of them
    /// existed, and a fourth pane will be added after this one.
    void ClearOutput()
    {
        _output.Clear();
        _errors.Clear();
        _messages.Clear();
        _errorLines.Clear();
        _errorTail = "";
        _outputTail = "";
    }

    /// One diagnostic as a row, remembering which output line it came from so
    /// that double-clicking either list does the same thing.
    void AddError(BuildMessage message)
    {
        int row = _errors.AddRow(message.IsError ? "!" : "?");
        _errors.SetCell(row, 1, message.Code);
        _errors.SetCell(row, 2, message.Message);
        _errors.SetCell(row, 3, NameOf(message.File));
        _errors.SetCell(row, 4, message.HasPlace
                                ? Standard.Text.FromInteger(message.Line) : "");
        _errorLines.Add(_messages.Count - 1u);
    }

    /// A line that is not the compiler's, shown as it came.
    void ShowRaw(String line)
    {
        _output.Add(line);
        _messages.Add(BuildMessage.Plain());
    }

    String CountErrors()
    {
        nuint errors = 0u;
        foreach (var message in _messages)
        {
            if (message.IsError)
                errors++;
        }
        if (errors == 0u)
            return "";
        return Standard.Text.FromInteger(errors) + (errors == 1u ? " error" : " errors");
    }

    /// A line of the output was double-clicked: go to what it points at, in
    /// whichever tab holds that file -- opening it if none does, which is what
    /// tabs made possible and what the single-editor version had to refuse.
    void OnOutputChosen(Control sender)
    {
        if (_output.SelectedIndex < 0)
            return;
        GoToMessage((nuint)_output.SelectedIndex);
    }

    /// Goes to what the diagnostic at `index` points at. Shared by Output and
    /// the Error List, so that the two cannot drift into doing different things
    /// with the same double-click.
    void GoToMessage(nuint index)
    {
        if (index >= _messages.Count)
            return;

        var message = _messages[index];
        if (!message.HasPlace)
            return;

        var tab = TabFor(message.File);
        if (tab == null)
        {
            if (!OpenFile(message.File))
            {
                Say("Could not open " + message.File);
                return;
            }
            tab = TabFor(message.File);
            if (tab == null)
                return;
        }

        var found = (EditorTab)tab;
        _book.SelectedIndex = found.Page.Index;
        found.Editor.GoTo(message.Line - 1u,
                          message.Column > 0u ? message.Column - 1u : 0u);
        found.Editor.Focus();
    }



    // ------------------------------------------------- the project properties

    /// Edits `stainless.json` in a window, and writes it back on OK.
    ///
    /// **Modal, and the model is only touched if OK is pressed.** The tree, the
    /// build and the title all read the project in front, so a dialog that
    /// edited it live would have every other pane showing something half
    /// changed. The dialog fills itself from the project and writes back in one
    /// pass, which makes Cancel genuinely nothing having happened.
    ///
    /// **The file is re-read after writing**, rather than keeping the object the
    /// dialog edited. The writer emits only what differs from a default, so what
    /// lands on disk is not always field-for-field what went in -- and the model
    /// the window goes on using should be the one a fresh start would get, not a
    /// slightly richer one only this session has.
    void OnProjectProperties(MenuItem sender)
    {
        if (_project == null)
        {
            Say("No project is open.");
            return;
        }

        var project = (ProjectFile)_project;
        var dialog = new ProjectDialog();
        dialog.Load(project);
        dialog.ShowModal();

        if (!dialog.Accepted)
        {
            Say("Properties unchanged.");
            return;
        }

        // **A guard, not a validation.** The dialog has already read itself
        // back into the project; this asks whether what came out could possibly
        // be right. It exists because the first version of this read the
        // controls *after* the window had closed -- when a `TextBox`'s text is
        // gone, because it lives in the native control -- and wrote a project
        // with no name and no sources over a working one. That bug is fixed at
        // its cause, and this stands between the next one and somebody's file.
        if (project.Name == "" || project.Sources.Length == 0u)
        {
            Show("refusing to write a project with no name or no sources");
            Say("Properties not saved.");
            return;
        }

        var written = Project.Write(project, _projectPath);
        if (!written.Ok)
        {
            Show(written.Error);
            Say("Could not write " + _projectPath);
            return;
        }

        if (!OpenProject(_projectPath))
            return;

        Say("Project saved.");
    }

    // ------------------------------------------------------ find and replace

    /// Opens the find window, seeded from the selection.
    ///
    /// **Seeded from the selection**, because looking for the word under the
    /// caret is what Find is for nine times out of ten -- and only when the
    /// selection is on one line, since a multi-line selection is not something
    /// a line-oriented search can look for and putting it in the box would
    /// promise otherwise.
    void OnFind(MenuItem sender)
    {
        var dialog = Finder();

        var now = Current;
        if (now != null)
        {
            var editor = (CodeEditor)now;
            String chosen = editor.SelectedText;
            if (chosen != "" && !chosen.Contains("\n"))
                dialog.Needle = chosen;
        }

        dialog.Present();
    }

    /// Find Next without opening the window, which is what the menu item next
    /// to it is for: once a search is set up, repeating it should not need the
    /// dialog in front of the thing being searched.
    void OnFindNext(MenuItem sender)
    {
        var now = Current;
        if (now == null)
            return;

        var dialog = Finder();
        if (dialog.Needle == "")
        {
            OnFind(sender);
            return;
        }

        if (!((CodeEditor)now).FindNext(dialog.Needle, false, true))
            Say("No more matches for '" + dialog.Needle + "'.");
        else
            Say("");
    }

    /// The find window, made on the first ask.
    FindDialog Finder()
    {
        var made = _finder;
        if (made != null)
            return (FindDialog)made;

        // The closure is why this dialog holds no editor: it asks for whichever
        // one is in front at the moment a button is pressed, so changing tabs
        // with the window open searches the tab now being looked at.
        var dialog = new FindDialog(() => this.Current);
        _finder = dialog;
        return dialog;
    }

    // ------------------------------------------------------------- the panes

    void OnShowSolution(MenuItem sender) => ShowPane(Panes.Solution, "Solution Explorer");
    void OnShowErrors(MenuItem sender) => ShowPane(Panes.Errors, "Error List");
    void OnShowOutput(MenuItem sender) => ShowPane(Panes.Output, "Output");

    void ShowPane(String name, String title)
    {
        if (_dock.Reveal(name))
            Say(title + ".");
    }

    /// Puts every pane back where a first run would have had it.
    ///
    /// **It writes the file and says to restart**, rather than rearranging the
    /// window. A pane's edge is fixed when it is constructed -- `forms/` cannot
    /// reparent a control -- so moving one back to an edge it was not built on
    /// is the one thing this cannot do live. Saying so is better than a menu
    /// item that silently does three quarters of what it says.
    void OnResetLayout(MenuItem sender)
    {
        _arrangement = DockLayout.Default();
        if (SaveLayout(_arrangement, LayoutPath()))
            Say("Layout reset. It takes effect next time this starts.");
        else
            Say("Could not write " + LayoutPath() + ".");
    }

    /// Saves where everything is, on the way out.
    ///
    /// **`Remember` first**, because a splitter drag sets its neighbour's width
    /// on the control and tells nobody -- there is no drag-finished event to
    /// have listened for, so the sizes are read back off the controls at the
    /// one moment they are wanted.
    ///
    /// A failure to write is deliberately silent. The window is closing; there
    /// is nowhere to put the message that anyone would see, and losing a pane
    /// width is not worth refusing to exit over.
    protected override void OnClosing(CancelEventArgs args)
    {
        base.OnClosing(args);
        if (args.Cancel)
            return;

        // Asked before the layout is written, and the layout is not written at
        // all if the answer is no: a session that was not closed should not
        // leave a saved arrangement behind, because the next thing the person
        // does may be to move a pane and close properly.
        if (!MayCloseAll())
        {
            args.Cancel = true;
            return;
        }

        _dock.Remember();
        SaveLayout(_arrangement, LayoutPath());
    }

    // ------------------------------------------------------ the project tree

    /// Fills the Solution Explorer from the project in front.
    ///
    /// **From the project's `sources`, walked on disk**, rather than from a
    /// list of files the project keeps -- because it keeps none. A Stainless
    /// project names directories and the compiler compiles what is in them,
    /// which is the whole reason a project file here is twenty lines rather
    /// than a manifest of every file. The tree therefore shows what the build
    /// will actually see, which is a stronger guarantee than a file list that
    /// has to be kept in step.
    ///
    /// Rebuilt whole rather than patched. A project is opened and closed rarely
    /// and holds tens of files, so the cost is nothing and the alternative is a
    /// diff against the file system that can be wrong.
    void ShowProjectTree()
    {
        _tree.Clear();
        _treeItems.Clear();

        if (_project == null)
        {
            var none = _tree.Add("No project open");
            none.Expand();
            return;
        }

        var project = (ProjectFile)_project;
        var root = _tree.Add(project.Name + " (" + project.Version + ")");

        foreach (var source in project.SourcesFor(ProjectFile.ThisPlatform))
        {
            String resolved = project.Resolve(source);
            var branch = root.Add(source);

            if (Directory.Exists(resolved))
            {
                Remember(branch, resolved, true);
                AddFiles(branch, resolved);
            }
            else if (File.Exists(resolved))
            {
                Remember(branch, resolved, false);
            }
            branch.Expand();
        }

        // References last and always, even when empty: a References node that
        // appears only sometimes is one people stop looking for.
        var references = root.Add("References");
        foreach (var dependency in project.Dependencies)
        {
            references.Add(dependency.Name + " -- " + dependency.Describe());
        }
        foreach (var library in project.LibrariesFor(ProjectFile.ThisPlatform))
        {
            references.Add(library);
        }

        root.Expand();
    }

    /// Every `.sl` in a directory, and every directory under it.
    ///
    /// Sorted by the platform's own enumeration order, which on both systems is
    /// what the file system gives -- not sorted here, because a tree that
    /// reordered what the build sees would be lying about the build.
    void AddFiles(TreeNode branch, String folder)
    {
        var folders = Directory.Directories(folder);
        if (folders.Ok)
        {
            foreach (var inner in folders.Value)
            {
                var below = branch.Add(NameOf(inner));
                Remember(below, inner, true);
                AddFiles(below, inner);
            }
        }

        var files = Directory.Files(folder);
        if (!files.Ok)
            return;

        foreach (var file in files.Value)
        {
            if (file.EndsWith(".sl"))
                Remember(branch.Add(NameOf(file)), file, false);
        }
    }

    /// Ties a node to the file or directory it stands for.
    ///
    /// A list searched rather than a map, for the reason `TreeView.Lookup`
    /// gives: a tree small enough to be usable is a tree small enough to walk,
    /// and a handful of files is a search that is over in microseconds.
    void Remember(TreeNode node, String path, bool folder)
    {
        _treeItems.Add(new TreeEntry(node, path, folder));
    }

    /// What a node stands for, or null for one that stands for nothing -- the
    /// project root, the References branch and everything under it.
    TreeEntry? EntryFor(TreeNode node)
    {
        foreach (var entry in _treeItems)
        {
            if (entry.Node == node)
                return entry;
        }
        return null;
    }

    /// A node was double-clicked. A file opens; anything else does nothing.
    void OnTreeChosen(Control sender)
    {
        var chosen = _tree.SelectedNode;
        if (chosen == null)
            return;

        var entry = EntryFor((TreeNode)chosen);
        if (entry == null || ((TreeEntry)entry).IsFolder)
            return;

        OpenEntry((TreeEntry)entry);
    }

    /// Opens what a node stands for.
    ///
    /// **Not named `Open`**, though that is what it does: `Standard.Process`
    /// now has a module-level `Open`, and CLAUDE.md records what happens to a
    /// method that shares a name with one of those -- it resolves to the free
    /// function inside a lambda body and to the method everywhere else, which
    /// is a bug that shows up in exactly one place and looks like nothing.
    void OpenEntry(TreeEntry entry)
    {
        if (!OpenFile(entry.FullPath))
            Say("Could not read " + entry.FullPath);
    }

    // ------------------------------------------ the Solution Explorer's menu

    /// A right-click in the tree.
    ///
    /// **The node under the pointer, not the selected one.** Neither platform
    /// moves the selection on a right-click, so a menu built from
    /// `SelectedNode` would act on whatever was selected beforehand -- a
    /// Delete that removes a file nobody pointed at. `TreeView.NodeAt` answers
    /// what was actually clicked, and the selection is moved to follow it, so
    /// that what the menu is about is also what is highlighted while it is up.
    void OnTreeMouse(Control sender, MouseEventArgs args)
    {
        if (args.Button != MouseButton.Right)
            return;

        TreeEntry? target = null;
        var hit = _tree.NodeAt(args.Location);
        if (hit != null)
        {
            _tree.SelectedNode = hit;
            target = EntryFor((TreeNode)hit);
        }

        ShowTreeMenu(target, args.Location);
    }

    /// The context menu, built afresh every time it is shown.
    ///
    /// Building it each time is what `PopupMenu` is for -- its own doc comment
    /// says the point is items decided by what is selected *now* rather than
    /// kept in step from everywhere the selection can change.
    ///
    /// **There is no "remove from project", and that is not an omission.** A
    /// Stainless project names directories and the compiler compiles what is
    /// in them, which is why `ShowProjectTree` walks the disk rather than a
    /// manifest: a file is in the build because it is in the directory, and
    /// there is no list to take it out of. So the only honest way out of a
    /// build is to move the file or delete it, the item says Delete, and it
    /// asks first.
    void ShowTreeMenu(TreeEntry? target, Point at)
    {
        _menuTarget = target;

        bool isFile = target != null && !((TreeEntry)target).IsFolder;
        String folder = FolderFor(target);

        var menu = new PopupMenu();

        if (isFile)
        {
            menu.Add("&Open").Click += this.OnTreeOpen;
            menu.Add(MenuItem.Separator());
        }

        var added = menu.Add("Add &new file...");
        added.Enabled = folder.ByteLength() != 0u;
        added.Click += this.OnTreeAddFile;

        var renamed = menu.Add("&Rename...");
        renamed.Enabled = isFile;
        renamed.Click += this.OnTreeRename;

        var removed = menu.Add("&Delete");
        removed.Enabled = isFile;
        removed.Click += this.OnTreeDelete;

        menu.Add(MenuItem.Separator());

        var shown = menu.Add(RevealVerb());
        shown.Enabled = target != null;
        shown.Click += this.OnTreeReveal;

        menu.Add("Re&fresh").Click += this.OnTreeRefresh;

        // **Both backends raise the chosen item before this returns** -- Win32
        // through `TPM_RETURNCMD`, GTK through a nested main loop -- so the
        // target is still here when a handler asks for it, and clearing it on
        // the next line cannot come too early.
        menu.Show(_tree, at);
        _menuTarget = null;
    }

    /// The directory a new file would go in: the one that was clicked, or the
    /// one holding the file that was. Empty when neither, which is what
    /// disables the item rather than offering somewhere arbitrary.
    String FolderFor(TreeEntry? target)
    {
        if (target == null)
            return "";

        var entry = (TreeEntry)target;
        if (entry.IsFolder)
            return entry.FullPath;
        return Path.DirectoryName(entry.FullPath);
    }

    /// What the "show me this on disk" item says.
    ///
    /// The file manager's own name on each platform rather than one generic
    /// phrase, because people look for the word they already know.
    String RevealVerb()
    {
        #if WINDOWS
        return "Reveal in &Explorer";
        #else
        return "Open containing &folder";
        #endif
    }

    void OnTreeOpen(MenuItem sender)
    {
        var target = _menuTarget;
        if (target != null && !((TreeEntry)target).IsFolder)
            OpenEntry((TreeEntry)target);
    }

    void OnTreeRefresh(MenuItem sender)
    {
        ShowProjectTree();
        Say("Solution Explorer refreshed.");
    }

    void OnTreeAddFile(MenuItem sender)
    {
        String folder = FolderFor(_menuTarget);
        if (folder.ByteLength() == 0u)
            return;

        var asked = InputDialog.Ask("Add file", "Name of the new file:", "");
        if (asked is Some given)
            AddFileNamed(folder, given.Value);
    }

    /// Makes the file, seeds it, and opens it.
    ///
    /// **The extension is added when it is missing**, because `.sl` is the only
    /// thing the compiler reads out of a source directory and a file without it
    /// would sit there being ignored.
    void AddFileNamed(String folder, String typed)
    {
        String name = typed.Trim();
        if (name.ByteLength() == 0u)
            return;
        if (!name.EndsWith(".sl"))
            name = name + ".sl";

        String path = Path.Join(folder, name);
        if (File.Exists(path))
        {
            Application.Complain(name + " is already there.", "Add file");
            return;
        }

        String seed = "";
        String named = ModuleOf(folder);
        if (named.ByteLength() != 0u)
            seed = "module " + named + ";\n\n";

        if (File.WriteAllText(path, seed) != IOError.None)
        {
            Application.Complain("Could not create " + path + ".", "Add file");
            return;
        }

        ShowProjectTree();
        OpenFile(path);
        Say("Added " + path);
    }

    /// The module the `.sl` files in a directory declare, or `""` when they
    /// declare none or disagree.
    ///
    /// **A new file is seeded with its neighbours' module**, because a
    /// directory here is a module -- every file in `ide/src/App` says
    /// `module Ide.App;` -- and a new one that said nothing would fail to
    /// compile for a reason that has nothing to do with what was being
    /// written.
    ///
    /// The first declaration wins and the rest are checked against it. A
    /// directory whose files are split across modules is one where there is no
    /// right answer, and seeding with either would be a guess wearing the
    /// clothes of a fact -- so it seeds with nothing, and the empty file says
    /// so plainly.
    String ModuleOf(String folder)
    {
        var files = Directory.Files(folder);
        if (!files.Ok)
            return "";

        String found = "";
        foreach (var file in files.Value)
        {
            if (!file.EndsWith(".sl"))
                continue;

            String named = ModuleIn(file);
            if (named.ByteLength() == 0u)
                continue;
            if (found.ByteLength() == 0u)
            {
                found = named;
                continue;
            }
            if (found != named)
                return "";
        }
        return found;
    }

    /// The module one file declares, or `""`.
    ///
    /// The first line beginning with `module` wins, which is what the language
    /// requires anyway: a file has one module declaration, and it comes before
    /// everything but the licence comment.
    String ModuleIn(String path)
    {
        var lines = File.ReadAllLines(path);
        if (!lines.Ok)
            return "";

        foreach (var line in lines.Value)
        {
            String text = line.Trim();
            if (!text.StartsWith("module "))
                continue;
            return text.After("module ").Before(";").Trim();
        }
        return "";
    }

    void OnTreeRename(MenuItem sender)
    {
        var target = _menuTarget;
        if (target == null)
            return;

        var entry = (TreeEntry)target;
        if (entry.IsFolder)
            return;

        var asked = InputDialog.Ask("Rename", "New name:", NameOf(entry.FullPath));
        if (asked is Some given)
            RenameTo(entry, given.Value);
    }

    void RenameTo(TreeEntry entry, String typed)
    {
        String name = typed.Trim();
        if (name.ByteLength() == 0u || name == NameOf(entry.FullPath))
            return;

        String path = Path.Join(Path.DirectoryName(entry.FullPath), name);
        if (File.Exists(path))
        {
            Application.Complain(name + " is already there.", "Rename");
            return;
        }

        if (File.Rename(entry.FullPath, path) != IOError.None)
        {
            Application.Complain("Could not rename " + entry.FullPath + ".", "Rename");
            return;
        }

        // **A tab showing the file has to be told**, or it keeps the old path
        // and the next save writes the file back into existence under the name
        // it was just moved off.
        var open = TabFor(entry.FullPath);
        if (open != null)
        {
            var tab = (EditorTab)open;
            tab.Editor.Contents.Location = path;
            Relabel(tab);
            Retitle();
        }

        ShowProjectTree();
        Say("Renamed to " + name);
    }

    void OnTreeDelete(MenuItem sender)
    {
        var target = _menuTarget;
        if (target == null)
            return;

        var entry = (TreeEntry)target;
        if (entry.IsFolder)
            return;

        if (!Application.Ask("Delete " + NameOf(entry.FullPath) + "?\n\n"
                             + entry.FullPath + "\n\nThis cannot be undone.",
                             "Delete file"))
            return;

        if (File.Delete(entry.FullPath) != IOError.None)
        {
            Application.Complain("Could not delete " + entry.FullPath + ".",
                                 "Delete file");
            return;
        }

        // A tab showing a file that is no longer there is a tab that would
        // write it back on the next save, so it goes with the file.
        var open = TabFor(entry.FullPath);
        if (open != null)
            CloseTab((EditorTab)open);

        ShowProjectTree();
        Say("Deleted " + entry.FullPath);
    }

    void OnTreeReveal(MenuItem sender)
    {
        var target = _menuTarget;
        if (target != null)
            Reveal((TreeEntry)target);
    }

    /// Shows a file on disk, in whatever the platform's file manager is.
    ///
    /// **On a background thread**, for the same reason the build is: `Run` does
    /// not answer until the child has exited, and a file manager that takes a
    /// moment to come up would take this window with it. Nothing is done with
    /// the answer -- there is nothing useful to say about a file manager that
    /// declined to open, and the file is still right there in the tree.
    void Reveal(TreeEntry entry)
    {
        #if WINDOWS
        // `/select,<path>` is **one** argument, comma and all: Explorer parses
        // the switch itself rather than taking the path as a second token.
        String program = "explorer.exe";
        String[] arguments = ["/select," + entry.FullPath];
        if (entry.IsFolder)
            arguments = [entry.FullPath];
        #else
        String program = "xdg-open";
        String folder = entry.IsFolder ? entry.FullPath
                                       : Path.DirectoryName(entry.FullPath);
        String[] arguments = [folder];
        #endif

        Background.Run(() => Process.Run(program, arguments), finished => { });
        Say("Showing " + entry.FullPath);
    }

    /// A row of the Error List was double-clicked, which goes to exactly where
    /// the same diagnostic in Output goes -- one path through one model.
    void OnErrorChosen(Control sender)
    {
        int row = _errors.SelectedIndex;
        if (row < 0 || (nuint)row >= _errorLines.Count)
            return;

        GoToMessage(_errorLines[(nuint)row]);
    }

    // -------------------------------------------------------------- the rest

    void OnCaretMoved(Control sender)
    {
        var now = Current;
        if (now == null)
            return;
        var editor = (CodeEditor)now;
        var at = editor.CaretPosition;
        String line = editor.Contents.TextAt(at.Row);
        _status.SetPanelText(3,
            "Ln " + Standard.Text.FromInteger(at.Row + 1u)
          + ", Col " + Standard.Text.FromInteger(editor.ColumnOf(line, at.Column) + 1u));
    }

    void OnEdited(Control sender)
    {
        if (sender is CodeEditor editor)
            RelabelFor(editor);
        Retitle();
    }

    /// The title says what is open and whether it has been changed, which is
    /// the one piece of state a person checks without being told to.
    void Retitle()
    {
        var now = Current;
        if (now == null)
        {
            Text = "Stainless";
            return;
        }
        var editor = (CodeEditor)now;
        String path = editor.Contents.Location;

        // The project's name leads, as it does in every editor that has one:
        // which program this is matters more than which of its files is in
        // front, and the file is in the tab already.
        String project = ProjectName();
        String lead = project == "" ? "" : project + " -- ";

        Text = (editor.Contents.Edited ? "* " : "") + lead + NameOf(path) + " -- Stainless";
        _status.SetPanelText(0, path.ByteLength() == 0u ? "Not saved" : path);
    }

    void Say(String what) => _status.SetPanelText(1, what);

    /// Whether a list of arguments holds one.
    static bool Names(String[] arguments, String wanted)
    {
        foreach (var argument in arguments)
        {
            if (argument == wanted)
                return true;
        }
        return false;
    }

    /// What the self test checks, since a window cannot be typed into by a
    /// machine.
    public bool SelfTest()
    {
        bool ok = true;
        var editor = Editor;

        editor.Focus();
        Application.DoEvents();
        if (!editor.Focused)
        {
            Console.WriteLine("FAIL: the editor did not take the focus");
            ok = false;
        }

        editor.Type("int Main() { return 0; }");
        if (editor.Contents.TextAt(0u) != "int Main() { return 0; }")
        {
            Console.WriteLine("FAIL: typing");
            ok = false;
        }
        if (editor.Contents.LineAt(0u).Tokens.Count == 0u)
        {
            Console.WriteLine("FAIL: the line did not lex");
            ok = false;
        }

        editor.Type("\nint Second() { return 1; }");
        if (editor.Contents.LineCount != 2u
            || editor.Contents.LineAt(1u).Tokens.Count == 0u)
        {
            Console.WriteLine("FAIL: a second line");
            ok = false;
        }

        // The clipboard belongs to the whole desktop, so whatever was on it
        // goes back afterwards rather than being replaced by a test's leavings.
        String was = Clipboard.GetText();

        editor.SelectAll();
        if (!editor.Copy())
        {
            Console.WriteLine("FAIL: copy with a selection did nothing");
            ok = false;
        }
        if (!Clipboard.GetText().StartsWith("int Main()"))
        {
            Console.WriteLine("FAIL: the clipboard did not take the selection");
            ok = false;
        }

        nuint lines = editor.Contents.LineCount;
        editor.GoTo(lines - 1u, editor.Contents.LengthAt(lines - 1u));
        if (!editor.Paste())
        {
            Console.WriteLine("FAIL: paste did nothing");
            ok = false;
        }
        // Two lines pasted at the end of two gives three, not four: the first
        // pasted line joins the line the caret was on, which is what makes a
        // paste in the middle of a line work at all.
        if (editor.Contents.LineCount != lines * 2u - 1u)
        {
            Console.WriteLine("FAIL: pasting " + Standard.Text.FromInteger(lines)
                              + " lines at the end of " + Standard.Text.FromInteger(lines)
                              + " gave " + Standard.Text.FromInteger(editor.Contents.LineCount));
            ok = false;
        }
        Clipboard.SetText(was);

        // The text size, which every tab shares.
        int before = editor.FontSize;
        Resize(2);
        if (editor.FontSize != before + 2)
        {
            Console.WriteLine("FAIL: the text did not resize");
            ok = false;
        }
        Resize(-2);

        // A second tab, brought to the front, then closed again.
        nuint had = _open.Count;
        NewFile();
        if (_open.Count != had + 1u)
        {
            Console.WriteLine("FAIL: a new tab did not appear");
            ok = false;
        }
        if (_book.SelectedIndex != (int)(_open.Count - 1u))
        {
            Console.WriteLine("FAIL: the new tab did not come to the front");
            ok = false;
        }

        int at = _book.SelectedIndex;
        CloseTab(_open[(nuint)at]);
        if (_open.Count != had)
        {
            Console.WriteLine("FAIL: closing a tab did not remove it");
            ok = false;
        }

        // Closing them all leaves one empty tab rather than none.
        while (_open.Count > 1u)
            CloseTab(_open[0u]);
        CloseTab(_open[0u]);
        if (_open.Count != 1u)
        {
            Console.WriteLine("FAIL: closing every tab left "
                              + Standard.Text.FromInteger(_open.Count));
            ok = false;
        }

        // Several files at once, which is what the command line does and what
        // a single open never exercised.
        while (_open.Count > 1u)
            CloseTab(_open[0u]);
        OpenFile("samples/shapes.sl");
        OpenFile("samples/hello.sl");
        OpenFile("samples/json.sl");
        Application.DoEvents();
        ShowFirstTab();
        Application.DoEvents();

        // Only checkable from the repository root, since the paths are
        // relative; said rather than skipped silently, so a run that proved
        // less than it looks like says so.
        if (_open.Count != 3u)
        {
            Console.WriteLine("  (three-tab check skipped: run from the repository root)");
        }
        else if (Editor.TopLine != 0u)
        {
            Console.WriteLine("FAIL: with three tabs the first opened at line "
                              + Standard.Text.FromInteger(Editor.TopLine + 1u));
            ok = false;
        }

        // Undo, which is the one thing here that a self test can prove
        // completely: the text after undoing is either what it was or it is
        // not, and nobody has to look at the window to find out.
        {
            var scratch = AddTab(new Document());
            var pad = scratch.Editor;
            pad.Focus();
            Application.DoEvents();

            pad.Type("hello");
            if (pad.Contents.TextAt(0u) != "hello")
            {
                Console.WriteLine("FAIL: undo setup");
                ok = false;
            }

            // Typing a word is one undo and not five, which is the whole
            // reason the stack coalesces.
            pad.Undo();
            if (pad.Contents.TextAt(0u) != "")
            {
                Console.WriteLine("FAIL: one undo did not take back a typed word, leaving '"
                                  + pad.Contents.TextAt(0u) + "'");
                ok = false;
            }

            pad.Redo();
            if (pad.Contents.TextAt(0u) != "hello")
            {
                Console.WriteLine("FAIL: redo did not put it back");
                ok = false;
            }

            // A newline ends a run, so what follows undoes on its own.
            // Three calls, because that is what three keystrokes are --
            // one Type of the whole string is one insertion and rightly
            // one undo.
            pad.Type("\n");
            pad.Type("w");
            pad.Type("orld");
            pad.Undo();
            if (pad.Contents.LineCount != 2u || pad.Contents.TextAt(1u) != "")
            {
                Console.WriteLine("FAIL: undo crossed a line it should not have");
                ok = false;
            }

            // And undoing everything says the file is unmodified again, rather
            // than staying starred because a flag was latched.
            while (pad.Undo()) { }
            if (pad.Contents.Edited)
            {
                Console.WriteLine("FAIL: undoing back to the start left the file modified");
                ok = false;
            }
            if (pad.Contents.TextAt(0u) != "" || pad.Contents.LineCount != 1u)
            {
                Console.WriteLine("FAIL: undoing everything did not empty the document");
                ok = false;
            }
            if (pad.CanUndo)
            {
                Console.WriteLine("FAIL: there was still something to undo");
                ok = false;
            }

            CloseTab(scratch);
            Application.DoEvents();
        }

        // Selecting a word, which is what a double-click now does -- and could
        // not do before, because `Control.DoubleClick` was raised by nothing on
        // either backend and so had never fired at all.
        //
        // The gesture is not testable without a mouse; what it *does* is, which
        // is why `SelectWord` is a method rather than only a handler.
        {
            var pad = AddTab(new Document()).Editor;
            pad.Focus();
            Application.DoEvents();
            pad.Type("var total = count + 1;   // sum");

            // Inside a word takes the word and not the space after it.
            pad.GoTo(0u, 5u);
            pad.SelectWord();
            if (pad.SelectedText != "total")
            {
                Console.WriteLine("FAIL: double-click on a word selected '"
                                  + pad.SelectedText + "'");
                ok = false;
            }

            // At the first byte of a word, which is where a click usually lands.
            pad.GoTo(0u, 0u);
            pad.SelectWord();
            if (pad.SelectedText != "var")
            {
                Console.WriteLine("FAIL: at the start of a word it selected '"
                                  + pad.SelectedText + "'");
                ok = false;
            }

            // A run of spaces is its own run, and stops at the word either side.
            pad.GoTo(0u, 23u);
            pad.SelectWord();
            if (pad.SelectedText != "   ")
            {
                Console.WriteLine("FAIL: on spaces it selected '"
                                  + pad.SelectedText + "' rather than three spaces");
                ok = false;
            }

            // Punctuation is the third run, so `//` comes out whole rather than
            // one slash -- which is the case two runs would get wrong.
            pad.GoTo(0u, 26u);
            pad.SelectWord();
            if (pad.SelectedText != "//")
            {
                Console.WriteLine("FAIL: on punctuation it selected '"
                                  + pad.SelectedText + "'");
                ok = false;
            }

            // Past the end of the line, where a click in the empty space to the
            // right of the text lands. It must select the last run, not reach
            // past the line and not fault.
            pad.GoTo(0u, 200u);
            pad.SelectWord();
            if (pad.SelectedText != "sum")
            {
                Console.WriteLine("FAIL: past the end of the line it selected '"
                                  + pad.SelectedText + "'");
                ok = false;
            }

            // An empty line has no run at all, and must not select anything or
            // walk off the front of a zero-length string.
            pad.Type("\n");
            pad.SelectWord();
            if (pad.HasSelection)
            {
                Console.WriteLine("FAIL: an empty line selected something");
                ok = false;
            }

            CloseTab(_open[_open.Count - 1u]);
            Application.DoEvents();
        }

        // The three list fields the properties dialog edits as one line each.
        // A trailing space must not become an entry that names nothing, which
        // is what would send the compiler looking for a directory called "".
        {
            String[] round = ProjectDialog.Split(
                ProjectDialog.Joined(["src", "../forms/src", "vendor"]));
            if (round.Length != 3u || round[0u] != "src"
                || round[1u] != "../forms/src" || round[2u] != "vendor")
            {
                Console.WriteLine("FAIL: a source list did not survive the round trip");
                ok = false;
            }

            if (ProjectDialog.Split("  a   b  ").Length != 2u)
            {
                Console.WriteLine("FAIL: runs of spaces made empty entries");
                ok = false;
            }
            if (ProjectDialog.Split("   ").Length != 0u)
            {
                Console.WriteLine("FAIL: a field of spaces was not empty");
                ok = false;
            }
            if (ProjectDialog.Joined([]) != "")
            {
                Console.WriteLine("FAIL: an empty list did not join to nothing");
                ok = false;
            }
        }

        // Find and replace, which is entirely model and so is entirely
        // checkable here -- the dialog is three text boxes over these methods.
        {
            var pad = AddTab(new Document()).Editor;
            pad.Focus();
            Application.DoEvents();
            pad.Type("one two one\nthree ONE four\none");

            pad.GoTo(0u, 0u);
            if (!pad.FindNext("one", true, true) || pad.SelectedText != "one"
                || pad.CaretPosition.Row != 0u)
            {
                Console.WriteLine("FAIL: the first match was not found");
                ok = false;
            }

            // Again, which must advance rather than find the same one.
            if (!pad.FindNext("one", true, true) || pad.CaretPosition.Row != 0u
                || pad.CaretPosition.Column != 11u)
            {
                Console.WriteLine("FAIL: find next did not advance, landing at column "
                                  + Standard.Text.FromInteger(pad.CaretPosition.Column));
                ok = false;
            }

            // Case matters when it is asked to, so `ONE` on line 2 is skipped
            // and the next match is the one on line 3.
            if (!pad.FindNext("one", true, true) || pad.CaretPosition.Row != 2u)
            {
                Console.WriteLine("FAIL: a case-sensitive find matched the wrong case");
                ok = false;
            }

            // And the search wraps back to the top rather than stopping.
            if (!pad.FindNext("one", true, true) || pad.CaretPosition.Row != 0u)
            {
                Console.WriteLine("FAIL: the search did not wrap");
                ok = false;
            }

            // Ignoring case reaches `ONE`, which the pass above walked past.
            pad.GoTo(1u, 0u);
            if (!pad.FindNext("one", false, true) || pad.CaretPosition.Row != 1u
                || pad.SelectedText != "ONE")
            {
                Console.WriteLine("FAIL: a case-insensitive find missed 'ONE'");
                ok = false;
            }

            // Something that is not there is not found, and wrapping must not
            // turn that into a loop that never ends.
            if (pad.FindNext("zebra", false, true))
            {
                Console.WriteLine("FAIL: found something that is not there");
                ok = false;
            }

            // Replace acts on a selection that already matches, and otherwise
            // only finds -- the first press selects, the second replaces.
            pad.GoTo(0u, 0u);
            if (pad.ReplaceCurrent("two", "2", true))
            {
                Console.WriteLine("FAIL: replace changed something without a match selected");
                ok = false;
            }
            if (!pad.ReplaceCurrent("two", "2", true))
            {
                Console.WriteLine("FAIL: replace did not take the selected match");
                ok = false;
            }
            if (pad.Contents.TextAt(0u) != "one 2 one")
            {
                Console.WriteLine("FAIL: after replace line one reads '"
                                  + pad.Contents.TextAt(0u) + "'");
                ok = false;
            }

            // Replace All counts what it did, reaches every line, and honours
            // case -- `ONE` on line two stays.
            nuint changed = pad.ReplaceAll("one", "1", true);
            if (changed != 3u)
            {
                Console.WriteLine("FAIL: replace all changed "
                                  + Standard.Text.FromInteger(changed) + " rather than 3");
                ok = false;
            }
            if (pad.Contents.TextAt(0u) != "1 2 1"
                || pad.Contents.TextAt(1u) != "three ONE four"
                || pad.Contents.TextAt(2u) != "1")
            {
                Console.WriteLine("FAIL: replace all left '" + pad.Contents.TextAt(0u)
                                  + "' / '" + pad.Contents.TextAt(1u)
                                  + "' / '" + pad.Contents.TextAt(2u) + "'");
                ok = false;
            }

            // The replacement containing the needle is the case that never
            // terminates if the sweep wraps. It must replace each once.
            nuint grown = pad.ReplaceAll("1", "11", true);
            if (grown != 3u || pad.Contents.TextAt(0u) != "11 2 11")
            {
                Console.WriteLine("FAIL: a replacement containing the needle gave "
                                  + Standard.Text.FromInteger(grown) + " and '"
                                  + pad.Contents.TextAt(0u) + "'");
                ok = false;
            }

            // And the whole thing is one undo per replacement rather than a
            // document that cannot be put back.
            while (pad.Undo()) { }
            if (pad.Contents.TextAt(0u) != "")
            {
                Console.WriteLine("FAIL: undoing every replacement left '"
                                  + pad.Contents.TextAt(0u) + "'");
                ok = false;
            }

            CloseTab(_open[_open.Count - 1u]);
            Application.DoEvents();
        }

        // The panes, and what a self test can honestly say about them.
        //
        // **Not that anything is on the screen.** Three wells and a strip are
        // exactly the kind of thing `forms/` passed 116 checks about while
        // drawing nothing, so the arrangement is proved by screenshot and what
        // is proved here is the model underneath: that each pane was made, that
        // it landed on the edge the layout asked for, and that closing and
        // reopening one is the same object rather than a new empty tree.
        {
            if (_dock.PaneCount != 3u)
            {
                Console.WriteLine("FAIL: expected three panes, found "
                                  + Standard.Text.FromInteger(_dock.PaneCount));
                ok = false;
            }

            if (_dock.EdgeOf(Panes.Solution) != DockEdge.Left)
            {
                Console.WriteLine("FAIL: the tree is not in the left well");
                ok = false;
            }
            if (_dock.EdgeOf(Panes.Errors) != DockEdge.Bottom
                || _dock.EdgeOf(Panes.Output) != DockEdge.Bottom)
            {
                Console.WriteLine("FAIL: the build's panes are not in the bottom well");
                ok = false;
            }

            // A pane nobody has heard of is not held, which is what makes
            // `Reveal` safe to call from a menu that outlives a pane.
            if (_dock.Holds("toolbox") || _dock.Reveal("toolbox"))
            {
                Console.WriteLine("FAIL: a pane that does not exist was found");
                ok = false;
            }

            // Closing hides rather than destroys. The tree inside the pane is
            // live and the IDE is still holding it, so what comes back must be
            // the same one -- with the project still in it.
            nuint rooted = _tree.Nodes.Count;
            if (!_dock.Close(Panes.Solution))
            {
                Console.WriteLine("FAIL: closing the tree pane did nothing");
                ok = false;
            }
            Application.DoEvents();

            if (_dock.Showing(Panes.Solution))
            {
                Console.WriteLine("FAIL: a closed pane is still showing");
                ok = false;
            }
            if (!_dock.Holds(Panes.Solution))
            {
                Console.WriteLine("FAIL: a closed pane was destroyed rather than hidden");
                ok = false;
            }

            if (!_dock.Reveal(Panes.Solution))
            {
                Console.WriteLine("FAIL: a closed pane could not be reopened");
                ok = false;
            }
            Application.DoEvents();

            if (!_dock.Showing(Panes.Solution))
            {
                Console.WriteLine("FAIL: reopening the tree pane did not show it");
                ok = false;
            }
            if (_tree.Nodes.Count != rooted)
            {
                Console.WriteLine("FAIL: reopening the tree pane lost what was in it");
                ok = false;
            }

            // What is about to be written is what is on the screen, which is
            // the one thing `Remember` exists to guarantee -- a splitter drag
            // raises nothing, so the sizes are read back off the controls.
            _dock.Remember();
            var written = ParseLayout(WriteLayout(_dock.Layout));
            if (written.Find(Panes.Solution) == null
                || written.Find(Panes.Errors) == null
                || written.Find(Panes.Output) == null)
            {
                Console.WriteLine("FAIL: the layout about to be saved lost a pane");
                ok = false;
            }
            if (written.LeftWidth < SmallestWell || written.LeftWidth > LargestWell)
            {
                Console.WriteLine("FAIL: the saved left width is out of range at "
                                  + Standard.Text.FromInteger((long)written.LeftWidth));
                ok = false;
            }
        }

        // Build output arriving in pieces, which is what a pump hands over.
        //
        // **The line is the unit and the chunk is not.** A pump answers with
        // however many bytes the child had written, so a diagnostic routinely
        // arrives in two halves -- and an Error List holding half a JSON
        // object is exactly the failure the reassembly exists to prevent.
        //
        // Checked here rather than by building something: the seam is a string
        // in and a string out, so it wants no compiler, no child process and
        // no timing to exercise, which is the difference between a test that
        // means something and one that passes on a fast machine.
        {
            ClearOutput();

            // A chunk that stops mid-line shows the whole lines and keeps the
            // rest. Nothing of "second ha" may reach the pane.
            String left = ShowComplete("first line" + Newline() + "second ha", false);
            if (left != "second ha" || _output.Count != 1u
                || _output.ItemAt(0u) != "first line")
            {
                Console.WriteLine("FAIL: a split line was not held back: left='"
                                  + left + "' shown="
                                  + Standard.Text.FromInteger((long)_output.Count));
                ok = false;
            }

            // And the rest of it completes the line rather than starting one.
            left = ShowComplete(left + "lf" + Newline(), false);
            if (left != "" || _output.Count != 2u
                || _output.ItemAt(1u) != "second half")
            {
                Console.WriteLine("FAIL: a line split across two chunks came back as '"
                                  + (_output.Count > 1u ? _output.ItemAt(1u) : "")
                                  + "' with '" + left + "' left over");
                ok = false;
            }

            // Windows line endings are the compiler's on this platform, and
            // must not arrive as a stray carriage return on the end of a line.
            ClearOutput();
            ShowComplete("carried\r\n", false);
            if (_output.Count != 1u || _output.ItemAt(0u) != "carried")
            {
                Console.WriteLine("FAIL: a CRLF line came back as '"
                                  + (_output.Count == 0u ? "" : _output.ItemAt(0u)) + "'");
                ok = false;
            }

            ClearOutput();
        }

        // The project, which is what makes Build mean the program rather than
        // the file. Opening a file inside the fixture should find it without
        // anyone asking -- which is the behaviour, not just the reader.
        if (OpenFile("ide/tests/fixture/src/main.sl"))
        {
            Application.DoEvents();
            if (ProjectName() != "fixture")
            {
                Console.WriteLine("FAIL: opening a file did not find the project above it,"
                                  + " and answered '" + ProjectName() + "'");
                ok = false;
            }

            // The Solution Explorer's model, which is what the context menu
            // acts on.
            //
            // **Not that a menu appeared.** There is no pointer here, so what
            // a self test can honestly say is that every node the menu can be
            // opened on knows what it stands for, that a directory is told
            // from a file, and that a node standing for nothing offers
            // nothing -- which is the half that decides whether Delete removes
            // the right file.
            nuint folders = 0u;
            nuint files = 0u;
            foreach (var entry in _treeItems)
            {
                if (entry.IsFolder)
                    folders++;
                else
                    files++;
            }

            if (files != 2u)
            {
                Console.WriteLine("FAIL: the tree holds "
                                  + Standard.Text.FromInteger((long)files)
                                  + " files, not the fixture's two");
                ok = false;
            }
            if (folders == 0u)
            {
                Console.WriteLine("FAIL: the tree told no directory from a file");
                ok = false;
            }

            foreach (var entry in _treeItems)
            {
                if (EntryFor(entry.Node) != entry)
                {
                    Console.WriteLine("FAIL: a tree node did not answer with its own"
                                      + " entry: " + entry.FullPath);
                    ok = false;
                }

                // A new file goes beside a file, and inside a directory.
                String wanted = entry.IsFolder
                              ? entry.FullPath
                              : Path.DirectoryName(entry.FullPath);
                if (FolderFor(entry) != wanted)
                {
                    Console.WriteLine("FAIL: a new file beside " + entry.FullPath
                                      + " would go to '" + FolderFor(entry) + "'");
                    ok = false;
                }
            }

            if (FolderFor(null).ByteLength() != 0u)
            {
                Console.WriteLine("FAIL: a new file was offered a home with nothing"
                                  + " clicked on");
                ok = false;
            }

            // The module a new file would be seeded with. Both of the
            // fixture's files declare `Fixture`, so a third belongs in it too.
            String seeded = ModuleOf("ide/tests/fixture/src");
            if (seeded != "Fixture")
            {
                Console.WriteLine("FAIL: a new file would be seeded with module '"
                                  + seeded + "'");
                ok = false;
            }

            // And the arguments that finding it changes, which is the whole
            // point: a project build names the project and never a file.
            //
            // By what is in them rather than by where: this checked position 1
            // and broke the day `--diagnostics json` was added in front, which
            // is the test being about the wrong thing rather than the change
            // being wrong.
            var arguments = BuildArguments(false);
            if (!Names(arguments, "--project") || !Names(arguments, _projectPath))
            {
                Console.WriteLine("FAIL: a project build did not ask for the project");
                ok = false;
            }
            if (!Names(arguments, "--diagnostics") || !Names(arguments, "json"))
            {
                Console.WriteLine("FAIL: a build did not ask for diagnostics it can read");
                ok = false;
            }

            // The configuration picker, which is the only thing that decides
            // what a build is optimised for -- a project's own `optimize` and
            // `debug` are overridden rather than consulted, so what the picker
            // says has to reach the command line or it says nothing at all.
            if (!Names(arguments, "-g") || !Names(arguments, "-O0")
                || Names(arguments, "--no-debug"))
            {
                Console.WriteLine("FAIL: a Debug build did not ask to be debuggable");
                ok = false;
            }

            _configuration.SelectedIndex = 1;
            if (Chosen() != Configuration.Release)
            {
                Console.WriteLine("FAIL: the picker did not move to Release");
                ok = false;
            }

            var shipping = BuildArguments(false);
            if (!Names(shipping, "--no-debug") || !Names(shipping, "-O2")
                || Names(shipping, "-g") || Names(shipping, "-O0"))
            {
                Console.WriteLine("FAIL: a Release build asked to be debuggable");
                ok = false;
            }
            _configuration.SelectedIndex = 0;

            // Stop is pressable only while something is running, which is the
            // whole of what the toolbar claims to know.
            if (_stopButton.Enabled)
            {
                Console.WriteLine("FAIL: Stop was offered with nothing building");
                ok = false;
            }
            foreach (var argument in arguments)
            {
                if (argument.EndsWith(".sl"))
                {
                    Console.WriteLine("FAIL: a project build named a source file: " + argument);
                    ok = false;
                }
            }
        }
        else
        {
            Console.WriteLine("  (project check skipped: run from the repository root)");
        }

        if (ok)
        {
            Console.WriteLine("  editing, undo, word selection, lexing, the clipboard,");
            Console.WriteLine("  text size, tabs, the project and the docked panes");
        }
        return ok;
    }
}
