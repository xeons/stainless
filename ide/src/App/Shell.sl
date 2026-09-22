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
import Standard.Convert;
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
import Ide.Debugging;
import Debugger;

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
    TabControl _tabs;
    List<EditorTab> _openTabs;

    /// The wells, the splitters and the strips. Everything but the menu and the
    /// status bar lives inside it.
    DockHost _dock;
    /// Where the panes are and how wide, read at startup and written at exit.
    DockLayout _layout;

    ListBox _outputList;
    ListView _errorList;
    TreeView _tree;

    // ------------------------------------------------------------ debugging

    /// Every breakpoint, by file and line. Outlives each session.
    BreakpointStore _breakpoints;

    /// The session, or null when nothing is being debugged.
    DebugSession? _session;

    /// The last stop. Null when the program is running or gone.
    ///
    /// The panes are filled from it, and a hover reads its locals rather than
    /// asking the process: the values were true at the stop and nothing has
    /// run since.
    Snapshot? _lastStop;

    ListView _callStackList;
    ListView _threadList;
    ListView _localsList;
    ListView _watchList;
    ListView _breakList;
    ListBox _debugOutput;

    /// The watch expressions, which outlive each session the way breakpoints
    /// do -- a debugger that forgets what you were watching when the program
    /// exits is one you retype the same three expressions into.
    List<String> _watches;

    /// The frame the Call Stack has selected. Zero is where the program is.
    nuint _selectedFrame;

    /// Whether the next stop is this session's first.
    bool _isFirstStop;

    /// The pane `--show` asked for, which stays in front of the one a stop
    /// would otherwise bring forward. Empty when nobody asked.
    String _preferredPane;

    ToolBar _debugTools;
    ToolButton _startButton;
    ToolButton _pauseButton;
    ToolButton _stopDebugButton;
    ToolButton _stepIntoButton;
    ToolButton _stepOverButton;
    ToolButton _stepOutButton;
    StatusBar _statusBar;
    MainMenu _menuBar;

    MenuItem _themeItem;

    /// The find window, made the first time it is asked for and kept after
    /// that -- so the last search and the Match case tick survive closing it.
    /// Null until then: a window nobody has asked for should not be built.
    FindDialog? _findDialog;

    /// The size every editor's text is, kept here rather than on an editor
    /// because it is a preference of the program's and not of one file's.
    int _textSize;
    bool _isDark;

    /// Where the compiler is. Found once at startup.
    String _compilerPath;

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
    List<TreeEntry> _treeEntries;

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
    bool _isBuilding;

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
    CoolBar _coolBar;

    /// What draws the menus and the toolbar, which is deliberately **one**
    /// object shared by both: Office XP's hot menu item and its hot toolbar
    /// button are the same rectangle in the same colour, and two renderers
    /// would be two copies of that to keep in step by hand.
    ChromeRenderer _chrome;

    /// The toolbar's pictures, kept because the platform copied them but the
    /// list is what owns them. Null when the widget set refused, which leaves
    /// the buttons as captions and is not worth reporting.
    ImageList? _icons;
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
    Running? _compilerProcess;

    /// Where each icon sits in the list `BuildIcons` makes, in the order it
    /// adds them. Named rather than counted at the call site: a toolbar whose
    /// pictures are off by one is a toolbar where Clean says Run.
    /// The icon id `res/stainless-ide.rc` gives the program: a hex bolt with
    /// an S on it. One, because the shell shows the lowest-numbered one.
    static readonly int ProgramIcon = 1;

    static readonly int IconBuild   = 0;
    static readonly int IconRebuild = 1;
    static readonly int IconClean   = 2;
    static readonly int IconRun     = 3;
    static readonly int IconStop    = 4;

    static readonly int IconStart     = 5;
    static readonly int IconPause     = 6;
    static readonly int IconStopDebug = 7;
    static readonly int IconStepInto  = 8;
    static readonly int IconStepOver  = 9;
    static readonly int IconStepOut   = 10;
    static readonly int IconRestart   = 11;

    public Shell()
    {
        base(WindowBorder.Sizable);
        Text = "Stainless";
        SetBounds(0, 0, 1000, 700);

        _openTabs = new List<EditorTab>();
        _messages = new List<BuildMessage>();
        _errorLines = new List<nuint>();
        _treeEntries = new List<TreeEntry>();
        _menuTarget = null;
        _project = null;
        _projectPath = "";
        _findDialog = null;
        _isBuilding = false;
        _compilerProcess = null;
        _icons = null;
        _errorTail = "";
        _outputTail = "";
        _breakpoints = new BreakpointStore();
        _watches = new List<String>();
        _session = null;
        _lastStop = null;
        _selectedFrame = 0u;
        _isFirstStop = true;
        _preferredPane = "";
        _compilerPath = FindCompiler();
        _textSize = 10;
        _isDark = false;

        // The window's own icon, which is separate from the one Explorer
        // draws: the shell finds that by picking the lowest-numbered icon in
        // the binary, and a window has to be handed one. False on GTK, where
        // an icon comes from the desktop theme rather than from the program,
        // and there is nothing useful to do about that here.
        UseIconResource(ProgramIcon);

        _statusBar = new StatusBar(this);
        _statusBar.Dock = DockStyle.Bottom;
        // Four, and the third is why. The error count used to be written into
        // the same panel as the message, so "Built." appeared and was replaced
        // by "3 errors" on the same line in the same instant -- which read as
        // the build having said only the second thing.
        _statusBar.AddPanel(420);      // the path
        _statusBar.AddPanel(200);      // what just happened
        _statusBar.AddPanel(110);      // how many errors
        _statusBar.AddPanel(110);      // where the caret is
        _statusBar.AddPanel(0);        // what the pointer is over, while stopped

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
        _chrome = new OfficeXpRenderer();

        _coolBar = new CoolBar(this);
        _coolBar.Dock = DockStyle.Top;

        _configuration = new ComboBox(_coolBar);
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
        var chosen = new CoolBand(_coolBar);
        chosen.Text = "Configuration";
        chosen.Control = _configuration;
        chosen.Width = 230;

        _tools = new ToolBar(_coolBar);
        _tools.Height = 26;
        _tools.Renderer = _chrome;

        // Drawn rather than loaded -- `Icons.sl` says why -- and null when the
        // widget set would not take them, in which case the buttons are their
        // captions alone and nothing else changes.
        _icons = BuildIcons();
        if (_icons != null)
            _tools.Images = _icons;

        _tools.Add("Build", IconBuild).Click += this.OnBuild;
        _tools.Add("Rebuild", IconRebuild).Click += this.OnRebuild;
        _tools.Add("Clean", IconClean).Click += this.OnClean;
        _tools.AddSeparator();
        _tools.Add("Run", IconRun).Click += this.OnRun;
        _stopButton = _tools.Add("Stop", IconStop);
        _stopButton.Click += this.OnStop;

        // No caption: the buttons already say what they do, and a band reading
        // "Build" beside a button reading "Build" is twice the width for none
        // of the information.
        var commands = new CoolBand(_coolBar);
        commands.Text = "";
        commands.Break = false;     // share the row with the picker
        commands.Control = _tools;
        commands.Width = 380;

        // The debug commands on a row of their own. Start Debugging and Run
        // are both a green triangle; separating the rows is what tells them
        // apart, and is how Visual Studio's own two bands read.
        _debugTools = new ToolBar(_coolBar);
        _debugTools.Height = 26;
        _debugTools.Renderer = _chrome;
        if (_icons != null)
            _debugTools.Images = _icons;

        _startButton = _debugTools.Add("Start", IconStart);
        _startButton.Click += this.OnStartDebugging;
        _pauseButton = _debugTools.Add("Break", IconPause);
        _pauseButton.Click += this.OnBreakAll;
        _stopDebugButton = _debugTools.Add("Stop", IconStopDebug);
        _stopDebugButton.Click += this.OnStopDebugging;
        _debugTools.Add("Restart", IconRestart).Click += this.OnRestartDebugging;
        _debugTools.AddSeparator();
        _stepIntoButton = _debugTools.Add("Into", IconStepInto);
        _stepIntoButton.Click += this.OnStepInto;
        _stepOverButton = _debugTools.Add("Over", IconStepOver);
        _stepOverButton.Click += this.OnStepOver;
        _stepOutButton = _debugTools.Add("Out", IconStepOut);
        _stepOutButton.Click += this.OnStepOut;

        var debugging = new CoolBand(_coolBar);
        debugging.Text = "Debug";
        debugging.Break = true;     // its own row
        debugging.Control = _debugTools;
        debugging.Width = 420;

        _coolBar.Height = _coolBar.PreferredSize.Height;
        EnableBuildCommands();

        // The layout is read before anything is built, because where a pane
        // goes is decided as it is made -- a control's parent is fixed at
        // construction and `forms/` cannot move it afterwards.
        _layout = ReadLayout(GetLayoutPath());
        _dock = new DockHost(this, _layout);
        _dock.Dock = DockStyle.Fill;

        var solution = _dock.AddPane(Panes.Solution, "Solution Explorer", DockEdge.Left);
        _tree = new TreeView(solution);
        _tree.Dock = DockStyle.Fill;
        _tree.DoubleClick += this.OnTreeChosen;
        _tree.ContextMenu += this.OnTreeContextMenu;

        var errors = _dock.AddPane(Panes.Errors, "Error List", DockEdge.Bottom);
        _errorList = new ListView(errors);
        _errorList.Dock = DockStyle.Fill;
        _errorList.View = ListViewStyle.Details;
        _errorList.SetFullRowSelect(true, true);
        // Widths that add up to less than the bottom well starts at, so that
        // every column is visible without scrolling on a first run. Description
        // is the one that gives, because it is also the one the platform lets
        // you widen by dragging when a message is long.
        _errorList.AddColumn("", 22);
        _errorList.AddColumn("Code", 70);
        _errorList.AddColumn("Description", 380);
        _errorList.AddColumn("File", 140);
        _errorList.AddColumn("Line", 50, HorizontalAlignment.Right);
        _errorList.DoubleClick += this.OnErrorChosen;

        var output = _dock.AddPane(Panes.Output, "Output", DockEdge.Bottom);
        _outputList = new ListBox(output);
        _outputList.Dock = DockStyle.Fill;
        _outputList.DoubleClick += this.OnOutputChosen;

        var locals = _dock.AddPane(Panes.Locals, "Locals", DockEdge.Bottom);
        _localsList = new ListView(locals);
        _localsList.Dock = DockStyle.Fill;
        _localsList.View = ListViewStyle.Details;
        _localsList.SetFullRowSelect(true, true);
        _localsList.AddColumn("Name", 130);
        _localsList.AddColumn("Value", 260);
        _localsList.AddColumn("Type", 170);

        var watches = _dock.AddPane(Panes.Watch, "Watch", DockEdge.Bottom);
        _watchList = new ListView(watches);
        _watchList.Dock = DockStyle.Fill;
        _watchList.View = ListViewStyle.Details;
        _watchList.SetFullRowSelect(true, true);
        _watchList.AddColumn("Name", 180);
        _watchList.AddColumn("Value", 260);
        _watchList.AddColumn("Type", 120);
        _watchList.ContextMenu += this.OnWatchContextMenu;
        _watchList.DoubleClick += this.OnWatchChosen;

        var stack = _dock.AddPane(Panes.CallStack, "Call Stack", DockEdge.Bottom);
        _callStackList = new ListView(stack);
        _callStackList.Dock = DockStyle.Fill;
        _callStackList.View = ListViewStyle.Details;
        _callStackList.SetFullRowSelect(true, true);
        _callStackList.AddColumn("", 22);
        _callStackList.AddColumn("Function", 220);
        _callStackList.AddColumn("Line", 320);
        _callStackList.DoubleClick += this.OnFrameChosen;

        var threads = _dock.AddPane(Panes.Threads, "Threads", DockEdge.Bottom);
        _threadList = new ListView(threads);
        _threadList.Dock = DockStyle.Fill;
        _threadList.View = ListViewStyle.Details;
        _threadList.SetFullRowSelect(true, true);
        _threadList.AddColumn("", 22);
        _threadList.AddColumn("Id", 80);
        _threadList.AddColumn("Function", 220);
        _threadList.AddColumn("Location", 240);
        _threadList.DoubleClick += this.OnThreadChosen;

        var points = _dock.AddPane(Panes.Breakpoints, "Breakpoints", DockEdge.Bottom);
        _breakList = new ListView(points);
        _breakList.Dock = DockStyle.Fill;
        _breakList.View = ListViewStyle.Details;
        _breakList.SetFullRowSelect(true, true);
        _breakList.AddColumn("", 22);
        _breakList.AddColumn("Where", 300);
        _breakList.AddColumn("State", 120);
        _breakList.DoubleClick += this.OnBreakpointChosen;
        _breakList.ContextMenu += this.OnBreakpointContextMenu;

        var trace = _dock.AddPane(Panes.DebugOutput, "Debug Output", DockEdge.Bottom);
        _debugOutput = new ListBox(trace);
        _debugOutput.Dock = DockStyle.Fill;

        _tabs = new TabControl(_dock.Documents);
        _tabs.Dock = DockStyle.Fill;
        _tabs.SelectedIndexChanged += this.OnTabChanged;

        // Once, after every pane exists, rather than after each -- see
        // `DockHost.ArrangeWells`.
        _dock.ArrangeWells();

        BuildMenuBar();
        OpenBlankTab();
        ShowProjectTree();
        EnableDebugCommands();
        ShowStatus("Ready.");
    }

    // ------------------------------------------------------------- the tabs

    /// The editor of whichever tab is showing, or null when none is.
    public CodeEditor? Current
    {
        get
        {
            int at = _tabs.SelectedIndex;
            if (at < 0 || (nuint)at >= _openTabs.Count)
                return null;
            return _openTabs[(nuint)at].Editor;
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

    public nuint TabCount => _openTabs.Count;

    /// Brings the first tab to the front and gives it the keyboard.
    ///
    /// For the command line, which opens each file it was given in turn and
    /// would otherwise leave the last one showing -- where a shell expanding
    /// `*.sl` means the first.
    public void ShowFirstTab()
    {
        if (_openTabs.IsEmpty)
            return;
        _tabs.SelectedIndex = 0;
        _openTabs[0u].Editor.Focus();
    }

    /// Makes a tab, puts an editor on it, and brings it to the front.
    EditorTab AddTab(Document document)
    {
        var page = new TabPage(_tabs, "");
        var editor = new CodeEditor(page);
        editor.Dock = DockStyle.Fill;
        editor.SetDocument(document);
        editor.FontSize = _textSize;
        editor.Palette = _isDark ? Theme.CreateDark() : Theme.CreateLight();
        editor.CaretMoved += this.OnCaretMoved;
        editor.Edited += this.OnEdited;
        editor.KeyDown += this.OnEditorKey;

        // The margin asks per painted line rather than being handed a list, so
        // one store answers for every tab and nothing is copied.
        editor.MarginClicked += this.OnMarginClicked;
        editor.Hovered += (word) => this.OnHovered(word);
        editor.ShowMarginMarks((row) => GetMarkFor(editor, row));

        // A breakpoint is anchored to a line number, and typing above one
        // moves that line. Without this the glyph stays beside code that has
        // moved on, which reads as a debugger ignoring where it was put.
        document.LinesShifted += (first, delta)
            => ShiftBreakpoints(editor, first, delta);

        var tab = new EditorTab(page, editor);
        _openTabs.Add(tab);

        _tabs.SelectedIndex = page.Index;
        UpdateTabCaption(tab);
        UpdateTitle();
        return tab;
    }

    /// The tab a file is already open in, or null.
    ///
    /// **Compared by the path as it was given.** Two spellings of one file -- a
    /// relative path and an absolute one, or two capitalisations on Windows --
    /// would open it twice. Settling that needs a canonical form from the
    /// platform, which `Standard.Path` does not offer yet.
    EditorTab? FindTab(String path)
    {
        if (path.ByteLength() == 0u)
            return null;
        foreach (var tab in _openTabs)
        {
            if (tab.Editor.Contents.Location == path)
                return tab;
        }
        return null;
    }

    /// Opens a file, or brings its tab forward when it is already open.
    public bool OpenFile(String path)
    {
        var already = FindTab(path);
        if (already != null)
        {
            _tabs.SelectedIndex = ((EditorTab)already).Page.Index;
            ShowStatus(path + " is already open.");
            return true;
        }

        var document = new Document();
        if (!document.LoadFile(path))
            return false;

        // An untouched, unnamed, empty first tab is a placeholder rather than a
        // document, so opening a file replaces it instead of sitting beside it.
        var spare = Current;
        bool replacing = _openTabs.Count == 1u && spare != null && IsBlank((CodeEditor)spare);
        var stale = replacing ? _openTabs[0u] : null;

        var tab = AddTab(document);
        if (stale != null)
            CloseTab((EditorTab)stale);
        tab.Editor.Focus();

        // A file usually arrives with a project above it, and finding it here
        // is what makes Build mean "build this program" without anyone having
        // opened the project by hand.
        AdoptProjectFor(path);

        ShowStatus("Opened " + path);
        return true;
    }

    bool IsBlank(CodeEditor editor)
    {
        return editor.Contents.Location.ByteLength() == 0u
            && !editor.Contents.Edited
            && editor.Contents.LineCount == 1u
            && editor.Contents.GetLineLength(0u) == 0u;
    }

    void OpenBlankTab()
    {
        var tab = AddTab(new Document());
        tab.Editor.Focus();
    }

    /// Shuts a tab, and makes sure one is always left.
    void CloseTab(EditorTab tab)
    {
        _tabs.RemovePage(tab.Page);
        for (nuint i = 0u; i < _openTabs.Count; i++)
        {
            if (_openTabs[i] == tab)
            {
                _openTabs.RemoveAt(i);
                break;
            }
        }
        // A window with no editor in it has nowhere to type, so closing the
        // last tab opens an empty one rather than leaving a hole.
        if (_openTabs.IsEmpty)
        {
            OpenBlankTab();
            return;
        }
        UpdateTitle();
        OnCaretMoved(this);
    }

    /// What a tab says: the file's name, and a mark when it has been changed.
    void UpdateTabCaption(EditorTab tab)
    {
        tab.Page.Caption = (tab.Editor.Contents.Edited ? "* " : "")
                         + GetDisplayName(tab.Editor.Contents.Location);
    }

    String GetDisplayName(String path)
    {
        if (path.ByteLength() == 0u)
            return "Untitled";
        String name = path.AfterLast(PathSeparator);
        return name.ByteLength() == 0u ? path : name;
    }

    void OnTabChanged(Control sender)
    {
        UpdateTitle();
        var now = Current;
        if (now != null)
        {
            ((CodeEditor)now).Focus();
            OnCaretMoved(this);
        }
    }

    // ------------------------------------------------------------- the menu

    void BuildMenuBar()
    {
        _menuBar = new MainMenu();

        // **Office XP, on Windows, and nothing on GTK.** A renderer asks the
        // platform to hand its items over and takes no for an answer: the GTK
        // backend says no, so the menus there stay the desktop's own, which is
        // what somebody running that desktop wanted from them. There is no
        // `#if` here for the same reason there is none anywhere else in this
        // program -- the seam is what knows which platform it is on.
        _menuBar.Renderer = _chrome;

        var file = _menuBar.Add("&File");
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

        var edit = _menuBar.Add("&Edit");
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

        var build = _menuBar.Add("&Build");
        build.Add("&Build").Click += this.OnBuild;
        build.Add("Re&build").Click += this.OnRebuild;
        build.Add("&Run").Click += this.OnRun;
        build.Add("&Stop").Click += this.OnStop;
        build.Add(MenuItem.Separator());
        build.Add("&Clean").Click += this.OnClean;
        build.Add(MenuItem.Separator());
        build.Add("&Clear output").Click += this.OnClearOutput;

        var debug = _menuBar.Add("&Debug");
        debug.Add("&Start debugging\tF5").Click += this.OnStartDebugging;
        debug.Add("Start &without debugging\tCtrl+F5").Click += this.OnRun;
        debug.Add("&Restart\tCtrl+Shift+F5").Click += this.OnRestartDebugging;
        debug.Add("Stop &debugging\tShift+F5").Click += this.OnStopDebugging;
        debug.Add(MenuItem.Separator());
        debug.Add("Break &all").Click += this.OnBreakAll;
        debug.Add("&Continue\tF5").Click += this.OnContinue;
        debug.Add(MenuItem.Separator());
        debug.Add("Step &into\tF11").Click += this.OnStepInto;
        debug.Add("Step &over\tF10").Click += this.OnStepOver;
        debug.Add("Step o&ut\tShift+F11").Click += this.OnStepOut;
        debug.Add(MenuItem.Separator());
        debug.Add("Toggle &breakpoint\tF9").Click += this.OnToggleBreakpoint;
        debug.Add("Brea&kpoint condition...").Click += this.OnBreakpointCondition;
        debug.Add("Delete all brea&kpoints").Click += this.OnClearBreakpoints;
        debug.Add(MenuItem.Separator());
        debug.Add("Add &watch...").Click += this.OnAddWatch;

        var view = _menuBar.Add("&View");
        // The panes first, which is where Visual Studio puts them and where
        // someone goes after closing one by accident -- a closed pane is hidden
        // rather than destroyed, so this brings back the same tree with the
        // same project already in it.
        view.Add("&Solution Explorer").Click += this.OnShowSolution;
        view.Add("&Error List").Click += this.OnShowErrors;
        view.Add("&Output").Click += this.OnShowOutput;
        view.Add("&Locals").Click += this.OnShowLocals;
        view.Add("&Watch").Click += this.OnShowWatch;
        view.Add("&Call Stack").Click += this.OnShowCallStack;
        view.Add("T&hreads").Click += this.OnShowThreads;
        view.Add("&Breakpoints").Click += this.OnShowBreakpoints;
        view.Add("&Debug Output").Click += this.OnShowDebugOutput;
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

        Menu = _menuBar;
    }

    // ------------------------------------------------------------- the file

    void OnNew(MenuItem sender)
    {
        OpenBlankTab();
        ShowStatus("A new file.");
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
            ShowStatus("Could not read " + chosen.Value);
    }

    void OnSave(MenuItem sender)
    {
        var now = Current;
        if (now != null)
            SaveEditorTo((CodeEditor)now, ((CodeEditor)now).Contents.Location);
    }

    void OnSaveAs(MenuItem sender)
    {
        var now = Current;
        if (now != null)
            SaveEditorTo((CodeEditor)now, "");
    }

    void OnCloseTab(MenuItem sender)
    {
        int at = _tabs.SelectedIndex;
        if (at < 0 || (nuint)at >= _openTabs.Count)
            return;
        var tab = _openTabs[(nuint)at];
        if (!ConfirmCloseTab(tab))
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
    bool ConfirmCloseTab(EditorTab tab)
    {
        if (!tab.Editor.Contents.Edited)
            return true;

        String name = GetDisplayName(tab.Editor.Contents.Location);
        if (name == "")
            name = "this file";

        var answer = Application.ShowMessage(
            "Save the changes to " + name + " before closing it?",
            "Stainless", MessageButtons.YesNoCancel, MessageIcon.Question);

        if (answer == DialogResult.Yes)
            return SaveEditorTo(tab.Editor, tab.Editor.Contents.Location);

        // Anything that is not an explicit Yes or No keeps the tab. A dialog
        // that failed to open answers `None`, and treating that as "discard"
        // would lose work because a window manager was busy.
        return answer == DialogResult.No;
    }

    /// Every edited tab, asked about in turn. False as soon as one is
    /// cancelled, leaving the rest untouched -- which is what cancelling the
    /// whole operation means.
    bool ConfirmCloseAllTabs()
    {
        // Backwards, because saying No to a tab closes it and shortens the
        // list under the loop. Going forwards would skip the tab that slid
        // into the index just visited, which is the classic way to lose one.
        for (nuint i = _openTabs.Count; i > 0u; i--)
        {
            nuint at = i - 1u;
            if (at >= _openTabs.Count)
                continue;
            if (!ConfirmCloseTab(_openTabs[at]))
                return false;
        }
        return true;
    }

    /// Saves an editor to `path`, or asks for one when it is empty. Answers
    /// whether it was written.
    bool SaveEditorTo(CodeEditor editor, String path)
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

        if (!editor.Contents.SaveFile(target))
        {
            ShowStatus("Could not write " + target);
            return false;
        }
        UpdateTabCaptionFor(editor);
        UpdateTitle();
        ShowStatus("Saved " + target);
        return true;
    }

    /// Updates the tab an editor is on, whichever one that is.
    void UpdateTabCaptionFor(CodeEditor editor)
    {
        foreach (var tab in _openTabs)
        {
            if (tab.Editor == editor)
            {
                UpdateTabCaption(tab);
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
            ShowStatus("Nothing to undo.");
    }

    void OnRedo(MenuItem sender)
    {
        var now = Current;
        if (now == null)
            return;
        if (!((CodeEditor)now).Redo())
            ShowStatus("Nothing to redo.");
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
        _isDark = !_themeItem.Checked;
        _themeItem.Checked = _isDark;
        var palette = _isDark ? Theme.CreateDark() : Theme.CreateLight();
        foreach (var tab in _openTabs)
            tab.Editor.Palette = palette;
    }

    void OnLarger(MenuItem sender) => ResizeText(1);
    void OnSmaller(MenuItem sender) => ResizeText(-1);
    void OnResetSize(MenuItem sender) => ResizeText(DefaultTextSize - _textSize);

    /// Changes the text size in every tab at once.
    ///
    /// **Every tab, not the one in front.** A size is a property of how this
    /// person reads and not of which file they are looking at, so an editor
    /// that resized one tab would make switching tabs change the size of the
    /// text.
    public void ResizeText(int by)
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
        foreach (var tab in _openTabs)
            tab.Editor.FontSize = _textSize;
        ShowStatus("Text size " + Standard.Text.FromInteger(_textSize) + ".");
    }

    // --------------------------------------------------------- the compiler

    /// Where `stainless` is: beside this program first, and on the path after.
    String FindCompiler()
    {
        String self = Env.Program();
        long cut = self.LastIndexOf(PathSeparator);
        if (cut > 0)
        {
            String beside = self.Substring(0u, (nuint)cut) + PathSeparator
                          + "stainless" + Extension;
            if (File.Exists(beside))
                return beside;
        }
        return "stainless";
    }

    /// How many items at or below this one the platform kept for itself.
    ///
    /// Recursive rather than a `Walk` taking a closure, because a closure
    /// captures by value in this language -- a visitor that set a flag would
    /// be setting its own copy of it, and the check would pass whatever it
    /// found.
    nuint CountPlatformDrawnItems(MenuItem item)
    {
        nuint kept = item.IsOwnerDrawn ? 0u : 1u;
        foreach (var child in item.Items)
            kept = kept + CountPlatformDrawnItems(child);
        return kept;
    }

    /// One line ending, as the compiler writes them on this platform.
    String Newline
    {
        get
        {
            #if WINDOWS
            return "\r\n";
            #else
            return "\n";
            #endif
        }
    }

    String PathSeparator
    {
        get
        {
            #if WINDOWS
            return "\\";
            #else
            return "/";
            #endif
        }
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

    void OnBuild(MenuItem sender) => BuildProgram(false);
    void OnBuild(Control sender) => BuildProgram(false);
    void OnRun(MenuItem sender) => BuildProgram(true);
    void OnRun(Control sender) => BuildProgram(true);

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
            ShowStatus("No project is open.");
            return;
        }

        _project = null;
        _projectPath = "";
        UpdateTitle();
        ShowProjectTree();
        ShowStatus("Project closed. Building compiles the file in front.");
    }

    /// Reads a project and takes it as the one in front.
    ///
    /// **A failure is shown and does not close what was open.** A project file
    /// being edited is broken for as long as it takes to type the next line,
    /// and an editor that dropped the project on every keystroke's worth of
    /// invalid JSON would be unusable.
    public bool OpenProject(String path)
    {
        var read = Project.ReadProjectFile(path);
        if (!read.Ok)
        {
            ShowOutputLine(read.Error);
            ShowStatus("That project could not be read.");
            return false;
        }

        _project = read.Value;
        _projectPath = path;
        UpdateTitle();
        ShowProjectTree();

        var project = (ProjectFile)read.Value;
        ShowStatus("Project " + project.Name + " " + project.Version + ".");
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

        String found = Project.FindProjectFile(Path.DirectoryName(path));
        if (found == "")
            return;

        var read = Project.ReadProjectFile(found);
        if (!read.Ok)
            return;

        _project = read.Value;
        _projectPath = found;
        UpdateTitle();
        ShowProjectTree();
    }

    /// What the compiler is being asked to do, for the status line.
    String ProjectName
    {
        get
        {
            if (_project == null)
                return "";
            return ((ProjectFile)_project).Name;
        }
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
    void BuildProgram(bool thenRun)
    {
        if (_isBuilding)
        {
            ShowStatus("A build is already running.");
            return;
        }

        if (!SaveBeforeBuilding())
            return;

        ClearOutput();

        var arguments = ComposeCompilerArguments(thenRun);
        ShowStatus(thenRun ? "Running..." : "Building...");
        StartCompiler(arguments, thenRun ? "Ran." : "Built.");
    }

    void OnClean(MenuItem sender) => CleanProject();
    void OnClean(Control sender) => CleanProject();

    void CleanProject()
    {
        if (_isBuilding)
        {
            ShowStatus("A build is already running.");
            return;
        }

        if (_project == null)
        {
            ShowStatus("Clean needs a project; there is nothing else to clean.");
            return;
        }

        ClearOutput();
        ShowStatus("Cleaning...");

        if (CleanObjects())
            ShowStatus("Cleaned.");
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
        String rubbish = project.ResolvePath(project.ObjectDirectory);

        if (!IsInsideProject(project, rubbish))
        {
            ShowOutputLine("refusing to clean '" + rubbish + "', which is outside the project");
            ShowStatus("Clean refused.");
            return false;
        }

        if (!Directory.Exists(rubbish))
            return true;

        nuint removed = DeleteDirectoryTree(rubbish);
        ShowOutputLine("removed " + Standard.Text.FromInteger((long)removed)
                       + " files from " + rubbish);
        return true;
    }

    /// Everything again from nothing: the object directory goes, and then the
    /// whole program is compiled.
    ///
    /// **Not `Clean` followed by `Build` from the menu**, which would clear the
    /// output pane twice and lose what the clean said.
    void OnRebuild(MenuItem sender) => RebuildProgram();

    void OnRebuild(Control sender) => RebuildProgram();

    void RebuildProgram()
    {
        if (_isBuilding)
        {
            ShowStatus("A build is already running.");
            return;
        }

        if (!SaveBeforeBuilding())
            return;

        ClearOutput();

        if (_project != null && !CleanObjects())
            return;

        ShowStatus("Rebuilding...");
        StartCompiler(ComposeCompilerArguments(false), "Rebuilt.");
    }

    /// Stops the build that is running. Nothing to say when none is.
    ///
    /// **Killed rather than asked.** `Stop` is polite on Linux and cannot be
    /// on Windows -- `Process.Stop`'s own comment says so -- and a compiler
    /// halfway through writing an object file has nothing to tidy that a
    /// rebuild will not do better. What this leaves behind is a partial object
    /// directory, which is what Clean is for.
    void OnStop(MenuItem sender) => StopBuild();
    void OnStop(Control sender) => StopBuild();

    void StopBuild()
    {
        var running = _compilerProcess;
        if (running == null)
        {
            ShowStatus("Nothing is building.");
            return;
        }

        ((Running)running).Kill();
        ShowStatus("Stopping...");
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
    nuint DeleteDirectoryTree(String directory)
    {
        nuint removed = 0u;

        var inside = Directory.Directories(directory);
        if (inside.Ok)
        {
            foreach (var child in inside.Value)
                removed = removed + DeleteDirectoryTree(child);
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
            if (!SaveEditorTo(editor, ""))
                return false;
        }
        else if (editor.Contents.Edited && !editor.Contents.SaveFile(path))
        {
            ShowStatus("Could not write " + path);
            return false;
        }
        UpdateTabCaptionFor(editor);

        if (_project != null && !SaveEveryOtherTab(editor))
            return false;

        UpdateTitle();
        return true;
    }

    /// The edited tabs that are not the one in front. False if one refused to
    /// be written, naming it -- a build against a stale file on disk is worse
    /// than no build.
    bool SaveEveryOtherTab(CodeEditor except)
    {
        foreach (var tab in _openTabs)
        {
            var editor = tab.Editor;
            if (editor == except || !editor.Contents.Edited)
                continue;

            String path = editor.Contents.Location;
            if (path.ByteLength() == 0u)
                continue;

            if (!editor.Contents.SaveFile(path))
            {
                ShowStatus("Could not write " + path);
                return false;
            }
            UpdateTabCaption(tab);
        }
        return true;
    }

    /// Which configuration the picker is showing.
    Configuration SelectedConfiguration
    {
        get
        {
            if (_configuration.SelectedIndex == 1)
                return Configuration.Release;
            return Configuration.Debug;
        }
    }

    /// What the compiler is asked, which is the project when there is one.
    String[] ComposeCompilerArguments(bool thenRun)
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
        if (SelectedConfiguration == Configuration.Release)
        {
            arguments.Add("--no-debug");
            arguments.Add("-O2");
        }
        else
        {
            arguments.Add("-g");
            arguments.Add("-O0");

            // DWARF, because that is what this program's own debugger reads.
            // Without it a Windows build describes itself in CodeView, into a
            // .pdb, and F5 finds a binary with no lines in it.
            //
            // The cost is the .pdb, so Visual Studio, WinDbg, minidumps and
            // Windows Error Reporting see an unsymbolised binary. Release is
            // what to build when that matters.
            arguments.Add("--debug-format");
            arguments.Add("dwarf");
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
        ShowStatus(SelectedConfiguration == Configuration.Release
            ? "Release: optimised, and nothing for a debugger."
            : "Debug: unoptimised, and described to a debugger.");
    }

    /// Enables what can be done now and disables what cannot.
    ///
    /// Stop is the one that matters: a Stop that is always pressable is one
    /// that does nothing most of the time, and a toolbar is the place a person
    /// looks to find out whether anything is happening.
    void EnableBuildCommands()
    {
        _stopButton.Enabled = _isBuilding;
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
    void StartCompiler(String[] arguments, String success)
    {
        _isBuilding = true;
        EnableBuildCommands();
        String compiler = _compilerPath;

        var worker = new Thread(() =>
        {
            var opened = Open(compiler, arguments);
            if (opened.Fail)
            {
                Application.Post(() => OnCompilerFailedToStart());
                return;
            }

            var child = opened.Value;

            // Handed across rather than assigned, so that the field Cancel
            // reads is only ever written by the thread Cancel runs on.
            Application.Post(() => OnCompilerStarted(child));

            while (child.Read())
            {
                // Taken here and captured by value, so each post carries its
                // own piece: `Thread`'s doc comment is explicit that a closure
                // holds a copy of what it named, which is what makes a loop
                // that posts from inside itself safe.
                String errors = child.TakeErrors();
                String output = child.TakeOutput();
                Application.Post(() => OnCompilerOutput(errors, output));
            }

            int code = child.Wait().GetValueOrDefault(-1);
            Application.Post(() => OnCompilerExited(code, success));
        });
        worker.Detach();
    }

    /// The build's child, handed over by the worker that made it.
    void OnCompilerStarted(Running child)
    {
        _compilerProcess = child;
        EnableBuildCommands();
    }

    /// The compiler could not be started at all, back on the UI thread.
    void OnCompilerFailedToStart()
    {
        _isBuilding = false;
        _compilerProcess = null;
        EnableBuildCommands();
        ShowOutputLine("could not start '" + _compilerPath + "' -- is it on the path?");
        ShowStatus("The compiler could not be started.");
    }

    /// A piece of each stream, on the UI thread.
    ///
    /// The compiler writes diagnostics to the error stream and the program's
    /// own output to the other, so the two are read differently and shown in
    /// that order -- which is the order they were written in when the build
    /// fails, and near enough when it does not.
    void OnCompilerOutput(String errors, String output)
    {
        _errorTail = ShowCompleteLines(_errorTail + errors, true);
        _outputTail = ShowCompleteLines(_outputTail + output, false);
    }

    /// Shows every whole line in `text`, and answers the part after the last
    /// newline -- which is not a whole line yet, and waits for the rest.
    String ShowCompleteLines(String text, bool diagnostics)
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
                ShowOutputLine(line);
            else
                ShowRawLine(line);
        }
        return tidy.Substring((nuint)cut + 1u);
    }

    /// The child has exited and every byte of it has been handed over.
    void OnCompilerExited(int code, String success)
    {
        _isBuilding = false;
        _compilerProcess = null;
        EnableBuildCommands();

        // Whatever came without a newline after it is still a line, and this
        // is the last chance to say so: a compiler that does not end its
        // output with one would otherwise have its final diagnostic dropped.
        if (_errorTail.ByteLength() != 0u)
            ShowOutputLine(_errorTail);
        if (_outputTail.ByteLength() != 0u)
            ShowRawLine(_outputTail);
        _errorTail = "";
        _outputTail = "";

        ShowStatus(code == 0
            ? success
            : "Failed, with " + Standard.Text.FromInteger(code) + ".");
        _statusBar.SetPanelText(2, FormatErrorCount());
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
    void ShowOutputLine(String line)
    {
        var message = BuildMessage.Parse(line);
        _outputList.Add(message.ToDisplayText());
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
        _outputList.Clear();
        _errorList.Clear();
        _messages.Clear();
        _errorLines.Clear();
        _errorTail = "";
        _outputTail = "";
    }

    /// One diagnostic as a row, remembering which output line it came from so
    /// that double-clicking either list does the same thing.
    void AddError(BuildMessage message)
    {
        int row = _errorList.AddRow(message.IsError ? "!" : "?");
        _errorList.SetCell(row, 1, message.Code);
        _errorList.SetCell(row, 2, message.Message);
        _errorList.SetCell(row, 3, GetDisplayName(message.File));
        _errorList.SetCell(row, 4, message.HasPlace
                                ? Standard.Text.FromInteger(message.Line) : "");
        _errorLines.Add(_messages.Count - 1u);
    }

    /// A line that is not the compiler's, shown as it came.
    void ShowRawLine(String line)
    {
        _outputList.Add(line);
        _messages.Add(BuildMessage.CreateEmpty());
    }

    String FormatErrorCount()
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
        if (_outputList.SelectedIndex < 0)
            return;
        GoToMessage((nuint)_outputList.SelectedIndex);
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

        var tab = FindTab(message.File);
        if (tab == null)
        {
            if (!OpenFile(message.File))
            {
                ShowStatus("Could not open " + message.File);
                return;
            }
            tab = FindTab(message.File);
            if (tab == null)
                return;
        }

        var found = (EditorTab)tab;
        _tabs.SelectedIndex = found.Page.Index;
        found.Editor.MoveCaretTo(message.Line - 1u,
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
            ShowStatus("No project is open.");
            return;
        }

        var project = (ProjectFile)_project;
        var dialog = new ProjectDialog();
        dialog.LoadProject(project);
        dialog.ShowModal();

        if (!dialog.WasAccepted)
        {
            ShowStatus("Properties unchanged.");
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
            ShowOutputLine("refusing to write a project with no name or no sources");
            ShowStatus("Properties not saved.");
            return;
        }

        var written = Project.WriteProjectFile(project, _projectPath);
        if (!written.Ok)
        {
            ShowOutputLine(written.Error);
            ShowStatus("Could not write " + _projectPath);
            return;
        }

        if (!OpenProject(_projectPath))
            return;

        ShowStatus("Project saved.");
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
        var dialog = GetFindDialog();

        var now = Current;
        if (now != null)
        {
            var editor = (CodeEditor)now;
            String chosen = editor.SelectedText;
            if (chosen != "" && !chosen.Contains("\n"))
                dialog.Needle = chosen;
        }

        dialog.ShowForSearch();
    }

    /// Find Next without opening the window, which is what the menu item next
    /// to it is for: once a search is set up, repeating it should not need the
    /// dialog in front of the thing being searched.
    void OnFindNext(MenuItem sender)
    {
        var now = Current;
        if (now == null)
            return;

        var dialog = GetFindDialog();
        if (dialog.Needle == "")
        {
            OnFind(sender);
            return;
        }

        if (!((CodeEditor)now).FindNext(dialog.Needle, false, true))
            ShowStatus("No more matches for '" + dialog.Needle + "'.");
        else
            ShowStatus("");
    }

    /// The find window, made on the first ask.
    FindDialog GetFindDialog()
    {
        var made = _findDialog;
        if (made != null)
            return (FindDialog)made;

        // The closure is why this dialog holds no editor: it asks for whichever
        // one is in front at the moment a button is pressed, so changing tabs
        // with the window open searches the tab now being looked at.
        var dialog = new FindDialog(() => this.Current);
        _findDialog = dialog;
        return dialog;
    }

    // ------------------------------------------------------------- the panes

    void OnShowSolution(MenuItem sender) => ShowPane(Panes.Solution, "Solution Explorer");
    void OnShowErrors(MenuItem sender) => ShowPane(Panes.Errors, "Error List");
    void OnShowOutput(MenuItem sender) => ShowPane(Panes.Output, "Output");
    void OnShowLocals(MenuItem sender) => ShowPane(Panes.Locals, "Locals");
    void OnShowWatch(MenuItem sender) => ShowPane(Panes.Watch, "Watch");
    void OnShowThreads(MenuItem sender) => ShowPane(Panes.Threads, "Threads");

    /// Brings a pane forward by the name the layout file calls it, and keeps
    /// it in front when the first stop arrives.
    ///
    /// The command line's `--show`, which exists so that a pane can be
    /// photographed without somebody clicking its tab. Remembered as well as
    /// revealed because a stop brings its own pane forward, and it arrives
    /// after this.
    public bool ShowPaneNamed(String name)
    {
        if (!_dock.ShowPane(name))
        {
            ShowStatus("There is no pane called '" + name + "'.");
            return false;
        }
        _preferredPane = name;
        return true;
    }
    void OnShowCallStack(MenuItem sender) => ShowPane(Panes.CallStack, "Call Stack");
    void OnShowBreakpoints(MenuItem sender) => ShowPane(Panes.Breakpoints, "Breakpoints");
    void OnShowDebugOutput(MenuItem sender)
        => ShowPane(Panes.DebugOutput, "Debug Output");

    void ShowPane(String name, String title)
    {
        if (_dock.ShowPane(name))
            ShowStatus(title + ".");
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
        _layout = DockLayout.CreateDefault();
        if (SaveLayout(_layout, GetLayoutPath()))
            ShowStatus("Layout reset. It takes effect next time this starts.");
        else
            ShowStatus("Could not write " + GetLayoutPath() + ".");
    }

    /// Saves where everything is, on the way out.
    ///
    /// **`RememberWellSizes` first**, because a splitter drag sets its
    /// neighbour's width on the control and tells nobody -- there is no
    /// drag-finished event to have listened for, so the sizes are read back off
    /// the controls at the one moment they are wanted.
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
        if (!ConfirmCloseAllTabs())
        {
            args.Cancel = true;
            return;
        }

        _dock.RememberWellSizes();
        SaveLayout(_layout, GetLayoutPath());
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
        _treeEntries.Clear();

        if (_project == null)
        {
            var none = _tree.Add("No project open");
            none.Expand();
            return;
        }

        var project = (ProjectFile)_project;
        var root = _tree.Add(project.Name + " (" + project.Version + ")");

        foreach (var source in project.GetSourcesFor(ProjectFile.ThisPlatform))
        {
            String resolved = project.ResolvePath(source);
            var branch = root.Add(source);

            if (Directory.Exists(resolved))
            {
                AddTreeEntry(branch, resolved, true);
                AddFiles(branch, resolved);
            }
            else if (File.Exists(resolved))
            {
                AddTreeEntry(branch, resolved, false);
            }
            branch.Expand();
        }

        // References last and always, even when empty: a References node that
        // appears only sometimes is one people stop looking for.
        var references = root.Add("References");
        foreach (var dependency in project.Dependencies)
        {
            references.Add(dependency.Name + " -- " + dependency.ToDisplayText());
        }
        foreach (var library in project.GetLibrariesFor(ProjectFile.ThisPlatform))
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
                var below = branch.Add(GetDisplayName(inner));
                AddTreeEntry(below, inner, true);
                AddFiles(below, inner);
            }
        }

        var files = Directory.Files(folder);
        if (!files.Ok)
            return;

        foreach (var file in files.Value)
        {
            if (file.EndsWith(".sl"))
                AddTreeEntry(branch.Add(GetDisplayName(file)), file, false);
        }
    }

    /// Ties a node to the file or directory it stands for.
    ///
    /// A list searched rather than a map, for the reason `TreeView.Lookup`
    /// gives: a tree small enough to be usable is a tree small enough to walk,
    /// and a handful of files is a search that is over in microseconds.
    void AddTreeEntry(TreeNode node, String path, bool folder)
    {
        _treeEntries.Add(new TreeEntry(node, path, folder));
    }

    /// What a node stands for, or null for one that stands for nothing -- the
    /// project root, the References branch and everything under it.
    TreeEntry? FindTreeEntry(TreeNode node)
    {
        foreach (var entry in _treeEntries)
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

        var entry = FindTreeEntry((TreeNode)chosen);
        if (entry == null || ((TreeEntry)entry).IsFolder)
            return;

        OpenTreeEntry((TreeEntry)entry);
    }

    /// Opens what a node stands for.
    ///
    /// **Not named `Open`**, though that is what it does: `Standard.Process`
    /// now has a module-level `Open`, and CLAUDE.md records what happens to a
    /// method that shares a name with one of those -- it resolves to the free
    /// function inside a lambda body and to the method everywhere else, which
    /// is a bug that shows up in exactly one place and looks like nothing.
    void OpenTreeEntry(TreeEntry entry)
    {
        if (!OpenFile(entry.FullPath))
            ShowStatus("Could not read " + entry.FullPath);
    }

    // ------------------------------------------ the Solution Explorer's menu

    /// A context menu was asked for in the tree.
    ///
    /// **The node under the pointer, not the selected one.** Neither platform
    /// moves the selection on a right-click, so a menu built from
    /// `SelectedNode` would act on whatever was selected beforehand -- a
    /// Delete that removes a file nobody pointed at. `TreeView.NodeAt` answers
    /// what was actually clicked, and the selection is moved to follow it, so
    /// that what the menu is about is also what is highlighted while it is up.
    ///
    /// **Not `MouseUp` with the right button, which is what this was first
    /// written as and did not work.** A Win32 tree captures the mouse on the
    /// press and runs its own loop watching for a right-drag, swallowing the
    /// release that ends it -- so the first right-click raised nothing at all
    /// and only a second, which confuses the sequence, got a menu out of it.
    /// `Control.ContextMenu` is the notification that actually arrives, and it
    /// is the only one a keyboard can raise.
    void OnTreeContextMenu(Control sender, ContextMenuEventArgs args)
    {
        TreeEntry? target = null;
        Point where = args.Location;

        // Asked for from the keyboard, there is no pointer to hit-test, so it
        // is the selection that the menu is about -- and it belongs beside the
        // selected row rather than in the control's corner.
        var hit = args.FromKeyboard ? _tree.SelectedNode : _tree.NodeAt(where);

        if (hit != null)
        {
            _tree.SelectedNode = hit;
            target = FindTreeEntry((TreeNode)hit);
        }

        ShowTreeMenu(target, where);
        args.Handled = true;
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
        String folder = GetFolderFor(target);

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

        var shown = menu.Add(RevealVerb);
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
    String GetFolderFor(TreeEntry? target)
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
    String RevealVerb
    {
        get
        {
            #if WINDOWS
            return "Reveal in &Explorer";
            #else
            return "Open containing &folder";
            #endif
        }
    }

    void OnTreeOpen(MenuItem sender)
    {
        var target = _menuTarget;
        if (target != null && !((TreeEntry)target).IsFolder)
            OpenTreeEntry((TreeEntry)target);
    }

    void OnTreeRefresh(MenuItem sender)
    {
        ShowProjectTree();
        ShowStatus("Solution Explorer refreshed.");
    }

    void OnTreeAddFile(MenuItem sender)
    {
        String folder = GetFolderFor(_menuTarget);
        if (folder.ByteLength() == 0u)
            return;

        var asked = InputDialog.Ask("Add file", "Name of the new file:", "");
        if (asked is Some given)
            CreateSourceFile(folder, given.Value);
    }

    /// Makes the file, seeds it, and opens it.
    ///
    /// **The extension is added when it is missing**, because `.sl` is the only
    /// thing the compiler reads out of a source directory and a file without it
    /// would sit there being ignored.
    void CreateSourceFile(String folder, String typed)
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
        String named = ReadFolderModule(folder);
        if (named.ByteLength() != 0u)
            seed = "module " + named + ";\n\n";

        if (File.WriteAllText(path, seed) != IOError.None)
        {
            Application.Complain("Could not create " + path + ".", "Add file");
            return;
        }

        ShowProjectTree();
        OpenFile(path);
        ShowStatus("Added " + path);
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
    String ReadFolderModule(String folder)
    {
        var files = Directory.Files(folder);
        if (!files.Ok)
            return "";

        String found = "";
        foreach (var file in files.Value)
        {
            if (!file.EndsWith(".sl"))
                continue;

            String named = ReadFileModule(file);
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
    String ReadFileModule(String path)
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

        var asked = InputDialog.Ask("Rename", "New name:", GetDisplayName(entry.FullPath));
        if (asked is Some given)
            RenameTreeEntry(entry, given.Value);
    }

    void RenameTreeEntry(TreeEntry entry, String typed)
    {
        String name = typed.Trim();
        if (name.ByteLength() == 0u || name == GetDisplayName(entry.FullPath))
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
        var open = FindTab(entry.FullPath);
        if (open != null)
        {
            var tab = (EditorTab)open;
            tab.Editor.Contents.Location = path;
            UpdateTabCaption(tab);
            UpdateTitle();
        }

        ShowProjectTree();
        ShowStatus("Renamed to " + name);
    }

    void OnTreeDelete(MenuItem sender)
    {
        var target = _menuTarget;
        if (target == null)
            return;

        var entry = (TreeEntry)target;
        if (entry.IsFolder)
            return;

        if (!Application.Ask("Delete " + GetDisplayName(entry.FullPath) + "?\n\n"
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
        var open = FindTab(entry.FullPath);
        if (open != null)
            CloseTab((EditorTab)open);

        ShowProjectTree();
        ShowStatus("Deleted " + entry.FullPath);
    }

    void OnTreeReveal(MenuItem sender)
    {
        var target = _menuTarget;
        if (target != null)
            ShowInFileManager((TreeEntry)target);
    }

    /// Shows a file on disk, in whatever the platform's file manager is.
    ///
    /// **On a background thread**, for the same reason the build is: `Run` does
    /// not answer until the child has exited, and a file manager that takes a
    /// moment to come up would take this window with it. Nothing is done with
    /// the answer -- there is nothing useful to say about a file manager that
    /// declined to open, and the file is still right there in the tree.
    void ShowInFileManager(TreeEntry entry)
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
        ShowStatus("Showing " + entry.FullPath);
    }

    /// A row of the Error List was double-clicked, which goes to exactly where
    /// the same diagnostic in Output goes -- one path through one model.
    void OnErrorChosen(Control sender)
    {
        int row = _errorList.SelectedIndex;
        if (row < 0 || (nuint)row >= _errorLines.Count)
            return;

        GoToMessage(_errorLines[(nuint)row]);
    }

    // --------------------------------------------------------- debugging

    /// The function keys, which reach here because the editor passes on
    /// everything it does not use itself.
    ///
    /// `forms/` has no menu shortcuts, so this is where they live. They work
    /// while an editor has the focus, which is where a person pressing F10
    /// nearly always is.
    void OnEditorKey(Control sender, KeyEventArgs args)
    {
        switch (args.Key)
        {
            case Key.F5:
            {
                if (args.Control)
                    BuildProgram(true);
                else if (args.Shift)
                    StopDebugging();
                else
                    StartOrContinue();
                break;
            }

            case Key.F9:
                ToggleBreakpointAtCaret();
                break;

            case Key.F10:
                StepDebuggee(DebugCommand.StepOver);
                break;

            case Key.F11:
                StepDebuggee(args.Shift ? DebugCommand.StepOut : DebugCommand.StepIn);
                break;

            default:
                break;
        }
    }

    // ------------------------------------------------------- breakpoints

    /// Sets a breakpoint at `file:line` and starts debugging.
    ///
    /// For `--break`, which exists so that a stopped session can be
    /// photographed. It does what a person would do with F9 and F5, and adds
    /// nothing the menu cannot reach.
    public bool StartDebuggingAt(String where, String condition)
    {
        nuint colon = 0u;
        bool split = false;
        for (nuint i = where.ByteLength(); i > 0u; i--)
        {
            if (where.ByteAt(i - 1u) == (byte)58)
            {
                colon = i - 1u;
                split = true;
                break;
            }
        }
        if (!split)
        {
            ShowStatus("--break wants file:line.");
            return false;
        }

        String file = where.Substring(0u, colon);
        var number = Standard.Convert.ToInt(
            where.Substring(colon + 1u, where.ByteLength() - colon - 1u));
        uint line = number.Ok && number.Value > 0 ? (uint)number.Value : 0u;
        if (line == 0u)
        {
            ShowStatus("--break wants a line number.");
            return false;
        }

        if (FindTab(file) == null && FindTabMatching(file) == null)
            OpenFile(file);

        var tab = FindTabMatching(file);
        String path = tab == null ? file
                                  : ((EditorTab)tab).Editor.Contents.Location;
        var made = _breakpoints.ToggleBreakpoint(path, line);
        if (made != null && condition.ByteLength() != 0u)
            ((SourceBreakpoint)made).Condition = condition;

        ShowBreakpointList();
        RepaintEditors();
        return StartDebugging();
    }

    void OnToggleBreakpoint(MenuItem sender) => ToggleBreakpointAtCaret();

    void ToggleBreakpointAtCaret()
    {
        var now = Current;
        if (now == null)
            return;
        var editor = (CodeEditor)now;

        String path = editor.Contents.Location;
        if (path.ByteLength() == 0u)
        {
            ShowStatus("Save the file before setting a breakpoint in it.");
            return;
        }

        uint line = (uint)(editor.CaretPosition.Row + 1u);
        var made = _breakpoints.ToggleBreakpoint(path, line);
        ShowStatus(made == null
            ? "Breakpoint removed from line "
              + Standard.Text.FromInteger((long)line) + "."
            : "Breakpoint set on line "
              + Standard.Text.FromInteger((long)line) + ".");

        if (_session != null)
            ShowStatus("It takes effect when debugging is restarted.");

        ShowBreakpointList();
        editor.Invalidate();
    }

    /// A click in an editor's margin.
    void OnMarginClicked(Control sender, RowEventArgs args)
    {
        if (sender is CodeEditor editor)
        {
            String path = editor.Contents.Location;
            if (path.ByteLength() == 0u)
            {
                ShowStatus("Save the file before setting a breakpoint in it.");
                return;
            }

            // A click on a bound breakpoint's glyph removes that breakpoint,
            // not whatever was asked for on the line clicked: the glyph may
            // have moved.
            var shown = _breakpoints.FindShownAtLine(path, (uint)(args.Row + 1u));
            if (shown != null)
                _breakpoints.Remove((SourceBreakpoint)shown);
            else
                _breakpoints.ToggleBreakpoint(path, (uint)(args.Row + 1u));

            ShowBreakpointList();
            editor.Invalidate();
        }
    }

    /// Moves the breakpoints of an edited file.
    void ShiftBreakpoints(CodeEditor editor, nuint first, int delta)
    {
        String path = editor.Contents.Location;
        if (path.ByteLength() == 0u || !_breakpoints.HasBreakpointsIn(path))
            return;

        _breakpoints.ShiftBreakpoints(path, (uint)(first + 1u), delta);
        ShowBreakpointList();
        editor.Invalidate();
    }

    /// What the margin draws beside one line of one editor.
    LineMark GetMarkFor(CodeEditor editor, nuint row)
    {
        String path = editor.Contents.Location;
        if (path.ByteLength() == 0u || _breakpoints.IsEmpty)
            return LineMark.None;

        var found = _breakpoints.FindShownAtLine(path, (uint)(row + 1u));
        if (found == null)
            return LineMark.None;

        var one = (SourceBreakpoint)found;
        if (!one.Enabled)
            return LineMark.BreakpointDisabled;

        // Unbound only once a session has had the chance to bind it. Before
        // that, hollow would say the build found no code when nothing has been
        // built.
        if (_session != null && !one.IsBound)
            return LineMark.BreakpointUnbound;
        return LineMark.Breakpoint;
    }

    void OnClearBreakpoints(MenuItem sender)
    {
        if (_breakpoints.IsEmpty)
        {
            ShowStatus("There are no breakpoints.");
            return;
        }
        _breakpoints.Clear();
        ShowBreakpointList();
        RepaintEditors();
        ShowStatus("Breakpoints deleted.");
    }

    /// Goes to the breakpoint that was double-clicked.
    void OnBreakpointChosen(Control sender)
    {
        int row = _breakList.SelectedIndex;
        if (row < 0 || (nuint)row >= _breakpoints.Count)
            return;
        var one = _breakpoints.All[(nuint)row];
        ShowStatementAt(one.File, one.ShownLine);
    }

    void OnBreakpointContextMenu(Control sender, ContextMenuEventArgs args)
    {
        int row = _breakList.SelectedIndex;
        bool onOne = row >= 0 && (nuint)row < _breakpoints.Count;

        var menu = new PopupMenu();

        var asked = menu.Add("&Condition...");
        asked.Enabled = onOne;
        asked.Click += this.OnBreakpointCondition;

        var toggled = menu.Add("&Enabled");
        toggled.Enabled = onOne;
        toggled.Click += this.OnToggleBreakpointEnabled;

        menu.Add(MenuItem.Separator());

        var removed = menu.Add("&Delete");
        removed.Enabled = onOne;
        removed.Click += this.OnDeleteBreakpoint;

        var cleared = menu.Add("Delete &all");
        cleared.Enabled = !_breakpoints.IsEmpty;
        cleared.Click += this.OnClearBreakpoints;

        menu.Show(_breakList, args.Location);
        args.Handled = true;
    }

    /// Asks what has to hold for the selected breakpoint to stop.
    ///
    /// A blank answer takes the condition off, which is how somebody clears
    /// the box they typed it into. The expression is checked here as well as by
    /// the session, because a session may not exist yet.
    void OnBreakpointCondition(MenuItem sender)
    {
        int row = _breakList.SelectedIndex;
        if (row < 0 || (nuint)row >= _breakpoints.Count)
        {
            ShowStatus("Select a breakpoint first.");
            return;
        }

        var one = _breakpoints.All[(nuint)row];
        var asked = InputDialog.Ask("Breakpoint Condition",
                                    "Stop only when this holds:", one.Condition);
        if (asked is Some given)
        {
            String wanted = given.Value.Trim();
            if (wanted.ByteLength() != 0u)
            {
                var parsed = ParseWatch(wanted);
                if (parsed.Problem.ByteLength() != 0u)
                {
                    Application.Complain("That is not a condition: "
                                         + parsed.Problem,
                                         "Breakpoint Condition");
                    return;
                }
                if (!parsed.IsCondition)
                {
                    Application.Complain(
                        "A condition has to compare two things, as 'i == 3'"
                        + " does.", "Breakpoint Condition");
                    return;
                }
            }

            one.Condition = wanted;
            ShowBreakpointList();
            ShowStatus(wanted.ByteLength() == 0u
                ? "The breakpoint will stop every time."
                : "The breakpoint will stop when " + wanted + ".");
            ReportConditionTakesEffect();
        }
    }

    /// A condition is read where a breakpoint is planted, which is when a
    /// session starts.
    void ReportConditionTakesEffect()
    {
        if (_session != null)
            AppendDebugOutput("Breakpoint conditions take effect next time you start.");
    }

    void OnToggleBreakpointEnabled(MenuItem sender)
    {
        int row = _breakList.SelectedIndex;
        if (row < 0 || (nuint)row >= _breakpoints.Count)
            return;

        var one = _breakpoints.All[(nuint)row];
        one.Enabled = !one.Enabled;
        ShowBreakpointList();
        RepaintEditors();
    }

    void OnDeleteBreakpoint(MenuItem sender)
    {
        int row = _breakList.SelectedIndex;
        if (row < 0 || (nuint)row >= _breakpoints.Count)
            return;

        var one = _breakpoints.All[(nuint)row];
        _breakpoints.ToggleBreakpoint(one.File, one.Line);
        ShowBreakpointList();
        RepaintEditors();
    }

    void ShowBreakpointList()
    {
        _breakList.Clear();
        for (nuint i = 0u; i < _breakpoints.Count; i++)
        {
            var one = _breakpoints.All[i];
            int row = _breakList.AddRow(one.Enabled ? "*" : "o");
            _breakList.SetCell(row, 1, one.ToDisplayText());
            _breakList.SetCell(row, 2, FormatBreakpointState(one));
        }
    }

    String FormatBreakpointState(SourceBreakpoint one)
    {
        if (!one.Enabled)
            return "disabled";
        if (_session == null)
            return "pending";
        return one.IsBound ? "bound" : "no code";
    }

    // --------------------------------------------------------- run control

    void OnStartDebugging(MenuItem sender) => StartOrContinue();
    void OnStartDebugging(Control sender) => StartOrContinue();

    /// F5: start if nothing is running, continue if something is stopped.
    void StartOrContinue()
    {
        var running = _session;
        if (running != null && ((DebugSession)running).IsStopped)
        {
            ContinueDebugging();
            return;
        }
        if (running != null)
        {
            ShowStatus("It is already running. Break to stop it.");
            return;
        }
        StartDebugging();
    }

    void OnContinue(MenuItem sender) => ContinueDebugging();

    void ContinueDebugging()
    {
        var running = _session;
        if (running == null || !((DebugSession)running).IsStopped)
        {
            ShowStatus("Nothing is stopped.");
            return;
        }
        ClearStopMarks();
        ((DebugSession)running).ContinueExecution();
        ShowRunning("Running...");
    }

    void OnStepInto(MenuItem sender) => StepDebuggee(DebugCommand.StepIn);
    void OnStepInto(Control sender) => StepDebuggee(DebugCommand.StepIn);
    void OnStepOver(MenuItem sender) => StepDebuggee(DebugCommand.StepOver);
    void OnStepOver(Control sender) => StepDebuggee(DebugCommand.StepOver);
    void OnStepOut(MenuItem sender) => StepDebuggee(DebugCommand.StepOut);
    void OnStepOut(Control sender) => StepDebuggee(DebugCommand.StepOut);

    void StepDebuggee(DebugCommand how)
    {
        var running = _session;
        if (running == null || !((DebugSession)running).IsStopped)
        {
            ShowStatus("Nothing is stopped.");
            return;
        }

        var session = (DebugSession)running;
        switch (how)
        {
            case DebugCommand.StepIn: session.StepIn(); break;
            case DebugCommand.StepOut: session.StepOut(); break;
            default: session.StepOver(); break;
        }

        ClearStopMarks();
        ShowRunning("Stepping...");
    }

    void OnBreakAll(MenuItem sender) => BreakAll();
    void OnBreakAll(Control sender) => BreakAll();

    void BreakAll()
    {
        var running = _session;
        if (running == null || ((DebugSession)running).State != RunState.Running)
        {
            ShowStatus("Nothing is running.");
            return;
        }
        if (((DebugSession)running).RequestBreak())
            ShowStatus("Breaking...");
        else
            ShowStatus("It could not be interrupted.");
    }

    void OnStopDebugging(MenuItem sender) => StopDebugging();
    void OnStopDebugging(Control sender) => StopDebugging();

    void StopDebugging()
    {
        var running = _session;
        if (running == null)
        {
            ShowStatus("Nothing is being debugged.");
            return;
        }
        ((DebugSession)running).Stop();
        ShowStatus("Stopping...");
    }

    /// Stops what is running and starts it again with the same breakpoints.
    ///
    /// The breakpoints survive because they live in the store rather than in
    /// the session. So do the open tabs and the layout.
    void OnRestartDebugging(MenuItem sender) => RestartDebugging();
    void OnRestartDebugging(Control sender) => RestartDebugging();

    void RestartDebugging()
    {
        var running = _session;
        if (running != null)
        {
            // Synchronous would mean waiting on the session's thread from the
            // one that paints. `Stop` is asynchronous, so the restart is the
            // next thing the person does.
            ((DebugSession)running).Stop();
            ShowStatus("Stopping. Press F5 to start again.");
            return;
        }
        StartDebugging();
    }

    /// Launches the built program under the debugger.
    bool StartDebugging()
    {
        if (_isBuilding)
        {
            ShowStatus("A build is running.");
            return false;
        }

        String program = DebuggeePath;
        if (program.ByteLength() == 0u)
        {
            ShowStatus("Open a project to debug. A loose file has no output path.");
            return false;
        }

        if (!Standard.File.Exists(program))
        {
            ShowStatus("Build it first: " + program + " is not there.");
            return false;
        }

        if (SelectedConfiguration == Configuration.Release)
            AppendDebugOutput("note: Release is optimised and has no debug information."
                      + " Switch to Debug and rebuild to step through it.");

        _breakpoints.ClearBindings();
        _lastStop = null;
        _selectedFrame = 0u;
        _isFirstStop = true;
        _debugOutput.Clear();
        ClearDebugPanes();

        var session = new DebugSession((taken) => this.OnProgramStopped(taken),
                                       (line) => AppendDebugOutput(line),
                                       (file, line, bound)
                                           => OnBreakpointBound(file, line, bound));
        _session = session;

        if (!session.Start(program, _breakpoints.All, _watches))
        {
            _session = null;
            ShowStatus("The session would not start.");
            return false;
        }

        AppendDebugOutput("Starting " + program);
        ShowRunning("Debugging...");
        _dock.ShowPane(Panes.DebugOutput);
        return true;
    }

    /// Where the program to debug is.
    ///
    /// Empty when there is no project. A loose file is compiled to a path the
    /// compiler chooses and this window never learns.
    String DebuggeePath
    {
        get
        {
            if (_project == null)
                return "";
            return ((ProjectFile)_project).OutputPath;
        }
    }

    // ------------------------------------------- what comes back from a stop

    /// One line from the session or from the program.
    void AppendDebugOutput(String line)
    {
        _debugOutput.Add(line);
        if (_debugOutput.Count > 0u)
            _debugOutput.SelectedIndex = (int)_debugOutput.Count - 1;
    }

    /// A breakpoint's binding, once a session has looked for code for it.
    void OnBreakpointBound(String file, uint line, uint bound)
    {
        _breakpoints.RecordBinding(file, line, bound);
        ShowBreakpointList();
        RepaintEditors();
    }

    /// The program stopped, or ended.
    ///
    /// A method here MUST NOT be named `Stopped`: `DebugEvent.Stopped` is a
    /// case constructor of the engine's and is in scope everywhere, and inside
    /// a lambda body it wins. See `docs/style.md` §1.5.
    void OnProgramStopped(Snapshot taken)
    {
        _lastStop = taken;
        _selectedFrame = 0u;

        if (taken.State == RunState.Ended)
        {
            OnSessionEnded(taken);
            return;
        }

        ShowLocals(taken);
        ShowWatches(taken);
        ShowCallStack(taken);
        ShowThreads(taken);
        EnableDebugCommands();

        // One pane comes forward on the first stop and on none after it. Every
        // stop would take the pane away from whoever had chosen another.
        //
        // Watch when there are watches, because a watch is there on purpose
        // and Locals is what to show someone who has not said what they are
        // interested in.
        if (_isFirstStop)
        {
            _isFirstStop = false;
            _dock.ShowPane(_preferredPane.ByteLength() != 0u
                         ? _preferredPane
                         : (_watches.IsEmpty ? Panes.Locals : Panes.Watch));
        }

        if (taken.HasSource)
            ShowStatementAt(taken.File, taken.Line);
        RepaintEditors();

        switch (taken.Kind)
        {
            case StopKind.Breakpoint:
                ShowStatus("Stopped at " + FormatStopLocation(taken) + ".");
                break;

            case StopKind.Paused:
                ShowStatus("Broken at " + FormatStopLocation(taken) + ".");
                break;

            case StopKind.Fault:
            {
                String what = "Faulted (0x"
                            + FormatHexadecimal((ulong)taken.FaultCode)
                            + ") at " + FormatStopLocation(taken) + ".";
                ShowStatus(what);
                AppendDebugOutput(what);
                break;
            }

            default:
                ShowStatus(FormatStopLocation(taken));
                break;
        }
    }

    /// The session is over.
    void OnSessionEnded(Snapshot taken)
    {
        String note = "Exited with "
                    + Standard.Text.FromInteger((long)taken.ExitCode) + ".";
        AppendDebugOutput(note);
        ShowStatus(note);

        _session = null;
        _lastStop = null;
        _breakpoints.ClearBindings();
        ClearDebugPanes();
        ClearStopMarks();
        ShowBreakpointList();
        EnableDebugCommands();
        RepaintEditors();
    }

    String FormatStopLocation(Snapshot taken)
    {
        String where = taken.HasSource
            ? GetDisplayName(taken.File) + ":"
              + Standard.Text.FromInteger((long)taken.Line)
            : "0x" + FormatHexadecimal((ulong)taken.Address);
        return taken.Function.ByteLength() == 0u
            ? where : where + " in " + taken.Function;
    }

    void ShowLocals(Snapshot taken)
    {
        _localsList.Clear();
        for (nuint i = 0u; i < taken.Locals.Count; i++)
        {
            var one = taken.Locals[i];
            int row = _localsList.AddRow(one.Name);
            _localsList.SetCell(row, 1, one.Value);
            _localsList.SetCell(row, 2, one.TypeName
                                    + (one.IsParameter ? "  (parameter)" : ""));
        }
    }

    /// The watches a stop answered, one row each. See `WatchLine`.
    void ShowWatches(Snapshot taken)
    {
        _watchList.Clear();
        for (nuint i = 0u; i < taken.Watches.Count; i++)
        {
            var one = taken.Watches[i];
            int row = _watchList.AddRow(one.Expression);
            _watchList.SetCell(row, 1, one.Value);
            _watchList.SetCell(row, 2, one.TypeName);
        }
    }

    /// The watches with no session behind them: the expressions, and nothing
    /// to say about any of them. A watch added before the program starts is
    /// visibly there, and the list survives the program exiting.
    void ShowWatchNames()
    {
        _watchList.Clear();
        for (nuint i = 0u; i < _watches.Count; i++)
        {
            int row = _watchList.AddRow(_watches[i]);
            _watchList.SetCell(row, 1, _session == null
                                       ? "(not running)" : "(running)");
            _watchList.SetCell(row, 2, "");
        }
    }

    /// Adds a watch, and answers why it was not added.
    ///
    /// It MUST answer rather than show: a dialog raised from here reaches the
    /// self test, which then waits for somebody to press OK.
    ///
    /// The expression is checked here as well as by the session, because a
    /// session may not exist yet.
    String AddWatch(String expression)
    {
        String wanted = expression.Trim();
        if (wanted.ByteLength() == 0u)
            return "there is nothing here to watch";

        String problem = ParseWatch(wanted).Problem;
        if (problem.ByteLength() != 0u)
            return problem;

        _watches.Add(wanted);

        var running = _session;
        if (running != null && ((DebugSession)running).IsStopped)
            ((DebugSession)running).AddWatch(wanted);
        else
            ShowWatchNames();

        _dock.ShowPane(Panes.Watch);
        return "";
    }

    /// Asks for an expression and adds it, saying why when it cannot.
    ///
    /// Blank is not a refusal worth a dialog: someone who pressed OK on an
    /// empty box has already changed their mind.
    void AskForWatch(String initial)
    {
        var asked = InputDialog.Ask("Add Watch", "Expression to watch:", initial);
        if (asked is Some given)
        {
            if (given.Value.Trim().ByteLength() == 0u)
                return;

            String problem = AddWatch(given.Value);
            if (problem.ByteLength() != 0u)
                Application.Complain("That is not a watch expression: " + problem,
                                     "Add Watch");
        }
    }

    void OnAddWatch(MenuItem sender) => AskForWatch("");

    /// Adds a watch from outside the window -- the command line's `--watch`.
    ///
    /// Answers whether it was kept, and says why on the status line when it
    /// was not: there is nobody at a dialog when a program is being started by
    /// a script.
    public bool TryAddWatch(String expression)
    {
        String problem = AddWatch(expression);
        if (problem.ByteLength() == 0u)
            return true;
        ShowStatus(expression + ": " + problem);
        return false;
    }

    /// Double-clicking a row edits the expression, which is how a watch is
    /// corrected without deleting it and typing the whole of it again.
    void OnWatchChosen(Control sender)
    {
        int row = _watchList.SelectedIndex;
        if (row < 0 || (nuint)row >= _watches.Count)
            return;

        String was = _watches[(nuint)row];
        RemoveWatchAt((nuint)row);
        AskForWatch(was);
    }

    void OnWatchContextMenu(Control sender, ContextMenuEventArgs args)
    {
        var menu = new PopupMenu();
        menu.Add("&Add watch...").Click += this.OnAddWatch;

        int row = _watchList.SelectedIndex;
        bool onOne = row >= 0 && (nuint)row < _watches.Count;

        var removed = menu.Add("&Delete watch");
        removed.Enabled = onOne;
        removed.Click += this.OnDeleteWatch;

        var cleared = menu.Add("Delete &all watches");
        cleared.Enabled = !_watches.IsEmpty;
        cleared.Click += this.OnClearWatches;

        menu.Show(_watchList, args.Location);
        args.Handled = true;
    }

    void OnDeleteWatch(MenuItem sender)
    {
        int row = _watchList.SelectedIndex;
        if (row >= 0)
            RemoveWatchAt((nuint)row);
    }

    void OnClearWatches(MenuItem sender)
    {
        // Backwards, so each removal leaves the rows below it where the
        // session still expects them.
        for (nuint i = _watches.Count; i > 0u; i--)
            RemoveWatchAt(i - 1u);
    }

    /// Stops watching one row, here and in the session both.
    void RemoveWatchAt(nuint row)
    {
        if (row >= _watches.Count)
            return;

        _watches.RemoveAt(row);

        var running = _session;
        if (running != null && ((DebugSession)running).IsStopped)
            ((DebugSession)running).RemoveWatchAt(row);
        else
            ShowWatchNames();
    }

    /// Every thread of the program, and where each of them is.
    ///
    /// A thread the platform will not let a debugger read keeps its row and
    /// says so: a program with four threads has four, whatever this can see of
    /// them.
    void ShowThreads(Snapshot taken)
    {
        _threadList.Clear();
        for (nuint i = 0u; i < taken.Threads.Count; i++)
        {
            var one = taken.Threads[i];
            int row = _threadList.AddRow(one.IsCurrent ? ">" : "");
            _threadList.SetCell(row, 1, Standard.Text.FromInteger((long)one.Id));
            _threadList.SetCell(row, 2, one.Function.ByteLength() != 0u
                                        ? one.Function : "??");
            _threadList.SetCell(row, 3, FormatThreadLocation(one));
        }
    }

    String FormatThreadLocation(ThreadLine one)
    {
        if (!one.CanRead)
            return "not traced";
        if (one.HasSource)
            return GetDisplayName(one.File) + ", line "
                 + Standard.Text.FromInteger((long)one.Line);
        return "0x" + FormatHexadecimal((ulong)one.Pc);
    }

    /// A thread was double-clicked: show where it is.
    ///
    /// Only the source position changes. Locals and the Call Stack still show
    /// the thread the stop was reported on -- switching which thread those are
    /// about means reading another one, and only the session's own thread may
    /// do that.
    void OnThreadChosen(Control sender)
    {
        var taken = _lastStop;
        if (taken == null)
            return;

        int row = _threadList.SelectedIndex;
        if (row < 0 || (nuint)row >= ((Snapshot)taken).Threads.Count)
            return;

        var one = ((Snapshot)taken).Threads[(nuint)row];
        if (!one.HasSource)
        {
            ShowStatus(one.CanRead ? "That thread is not in code this program was built"
                              + " from."
                            : "That thread cannot be read.");
            return;
        }

        ShowStatementAt(one.File, one.Line);
        RepaintEditors();
    }

    void ShowCallStack(Snapshot taken)
    {
        _callStackList.Clear();
        for (nuint i = 0u; i < taken.Frames.Count; i++)
        {
            var frame = taken.Frames[i];
            int row = _callStackList.AddRow(i == 0u ? ">" : "");
            _callStackList.SetCell(row, 1, frame.Function.ByteLength() != 0u
                                   ? frame.Function : "??");
            _callStackList.SetCell(row, 2, frame.HasSource
                ? GetDisplayName(frame.File) + ", line "
                  + Standard.Text.FromInteger((long)frame.Line)
                : "0x" + FormatHexadecimal((ulong)frame.Pc));
        }
        if (!taken.Frames.IsEmpty)
            _callStackList.SelectedIndex = 0;
    }

    /// A frame was double-clicked: show where it is.
    ///
    /// Only the source position changes. The Locals pane still shows frame
    /// zero, because reading another frame's variables needs its own frame
    /// base, and that MUST come from the session's thread.
    void OnFrameChosen(Control sender)
    {
        var taken = _lastStop;
        if (taken == null)
            return;

        int row = _callStackList.SelectedIndex;
        if (row < 0 || (nuint)row >= ((Snapshot)taken).Frames.Count)
            return;

        _selectedFrame = (nuint)row;
        var frame = ((Snapshot)taken).Frames[_selectedFrame];
        if (!frame.HasSource)
        {
            ShowStatus("That frame has no source.");
            return;
        }

        ShowStatementAt(frame.File, frame.Line);
        RepaintEditors();
    }

    /// The pointer came to rest over a word: say what it is worth.
    ///
    /// **Answered out of the stop already in hand**, never by asking the
    /// engine: the thread that may read a debuggee is the session's, and it is
    /// busy. `Snapshot.Locals` was read while the program was stopped and
    /// nothing has run since, so a local is already here -- and only a local:
    /// a field or an element would want an expression, and the pointer has not
    /// selected one.
    ///
    /// In the tip and on the status line both. The tip is where a person looks
    /// and waits half a second for; the status line is there at once and stays
    /// while the pointer is moved away to read it.
    void OnHovered(String word)
    {
        if (_lastStop == null || word.ByteLength() == 0u)
        {
            ShowHover("");
            return;
        }

        var stop = (Snapshot)_lastStop;
        for (nuint i = 0u; i < stop.Locals.Count; i++)
        {
            var one = stop.Locals[i];
            if (one.Name != word)
                continue;
            ShowHover(one.Name + " = " + one.Value + "   (" + one.TypeName + ")");
            return;
        }

        ShowHover("");
    }

    void ClearDebugPanes()
    {
        _localsList.Clear();
        _callStackList.Clear();
        _threadList.Clear();
        ShowWatchNames();
    }

    /// Takes the current-statement highlight off every tab.
    void ClearStopMarks()
    {
        foreach (var tab in _openTabs)
            tab.Editor.ClearStatement();
    }

    void RepaintEditors()
    {
        foreach (var tab in _openTabs)
            tab.Editor.Invalidate();
    }

    /// Opens a file if it is not open, and puts the statement mark on a line.
    void ShowStatementAt(String file, uint line)
    {
        var tab = FindTab(file);
        if (tab == null)
        {
            // The debugger's path may be spelled differently from the editor's:
            // a compiler joining a directory to a file name mixes separators.
            tab = FindTabMatching(file);
        }
        if (tab == null)
        {
            if (!OpenFile(file))
            {
                ShowStatus("Could not open " + file);
                return;
            }
            tab = FindTab(file);
            if (tab == null)
                return;
        }

        var found = (EditorTab)tab;
        _tabs.SelectedIndex = found.Page.Index;
        found.Editor.ShowStatementAt(line - 1u, _selectedFrame == 0u);
        OnCaretMoved(this);
    }

    /// The tab holding a file, compared the way the debugger compares paths.
    EditorTab? FindTabMatching(String path)
    {
        foreach (var tab in _openTabs)
        {
            String open = tab.Editor.Contents.Location;
            if (open.ByteLength() != 0u && IsTheSameSourceFile(open, path))
                return tab;
        }
        return null;
    }

    /// Enables what can be done now.
    void EnableDebugCommands()
    {
        var running = _session;
        bool live = running != null;
        bool stopped = live && ((DebugSession)running).IsStopped;

        _startButton.Enabled = !live || stopped;
        _pauseButton.Enabled = live && !stopped;
        _stopDebugButton.Enabled = live;
        _stepIntoButton.Enabled = stopped;
        _stepOverButton.Enabled = stopped;
        _stepOutButton.Enabled = stopped;
    }

    /// The program is on the move, so nothing may be read from it.
    void ShowRunning(String what)
    {
        ShowStatus(what);
        ClearDebugPanes();
        EnableDebugCommands();
    }

    // -------------------------------------------------------------- the rest

    void OnCaretMoved(Control sender)
    {
        var now = Current;
        if (now == null)
            return;
        var editor = (CodeEditor)now;
        var at = editor.CaretPosition;
        String line = editor.Contents.GetLineText(at.Row);
        _statusBar.SetPanelText(3,
            "Ln " + Standard.Text.FromInteger(at.Row + 1u)
          + ", Col " + Standard.Text.FromInteger(editor.GetColumnOfOffset(line, at.Column) + 1u));
    }

    void OnEdited(Control sender)
    {
        if (sender is CodeEditor editor)
            UpdateTabCaptionFor(editor);
        UpdateTitle();
    }

    /// The title says what is open and whether it has been changed, which is
    /// the one piece of state a person checks without being told to.
    void UpdateTitle()
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
        String project = ProjectName;
        String lead = project == "" ? "" : project + " -- ";

        Text = (editor.Contents.Edited ? "* " : "") + lead + GetDisplayName(path) + " -- Stainless";
        _statusBar.SetPanelText(0, path.ByteLength() == 0u ? "Not saved" : path);
    }

    void ShowStatus(String what) => _statusBar.SetPanelText(1, what);

    /// What the pointer is over, or "" to clear it.
    ///
    /// The status bar's own panel, so a hover does not take away what the
    /// window last said -- and the editor's tip, which is where somebody
    /// pointing at a name is looking.
    void ShowHover(String what)
    {
        _statusBar.SetPanelText(4, what);

        var now = Current;
        if (now != null)
            ((CodeEditor)now).ToolTip = what;
    }

    /// Whether a list of arguments holds one.
    static bool ContainsArgument(String[] arguments, String wanted)
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
    public bool RunSelfTest()
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

        editor.TypeText("int Main() { return 0; }");
        if (editor.Contents.GetLineText(0u) != "int Main() { return 0; }")
        {
            Console.WriteLine("FAIL: typing");
            ok = false;
        }
        if (editor.Contents.GetLine(0u).Tokens.Count == 0u)
        {
            Console.WriteLine("FAIL: the line did not lex");
            ok = false;
        }

        editor.TypeText("\nint Second() { return 1; }");
        if (editor.Contents.LineCount != 2u
            || editor.Contents.GetLine(1u).Tokens.Count == 0u)
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
        editor.MoveCaretTo(lines - 1u, editor.Contents.GetLineLength(lines - 1u));
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
        ResizeText(2);
        if (editor.FontSize != before + 2)
        {
            Console.WriteLine("FAIL: the text did not resize");
            ok = false;
        }
        ResizeText(-2);

        // A second tab, brought to the front, then closed again.
        nuint had = _openTabs.Count;
        OpenBlankTab();
        if (_openTabs.Count != had + 1u)
        {
            Console.WriteLine("FAIL: a new tab did not appear");
            ok = false;
        }
        if (_tabs.SelectedIndex != (int)(_openTabs.Count - 1u))
        {
            Console.WriteLine("FAIL: the new tab did not come to the front");
            ok = false;
        }

        int at = _tabs.SelectedIndex;
        CloseTab(_openTabs[(nuint)at]);
        if (_openTabs.Count != had)
        {
            Console.WriteLine("FAIL: closing a tab did not remove it");
            ok = false;
        }

        // Closing them all leaves one empty tab rather than none.
        while (_openTabs.Count > 1u)
            CloseTab(_openTabs[0u]);
        CloseTab(_openTabs[0u]);
        if (_openTabs.Count != 1u)
        {
            Console.WriteLine("FAIL: closing every tab left "
                              + Standard.Text.FromInteger(_openTabs.Count));
            ok = false;
        }

        // Several files at once, which is what the command line does and what
        // a single open never exercised.
        while (_openTabs.Count > 1u)
            CloseTab(_openTabs[0u]);
        OpenFile("samples/shapes.sl");
        OpenFile("samples/hello.sl");
        OpenFile("samples/json.sl");
        Application.DoEvents();
        ShowFirstTab();
        Application.DoEvents();

        // Only checkable from the repository root, since the paths are
        // relative; said rather than skipped silently, so a run that proved
        // less than it looks like says so.
        if (_openTabs.Count != 3u)
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

            pad.TypeText("hello");
            if (pad.Contents.GetLineText(0u) != "hello")
            {
                Console.WriteLine("FAIL: undo setup");
                ok = false;
            }

            // Typing a word is one undo and not five, which is the whole
            // reason the stack coalesces.
            pad.Undo();
            if (pad.Contents.GetLineText(0u) != "")
            {
                Console.WriteLine("FAIL: one undo did not take back a typed word, leaving '"
                                  + pad.Contents.GetLineText(0u) + "'");
                ok = false;
            }

            pad.Redo();
            if (pad.Contents.GetLineText(0u) != "hello")
            {
                Console.WriteLine("FAIL: redo did not put it back");
                ok = false;
            }

            // A newline ends a run, so what follows undoes on its own.
            // Three calls, because that is what three keystrokes are --
            // one Type of the whole string is one insertion and rightly
            // one undo.
            pad.TypeText("\n");
            pad.TypeText("w");
            pad.TypeText("orld");
            pad.Undo();
            if (pad.Contents.LineCount != 2u || pad.Contents.GetLineText(1u) != "")
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
            if (pad.Contents.GetLineText(0u) != "" || pad.Contents.LineCount != 1u)
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
            pad.TypeText("var total = count + 1;   // sum");

            // Inside a word takes the word and not the space after it.
            pad.MoveCaretTo(0u, 5u);
            pad.SelectWord();
            if (pad.SelectedText != "total")
            {
                Console.WriteLine("FAIL: double-click on a word selected '"
                                  + pad.SelectedText + "'");
                ok = false;
            }

            // At the first byte of a word, which is where a click usually lands.
            pad.MoveCaretTo(0u, 0u);
            pad.SelectWord();
            if (pad.SelectedText != "var")
            {
                Console.WriteLine("FAIL: at the start of a word it selected '"
                                  + pad.SelectedText + "'");
                ok = false;
            }

            // A run of spaces is its own run, and stops at the word either side.
            pad.MoveCaretTo(0u, 23u);
            pad.SelectWord();
            if (pad.SelectedText != "   ")
            {
                Console.WriteLine("FAIL: on spaces it selected '"
                                  + pad.SelectedText + "' rather than three spaces");
                ok = false;
            }

            // Punctuation is the third run, so `//` comes out whole rather than
            // one slash -- which is the case two runs would get wrong.
            pad.MoveCaretTo(0u, 26u);
            pad.SelectWord();
            if (pad.SelectedText != "//")
            {
                Console.WriteLine("FAIL: on punctuation it selected '"
                                  + pad.SelectedText + "'");
                ok = false;
            }

            // What the pointer is over, which a debugger asks about. Only a
            // word: a run of spaces or of punctuation is not a name, and
            // answering one has a debugger looking up `//`.
            if (pad.GetWordAt(Position.Create(0u, 5u)) != "total"
                || pad.GetWordAt(Position.Create(0u, 4u)) != "total"
                || pad.GetWordAt(Position.Create(0u, 0u)) != "var")
            {
                Console.WriteLine("FAIL: the word under the pointer was read wrongly");
                ok = false;
            }

            if (pad.GetWordAt(Position.Create(0u, 23u)).ByteLength() != 0u
                || pad.GetWordAt(Position.Create(0u, 26u)).ByteLength() != 0u)
            {
                Console.WriteLine("FAIL: spaces or punctuation were read as a word");
                ok = false;
            }

            // Past the end of the line, where the pointer spends most of its
            // time, and past the last line. Neither is a word and neither may
            // fault.
            if (pad.GetWordAt(Position.Create(0u, 200u)).ByteLength() != 0u
                || pad.GetWordAt(Position.Create(50u, 0u)).ByteLength() != 0u)
            {
                Console.WriteLine("FAIL: a point off the text was read as a word");
                ok = false;
            }

            // Past the end of the line, where a click in the empty space to the
            // right of the text lands. It must select the last run, not reach
            // past the line and not fault.
            pad.MoveCaretTo(0u, 200u);
            pad.SelectWord();
            if (pad.SelectedText != "sum")
            {
                Console.WriteLine("FAIL: past the end of the line it selected '"
                                  + pad.SelectedText + "'");
                ok = false;
            }

            // An empty line has no run at all, and must not select anything or
            // walk off the front of a zero-length string.
            pad.TypeText("\n");
            pad.SelectWord();
            if (pad.HasSelection)
            {
                Console.WriteLine("FAIL: an empty line selected something");
                ok = false;
            }

            CloseTab(_openTabs[_openTabs.Count - 1u]);
            Application.DoEvents();
        }

        // The three list fields the properties dialog edits as one line each.
        // A trailing space must not become an entry that names nothing, which
        // is what would send the compiler looking for a directory called "".
        {
            String[] round = ProjectDialog.SplitWords(
                ProjectDialog.JoinWords(["src", "../forms/src", "vendor"]));
            if (round.Length != 3u || round[0u] != "src"
                || round[1u] != "../forms/src" || round[2u] != "vendor")
            {
                Console.WriteLine("FAIL: a source list did not survive the round trip");
                ok = false;
            }

            if (ProjectDialog.SplitWords("  a   b  ").Length != 2u)
            {
                Console.WriteLine("FAIL: runs of spaces made empty entries");
                ok = false;
            }
            if (ProjectDialog.SplitWords("   ").Length != 0u)
            {
                Console.WriteLine("FAIL: a field of spaces was not empty");
                ok = false;
            }
            if (ProjectDialog.JoinWords([]) != "")
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
            pad.TypeText("one two one\nthree ONE four\none");

            pad.MoveCaretTo(0u, 0u);
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
            pad.MoveCaretTo(1u, 0u);
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
            pad.MoveCaretTo(0u, 0u);
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
            if (pad.Contents.GetLineText(0u) != "one 2 one")
            {
                Console.WriteLine("FAIL: after replace line one reads '"
                                  + pad.Contents.GetLineText(0u) + "'");
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
            if (pad.Contents.GetLineText(0u) != "1 2 1"
                || pad.Contents.GetLineText(1u) != "three ONE four"
                || pad.Contents.GetLineText(2u) != "1")
            {
                Console.WriteLine("FAIL: replace all left '" + pad.Contents.GetLineText(0u)
                                  + "' / '" + pad.Contents.GetLineText(1u)
                                  + "' / '" + pad.Contents.GetLineText(2u) + "'");
                ok = false;
            }

            // The replacement containing the needle is the case that never
            // terminates if the sweep wraps. It must replace each once.
            nuint grown = pad.ReplaceAll("1", "11", true);
            if (grown != 3u || pad.Contents.GetLineText(0u) != "11 2 11")
            {
                Console.WriteLine("FAIL: a replacement containing the needle gave "
                                  + Standard.Text.FromInteger(grown) + " and '"
                                  + pad.Contents.GetLineText(0u) + "'");
                ok = false;
            }

            // And the whole thing is one undo per replacement rather than a
            // document that cannot be put back.
            while (pad.Undo()) { }
            if (pad.Contents.GetLineText(0u) != "")
            {
                Console.WriteLine("FAIL: undoing every replacement left '"
                                  + pad.Contents.GetLineText(0u) + "'");
                ok = false;
            }

            CloseTab(_openTabs[_openTabs.Count - 1u]);
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
            // Three from Phase 1 and six the debugger added.
            if (_dock.PaneCount != 9u)
            {
                Console.WriteLine("FAIL: expected nine panes, found "
                                  + Standard.Text.FromInteger(_dock.PaneCount));
                ok = false;
            }

            if (_dock.GetEdgeOf(Panes.Solution) != DockEdge.Left)
            {
                Console.WriteLine("FAIL: the tree is not in the left well");
                ok = false;
            }
            if (_dock.GetEdgeOf(Panes.Errors) != DockEdge.Bottom
                || _dock.GetEdgeOf(Panes.Output) != DockEdge.Bottom)
            {
                Console.WriteLine("FAIL: the build's panes are not in the bottom well");
                ok = false;
            }

            if (_dock.GetEdgeOf(Panes.Locals) != DockEdge.Bottom
                || _dock.GetEdgeOf(Panes.Watch) != DockEdge.Bottom
                || _dock.GetEdgeOf(Panes.CallStack) != DockEdge.Bottom
                || _dock.GetEdgeOf(Panes.Threads) != DockEdge.Bottom
                || _dock.GetEdgeOf(Panes.Breakpoints) != DockEdge.Bottom
                || _dock.GetEdgeOf(Panes.DebugOutput) != DockEdge.Bottom)
            {
                Console.WriteLine("FAIL: the debugger's panes are not in the bottom well");
                ok = false;
            }

            // **A divider has to be somewhere a pointer can be.** A splitter
            // is windowless, so whether it can be dragged is entirely whether
            // its rectangle covers real pixels between the well and the
            // documents -- and nothing else here would notice an empty one.
            var leftSplit = _dock.GetSplitterBounds(DockEdge.Left);
            if (!_dock.IsSplitterShowing(DockEdge.Left)
                || leftSplit.Width <= 0 || leftSplit.Height <= 0)
            {
                Console.WriteLine("FAIL: the left divider is "
                                  + Standard.Text.FromInteger((long)leftSplit.Width)
                                  + " by "
                                  + Standard.Text.FromInteger((long)leftSplit.Height)
                                  + " at " + Standard.Text.FromInteger((long)leftSplit.X)
                                  + "," + Standard.Text.FromInteger((long)leftSplit.Y)
                                  + (_dock.IsSplitterShowing(DockEdge.Left)
                                     ? "" : " and is not showing"));
                ok = false;
            }

            var bottomSplit = _dock.GetSplitterBounds(DockEdge.Bottom);
            if (!_dock.IsSplitterShowing(DockEdge.Bottom)
                || bottomSplit.Width <= 0 || bottomSplit.Height <= 0)
            {
                Console.WriteLine("FAIL: the bottom divider is "
                                  + Standard.Text.FromInteger((long)bottomSplit.Width)
                                  + " by "
                                  + Standard.Text.FromInteger((long)bottomSplit.Height));
                ok = false;
            }

            // A pane nobody has heard of is not held, which is what makes
            // `ShowPane` safe to call from a menu that outlives a pane.
            if (_dock.HasPane("toolbox") || _dock.ShowPane("toolbox"))
            {
                Console.WriteLine("FAIL: a pane that does not exist was found");
                ok = false;
            }

            // Closing hides rather than destroys. The tree inside the pane is
            // live and the IDE is still holding it, so what comes back must be
            // the same one -- with the project still in it.
            nuint rooted = _tree.Nodes.Count;
            if (!_dock.ClosePane(Panes.Solution))
            {
                Console.WriteLine("FAIL: closing the tree pane did nothing");
                ok = false;
            }
            Application.DoEvents();

            if (_dock.IsPaneShowing(Panes.Solution))
            {
                Console.WriteLine("FAIL: a closed pane is still showing");
                ok = false;
            }
            if (!_dock.HasPane(Panes.Solution))
            {
                Console.WriteLine("FAIL: a closed pane was destroyed rather than hidden");
                ok = false;
            }

            if (!_dock.ShowPane(Panes.Solution))
            {
                Console.WriteLine("FAIL: a closed pane could not be reopened");
                ok = false;
            }
            Application.DoEvents();

            if (!_dock.IsPaneShowing(Panes.Solution))
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
            // the one thing `RememberWellSizes` exists to guarantee -- a
            // splitter drag raises nothing, so the sizes are read back off the
            // controls.
            _dock.RememberWellSizes();
            var written = ParseLayout(SerializeLayout(_dock.Layout));
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

        // The watch list, with no session behind it.
        //
        // What this can honestly say is that the window keeps what it was
        // asked to keep and turns down what is not an expression -- the
        // reading of one is `sldb --selftest` and `sldb watch`, which have a
        // process to read. A pane with rows in it proves neither.
        {
            nuint kept = _watches.Count;

            AddWatch("head.Next.Value");
            AddWatch("   ");
            if (_watches.Count != kept + 1u)
            {
                Console.WriteLine("FAIL: a watch was not kept, or blank space was");
                ok = false;
            }

            // Refused where it is typed rather than at the next stop, which is
            // the whole reason parsing is a pass of its own.
            if (AddWatch("a + 1").IsEmpty)
            {
                Console.WriteLine("FAIL: 'a + 1' was not refused");
                ok = false;
            }
            if (_watches.Count != kept + 1u)
            {
                Console.WriteLine("FAIL: something that is not an expression was kept");
                ok = false;
            }

            if ((nuint)_watchList.Count != _watches.Count)
            {
                Console.WriteLine("FAIL: the pane shows "
                                  + Standard.Text.FromInteger((long)_watchList.Count)
                                  + " rows for "
                                  + Standard.Text.FromInteger((long)_watches.Count)
                                  + " watches");
                ok = false;
            }

            RemoveWatchAt(kept);
            if (_watches.Count != kept || _watchList.Count != 0u)
            {
                Console.WriteLine("FAIL: removing a watch left it behind");
                ok = false;
            }
        }

        // Breakpoints against a live editor.
        //
        // `ide/tests/debugtest.sl` checks the store with no window at all.
        // What only this can check is the wiring: that toggling reaches the
        // store from a tab, and that typing above a breakpoint moves it --
        // which is one event raised by `Document` and one handler here, and
        // is invisible to a test that has neither.
        {
            var pad = AddTab(new Document());
            pad.Editor.Contents.Location = "selftest-breakpoints.sl";
            _breakpoints.Clear();

            pad.Editor.TypeText("one" + Newline + "two" + Newline + "three");
            pad.Editor.MoveCaretTo(2u, 0u);
            ToggleBreakpointAtCaret();

            if (_breakpoints.FindAtLine("selftest-breakpoints.sl", 3u) == null)
            {
                Console.WriteLine("FAIL: F9 did not set a breakpoint on line 3");
                ok = false;
            }
            if (GetMarkFor(pad.Editor, 2u) != LineMark.Breakpoint)
            {
                Console.WriteLine("FAIL: the margin does not show it");
                ok = false;
            }
            if (GetMarkFor(pad.Editor, 1u) != LineMark.None)
            {
                Console.WriteLine("FAIL: the margin shows one on a line with none");
                ok = false;
            }

            // Two lines typed above it push it from 3 to 5.
            pad.Editor.MoveCaretTo(0u, 0u);
            pad.Editor.TypeText("a" + Newline + "b" + Newline);
            Application.DoEvents();

            if (_breakpoints.FindAtLine("selftest-breakpoints.sl", 5u) == null)
            {
                Console.WriteLine("FAIL: typing above a breakpoint did not move it");
                ok = false;
            }

            // And taking those two lines out again brings it back to 3.
            //
            // Deleted rather than undone: undo would keep going past this,
            // and a document with nothing left in it says nothing about
            // whether a breakpoint follows an edit.
            pad.Editor.Contents.DeleteText(Position.Create(0u, 0u), Position.Create(2u, 0u));

            // The caret is put back before anything paints: the document was
            // edited behind the editor's back, so the caret is where those
            // lines used to be.
            pad.Editor.MoveCaretTo(0u, 0u);
            Application.DoEvents();

            if (_breakpoints.FindAtLine("selftest-breakpoints.sl", 3u) == null)
            {
                Console.WriteLine("FAIL: deleting above a breakpoint did not move it back");
                ok = false;
            }

            // A deletion that swallows it leaves it at the cut rather than
            // losing it.
            pad.Editor.Contents.DeleteText(Position.Create(1u, 0u), Position.Create(2u, 5u));
            pad.Editor.MoveCaretTo(0u, 0u);
            Application.DoEvents();

            if (_breakpoints.Count != 1u
                || _breakpoints.FindAtLine("selftest-breakpoints.sl", 2u) == null)
            {
                Console.WriteLine("FAIL: a breakpoint inside a deletion was lost");
                ok = false;
            }

            ToggleBreakpointAtCaret();
            _breakpoints.Clear();
            CloseTab(_openTabs[_openTabs.Count - 1u]);
            Application.DoEvents();
        }

        // Nothing is being debugged, so every run-control command says so
        // rather than doing something.
        {
            if (_session != null)
            {
                Console.WriteLine("FAIL: a session exists before anything started one");
                ok = false;
            }
            if (DebuggeePath.ByteLength() == 0u && _project != null)
            {
                Console.WriteLine("FAIL: a project gave no path to debug");
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
            String left = ShowCompleteLines("first line" + Newline + "second ha", false);
            if (left != "second ha" || _outputList.Count != 1u
                || _outputList.ItemAt(0u) != "first line")
            {
                Console.WriteLine("FAIL: a split line was not held back: left='"
                                  + left + "' shown="
                                  + Standard.Text.FromInteger((long)_outputList.Count));
                ok = false;
            }

            // And the rest of it completes the line rather than starting one.
            left = ShowCompleteLines(left + "lf" + Newline, false);
            if (left != "" || _outputList.Count != 2u
                || _outputList.ItemAt(1u) != "second half")
            {
                Console.WriteLine("FAIL: a line split across two chunks came back as '"
                                  + (_outputList.Count > 1u ? _outputList.ItemAt(1u) : "")
                                  + "' with '" + left + "' left over");
                ok = false;
            }

            // Windows line endings are the compiler's on this platform, and
            // must not arrive as a stray carriage return on the end of a line.
            ClearOutput();
            ShowCompleteLines("carried\r\n", false);
            if (_outputList.Count != 1u || _outputList.ItemAt(0u) != "carried")
            {
                Console.WriteLine("FAIL: a CRLF line came back as '"
                                  + (_outputList.Count == 0u ? "" : _outputList.ItemAt(0u)) + "'");
                ok = false;
            }

            ClearOutput();
        }

        // Every item of the menu bar was handed to the renderer, submenu
        // headings included.
        //
        // **This is the check that would have caught it.** An item that opens
        // a submenu is appended with `MF_POPUP` and the submenu's handle in
        // place of a command id, so it has none -- and every menu call
        // addressed items by command. Turning owner drawing on for `View` and
        // `Text size` therefore matched nothing, changed nothing and reported
        // nothing, and Windows went on drawing those two rows inside a menu
        // the program was drawing. One row looking wrong was the only symptom.
        //
        // Windows only: GTK refuses owner drawing outright and answers false
        // for every item, which is right rather than a failure.
        #if WINDOWS
        {
            nuint kept = 0u;
            foreach (var item in _menuBar.Items)
                kept = kept + CountPlatformDrawnItems(item);

            if (kept != 0u)
            {
                Console.WriteLine("FAIL: the platform kept "
                                  + Standard.Text.FromInteger((long)kept)
                                  + " menu item(s) the renderer asked for");
                ok = false;
            }
        }
        #endif

        // The project, which is what makes Build mean the program rather than
        // the file. Opening a file inside the fixture should find it without
        // anyone asking -- which is the behaviour, not just the reader.
        if (OpenFile("ide/tests/fixture/src/main.sl"))
        {
            Application.DoEvents();
            if (ProjectName != "fixture")
            {
                Console.WriteLine("FAIL: opening a file did not find the project above it,"
                                  + " and answered '" + ProjectName + "'");
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
            foreach (var entry in _treeEntries)
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

            foreach (var entry in _treeEntries)
            {
                if (FindTreeEntry(entry.Node) != entry)
                {
                    Console.WriteLine("FAIL: a tree node did not answer with its own"
                                      + " entry: " + entry.FullPath);
                    ok = false;
                }

                // A new file goes beside a file, and inside a directory.
                String wanted = entry.IsFolder
                              ? entry.FullPath
                              : Path.DirectoryName(entry.FullPath);
                if (GetFolderFor(entry) != wanted)
                {
                    Console.WriteLine("FAIL: a new file beside " + entry.FullPath
                                      + " would go to '" + GetFolderFor(entry) + "'");
                    ok = false;
                }
            }

            if (GetFolderFor(null).ByteLength() != 0u)
            {
                Console.WriteLine("FAIL: a new file was offered a home with nothing"
                                  + " clicked on");
                ok = false;
            }

            // The module a new file would be seeded with. Both of the
            // fixture's files declare `Fixture`, so a third belongs in it too.
            String seeded = ReadFolderModule("ide/tests/fixture/src");
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
            var arguments = ComposeCompilerArguments(false);
            if (!ContainsArgument(arguments, "--project")
                || !ContainsArgument(arguments, _projectPath))
            {
                Console.WriteLine("FAIL: a project build did not ask for the project");
                ok = false;
            }
            if (!ContainsArgument(arguments, "--diagnostics")
                || !ContainsArgument(arguments, "json"))
            {
                Console.WriteLine("FAIL: a build did not ask for diagnostics it can read");
                ok = false;
            }

            // The configuration picker, which is the only thing that decides
            // what a build is optimised for -- a project's own `optimize` and
            // `debug` are overridden rather than consulted, so what the picker
            // says has to reach the command line or it says nothing at all.
            if (!ContainsArgument(arguments, "-g") || !ContainsArgument(arguments, "-O0")
                || ContainsArgument(arguments, "--no-debug"))
            {
                Console.WriteLine("FAIL: a Debug build did not ask to be debuggable");
                ok = false;
            }

            _configuration.SelectedIndex = 1;
            if (SelectedConfiguration != Configuration.Release)
            {
                Console.WriteLine("FAIL: the picker did not move to Release");
                ok = false;
            }

            var shipping = ComposeCompilerArguments(false);
            if (!ContainsArgument(shipping, "--no-debug") || !ContainsArgument(shipping, "-O2")
                || ContainsArgument(shipping, "-g") || ContainsArgument(shipping, "-O0"))
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
