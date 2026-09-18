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

    /// Every file the tree is showing, by node, so that a double-click knows
    /// what to open. `TreeNode` carries no tag of its own.
    List<TreeNode> _treeNodes;
    List<String> _treePaths;

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

    public Shell()
    {
        base(WindowBorder.Sizable);
        Text = "Stainless";
        SetBounds(0, 0, 1000, 700);

        _open = new List<EditorTab>();
        _messages = new List<BuildMessage>();
        _errorLines = new List<nuint>();
        _treeNodes = new List<TreeNode>();
        _treePaths = new List<String>();
        _project = null;
        _projectPath = "";
        _building = false;
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
            return _open.At((nuint)at).Editor;
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
        if (_open.IsEmpty())
            return;
        _book.SelectedIndex = 0;
        _open.At(0u).Editor.Focus();
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
        var stale = replacing ? _open.At(0u) : null;

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
            if (_open.At(i) == tab)
            {
                _open.RemoveAt(i);
                break;
            }
        }
        // A window with no editor in it has nowhere to type, so closing the
        // last tab opens an empty one rather than leaving a hole.
        if (_open.IsEmpty())
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

        var build = _bar.Add("&Build");
        build.Add("&Build").Click += this.OnBuild;
        build.Add("&Run").Click += this.OnRun;
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
        CloseTab(_open.At((nuint)at));
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
    void OnRun(MenuItem sender) => Compile(true);

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
    /// **The output still arrives all at once at the end.** `Process.Run`
    /// captures both streams and answers when the child exits, so there is
    /// nothing to stream from. Streaming wants a `Process` that hands back its
    /// pipes as they fill, and that is a change to `Standard.Process` rather
    /// than to this. What was actually wrong -- a window that stopped
    /// repainting -- is fixed; a build that reports as it goes is not yet.
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

    void OnClean(MenuItem sender)
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
            return;
        }

        if (!Directory.Exists(rubbish))
        {
            Say("Nothing to clean.");
            return;
        }

        nuint removed = RemoveTree(rubbish);
        Show("removed " + Standard.Text.FromInteger((long)removed) + " files from " + rubbish);
        Say("Cleaned.");
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

    /// The file in front, saved, or false when it could not be.
    ///
    /// A project build still saves the file in front and nothing else, which is
    /// the honest half-measure: saving every edited tab is what a project build
    /// should do and wants a decision about tabs that have never had a name.
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
            path = editor.Contents.Location;
        }
        else if (editor.Contents.Edited && !editor.Contents.Save(path))
        {
            Say("Could not write " + path);
            return false;
        }

        RelabelFor(editor);
        Retitle();
        return true;
    }

    /// What the compiler is asked, which is the project when there is one.
    String[] BuildArguments(bool thenRun)
    {
        String verb = thenRun ? "run" : "build";

        // JSON, because the alternative is reading a format meant for a person
        // and guessing which part of it was the file name. `BuildMessage` says
        // what that cost.
        if (_project != null)
            return [verb, "--diagnostics", "json", "--project", _projectPath];

        var now = Current;
        if (now == null)
            return [verb, "--diagnostics", "json"];
        return [verb, "--diagnostics", "json", ((CodeEditor)now).Contents.Location];
    }

    /// Runs the compiler on a thread and reports back on the UI one.
    ///
    /// **Everything the worker needs is read before it starts.** The closure
    /// captures two strings and an array, and touches no control: a control
    /// read from another thread is the bug this arrangement exists to avoid,
    /// and `Forms` says so where `Background.Run` is declared.
    void Start(String[] arguments, String success)
    {
        _building = true;
        String compiler = _compiler;

        Background.Run(
            () => Process.Run(compiler, arguments),
            finished => Finished(finished, success));
    }

    /// Back on the UI thread, with whatever the compiler said.
    void Finished(Result<Completed, ProcessError> finished, String success)
    {
        _building = false;

        if (!finished.Ok)
        {
            Show("could not start '" + _compiler + "' -- is it on the path?");
            Say("The compiler could not be started.");
            return;
        }

        var result = finished.Value;
        // The compiler writes diagnostics to the error stream and the program's
        // own output to the other, so both are shown, in that order.
        ShowAll(result.Errors, true);
        ShowAll(result.Output, false);

        Say(result.ExitCode == 0
            ? success
            : "Failed, with " + Standard.Text.FromInteger(result.ExitCode) + ".");
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
        _treeNodes.Clear();
        _treePaths.Clear();

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
                AddFiles(branch, resolved);
            }
            else if (File.Exists(resolved))
            {
                Remember(branch, resolved);
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
                AddFiles(below, inner);
            }
        }

        var files = Directory.Files(folder);
        if (!files.Ok)
            return;

        foreach (var file in files.Value)
        {
            if (file.EndsWith(".sl"))
                Remember(branch.Add(NameOf(file)), file);
        }
    }

    /// Ties a node to the file it stands for.
    ///
    /// Two parallel lists rather than a field on the node, because `TreeNode`
    /// carries no tag and adding one would put a `String` on every node of
    /// every tree in `forms/` for the sake of this one. A handful of files is a
    /// handful of entries, and the search is over in microseconds.
    void Remember(TreeNode node, String path)
    {
        _treeNodes.Add(node);
        _treePaths.Add(path);
    }

    /// A node was double-clicked. A file opens; anything else does nothing.
    void OnTreeChosen(Control sender)
    {
        var chosen = _tree.SelectedNode;
        if (chosen == null)
            return;

        var node = (TreeNode)chosen;
        for (nuint i = 0u; i < _treeNodes.Count; i++)
        {
            if (_treeNodes.At(i) == node)
            {
                if (!OpenFile(_treePaths.At(i)))
                    Say("Could not read " + _treePaths.At(i));
                return;
            }
        }
    }

    /// A row of the Error List was double-clicked, which goes to exactly where
    /// the same diagnostic in Output goes -- one path through one model.
    void OnErrorChosen(Control sender)
    {
        int row = _errors.SelectedIndex;
        if (row < 0 || (nuint)row >= _errorLines.Count)
            return;

        GoToMessage(_errorLines.At((nuint)row));
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
        CloseTab(_open.At((nuint)at));
        if (_open.Count != had)
        {
            Console.WriteLine("FAIL: closing a tab did not remove it");
            ok = false;
        }

        // Closing them all leaves one empty tab rather than none.
        while (_open.Count > 1u)
            CloseTab(_open.At(0u));
        CloseTab(_open.At(0u));
        if (_open.Count != 1u)
        {
            Console.WriteLine("FAIL: closing every tab left "
                              + Standard.Text.FromInteger(_open.Count));
            ok = false;
        }

        // Several files at once, which is what the command line does and what
        // a single open never exercised.
        while (_open.Count > 1u)
            CloseTab(_open.At(0u));
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

            CloseTab(_open.At(_open.Count - 1u));
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
