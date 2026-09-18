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

    ListBox _output;
    Splitter _divider;
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
        _project = null;
        _projectPath = "";
        _building = false;
        _compiler = FindCompiler();
        _textSize = 10;
        _dark = false;

        _status = new StatusBar(this);
        _status.Dock = DockStyle.Bottom;
        _status.AddPanel(420);
        _status.AddPanel(180);
        _status.AddPanel(0);

        _output = new ListBox(this);
        _output.Dock = DockStyle.Bottom;
        _output.Height = 160;
        _output.DoubleClick += this.OnOutputChosen;

        _divider = new Splitter(this);
        _divider.Dock = DockStyle.Bottom;

        _book = new TabControl(this);
        _book.Dock = DockStyle.Fill;
        _book.SelectedIndexChanged += this.OnTabChanged;

        BuildMenu();
        NewFile();
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
        _output.Clear();
        _messages.Clear();
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

        _output.Clear();
        _messages.Clear();

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

        _output.Clear();
        _messages.Clear();
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

        if (_project != null)
            return [verb, "--project", _projectPath];

        var now = Current;
        if (now == null)
            return [verb];
        return [verb, ((CodeEditor)now).Contents.Location];
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
        ShowAll(result.Errors);
        ShowAll(result.Output);

        Say(result.ExitCode == 0
            ? success
            : "Failed, with " + Standard.Text.FromInteger(result.ExitCode) + ".");
        _status.SetPanelText(1, CountErrors());
    }

    void ShowAll(String text)
    {
        if (text.ByteLength() == 0u)
            return;
        foreach (var line in text.Replace("\r\n", "\n").Split("\n"))
            Show(line);
    }

    void Show(String line)
    {
        _output.Add(line);
        _messages.Add(BuildMessage.Parse(line));
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
        nuint index = (nuint)_output.SelectedIndex;
        if (_output.SelectedIndex < 0 || index >= _messages.Count)
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

    // -------------------------------------------------------------- the rest

    void OnCaretMoved(Control sender)
    {
        var now = Current;
        if (now == null)
            return;
        var editor = (CodeEditor)now;
        var at = editor.CaretPosition;
        String line = editor.Contents.TextAt(at.Row);
        _status.SetPanelText(2,
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
            var arguments = BuildArguments(false);
            if (arguments.Length != 3u || arguments[1u] != "--project")
            {
                Console.WriteLine("FAIL: a project build did not ask for the project");
                ok = false;
            }
        }
        else
        {
            Console.WriteLine("  (project check skipped: run from the repository root)");
        }

        if (ok)
        {
            Console.WriteLine("  editing, lexing, the clipboard, text size, tabs and the project");
        }
        return ok;
    }
}

// ================================================================== messages

/// One line of the compiler's output, and where it points.
///
/// **Parsed rather than asked for.** The compiler prints
/// `  --> path\to\file.sl:12:5` under each diagnostic, which is a format meant
/// for a person; reading it is what makes an error clickable today, and it is
/// the thing a `stainless serve` mode replaces with an answer that does not
/// have to be guessed at.
public struct BuildMessage
{
    public String File;
    public nuint Line;
    public nuint Column;
    public bool IsError;

    public bool HasPlace => Line > 0u;

    public static BuildMessage Parse(String line)
    {
        BuildMessage found;
        found.File = "";
        found.Line = 0u;
        found.Column = 0u;
        found.IsError = line.StartsWith("error");

        String trimmed = line.Trim();
        if (!trimmed.StartsWith("--> "))
            return found;

        // `path:line:column`, and the path may itself contain a colon after a
        // drive letter -- so the two numbers are taken from the end rather than
        // the path from the beginning.
        String rest = trimmed.Substring(4u);
        long lastColon = rest.LastIndexOf(":");
        if (lastColon < 0)
            return found;
        String columnText = rest.Substring((nuint)lastColon + 1u);

        String upToColumn = rest.Substring(0u, (nuint)lastColon);
        long beforeThat = upToColumn.LastIndexOf(":");
        if (beforeThat < 0)
            return found;

        found.File = upToColumn.Substring(0u, (nuint)beforeThat);
        found.Line = ParseNumber(upToColumn.Substring((nuint)beforeThat + 1u));
        found.Column = ParseNumber(columnText);
        return found;
    }

    /// A run of digits as a number, and zero for anything else. Deliberately
    /// forgiving: this is reading a message meant for a person.
    static nuint ParseNumber(String text)
    {
        nuint value = 0u;
        nuint at = 0u;
        if (text.ByteLength() == 0u)
            return 0u;
        while (at < text.ByteLength())
        {
            byte c = text.ByteAt(at);
            if (c < (byte)'0' || c > (byte)'9')
                return at == 0u ? 0u : value;
            value = value * 10u + (nuint)(c - (byte)'0');
            at++;
        }
        return value;
    }
}
