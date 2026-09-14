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

// The window: an editor, an output pane, a menu and a status bar.
//
// **What is here and what is not.** This is the first working shape of the
// thing -- one file open at a time, a build that runs the compiler and shows
// what it said, and an error line that takes you to the line it names. There is
// no project tree yet, no tabs, and no debugger; each of those is a pane and a
// model beside the two that are here rather than a change to them, which is why
// this file is laid out as a set of docked panes from the start.
module Ide.App;

import Standard.Text;
import Standard.Collections;
import Standard.IO;
import Standard.File;
import Standard.Process;
import Standard.Env;
import Forms;
import Forms.Drawing;
import Forms.Platform;
import Ide.Lang;
import Ide.Editor;

/// The main window.
public class Shell : Form {
    CodeEditor editor;
    ListBox    output;
    Splitter   divider;
    StatusBar  status;
    MainMenu   bar;

    MenuItem   themeItem;

    /// Where the compiler is. Found once at startup; empty when it was not
    /// found, which the build command reports rather than failing silently.
    String compiler;

    /// What the last build reported, one entry per line of its output, so that
    /// a click on a line can look up where it points.
    List<BuildMessage> messages;

    public Shell() {
        base(WindowBorder.Sizable);
        Text = "Stainless";
        SetBounds(0, 0, 1000, 700);

        messages = new List<BuildMessage>();
        compiler = FindCompiler();

        status = new StatusBar(this);
        status.Dock = DockStyle.Bottom;
        status.AddPanel(420);
        status.AddPanel(180);
        status.AddPanel(0);

        output = new ListBox(this);
        output.Dock = DockStyle.Bottom;
        output.Height = 160;
        output.DoubleClick += this.OnOutputChosen;

        divider = new Splitter(this);
        divider.Dock = DockStyle.Bottom;

        editor = new CodeEditor(this);
        editor.Dock = DockStyle.Fill;
        editor.CaretMoved += this.OnCaretMoved;
        editor.Edited += this.OnEdited;

        BuildMenu();
        Retitle();
        Say("Ready.");
    }

    /// The editor, for a caller that has a file to put in it.
    public CodeEditor Editor => editor;

    /// Opens a file into the editor, and says whether it could be read.
    ///
    /// **Here rather than on the editor**, because opening a file is not only
    /// putting text in a control: the title, the status bar and the output pane
    /// all say something about which file is open, and a caller that reached
    /// past this to `Editor.SetDocument` would leave all three describing the
    /// last one. The command line took that shortcut and the title said
    /// "Untitled" over somebody else's source.
    public bool OpenFile(String path) {
        var document = new Document();
        if (!document.Load(path)) { return false; }
        editor.SetDocument(document);
        output.Clear();
        messages.Clear();
        Retitle();
        Say("Opened " + path);
        return true;
    }

    // ----------------------------------------------------------- the menu

    void BuildMenu() {
        bar = new MainMenu();

        var file = bar.Add("&File");
        file.Add("&New").Click += this.OnNew;
        file.Add("&Open...").Click += this.OnOpen;
        file.Add("&Save").Click += this.OnSave;
        file.Add("Save &As...").Click += this.OnSaveAs;
        file.Add(MenuItem.Separator());
        file.Add("E&xit").Click += this.OnExit;

        var build = bar.Add("&Build");
        build.Add("&Build").Click += this.OnBuild;
        build.Add("&Run").Click += this.OnRun;
        build.Add(MenuItem.Separator());
        build.Add("&Clear output").Click += this.OnClearOutput;

        var view = bar.Add("&View");
        themeItem = view.Add("&Dark theme");
        themeItem.Click += this.OnToggleTheme;

        Menu = bar;
    }

    // ------------------------------------------------------------ the file

    void OnNew(MenuItem sender) {
        editor.SetDocument(new Document());
        editor.Focus();
        Retitle();
        Say("A new file.");
    }

    void OnOpen(MenuItem sender) {
        var dialog = new OpenDialog();
        dialog.Title = "Open";
        dialog.AddFilter("Stainless source", "*.sl");
        dialog.AddFilter("Every file", "*");

        var chosen = dialog.Show(this);
        if (!chosen.Ok) { return; }

        if (!OpenFile(chosen.Value)) {
            Say("Could not read " + chosen.Value);
            return;
        }
        editor.Focus();
    }

    void OnSave(MenuItem sender) { SaveTo(editor.Contents.Location); }

    void OnSaveAs(MenuItem sender) { SaveTo(""); }

    /// Saves to `path`, or asks for one when it is empty.
    void SaveTo(String path) {
        String target = path;
        if (target.ByteLength() == 0u) {
            var dialog = new SaveDialog();
            dialog.Title = "Save as";
            dialog.AddFilter("Stainless source", "*.sl");
            dialog.FileName = editor.Contents.Location;
            var chosen = dialog.Show(this);
            if (!chosen.Ok) { return; }
            target = chosen.Value;
        }

        if (!editor.Contents.Save(target)) {
            Say("Could not write " + target);
            return;
        }
        Retitle();
        Say("Saved " + target);
    }

    void OnExit(MenuItem sender) { Close(); }

    // --------------------------------------------------------- the compiler

    /// Where `stainless` is.
    ///
    /// **Beside this program first, and on the path after.** An IDE shipped
    /// next to the compiler it drives should use that one rather than whichever
    /// happens to be installed, because the two move together.
    String FindCompiler() {
        // `Env.Program` is the path the system started this with, which is not
        // guaranteed to say where the binary is -- a shell may pass a bare
        // name. So this is a hint that is checked rather than a location that
        // is trusted, and the bare name is the answer when it fails.
        String self = Env.Program();
        long cut = self.LastIndexOf(Separator());
        if (cut > 0) {
            String beside = self.Substring(0u, (nuint)cut) + Separator()
                          + "stainless" + Extension();
            if (File.Exists(beside)) { return beside; }
        }
        return "stainless";
    }

    String Separator() {
        #if WINDOWS
        return "\\";
        #else
        return "/";
        #endif
    }

    String Extension() {
        #if WINDOWS
        return ".exe";
        #else
        return "";
        #endif
    }

    void OnBuild(MenuItem sender) { Compile(false); }
    void OnRun(MenuItem sender)   { Compile(true); }

    void OnClearOutput(MenuItem sender) {
        output.Clear();
        messages.Clear();
    }

    /// Saves, then runs the compiler over the file and shows what it said.
    ///
    /// **Synchronous, and that is the next thing to fix.** The window stops
    /// answering for as long as the build takes, which for one file is a
    /// second and for a project is not. What it needs is the build on a thread
    /// with its output arriving through a queue the message loop drains -- and
    /// what that needs first is a decision about how `Forms` marshals to the
    /// UI thread, which it has no answer for yet.
    void Compile(bool thenRun) {
        String path = editor.Contents.Location;
        if (path.ByteLength() == 0u) {
            Say("Save the file before building it.");
            return;
        }
        if (editor.Contents.Edited && !editor.Contents.Save(path)) {
            Say("Could not write " + path);
            return;
        }
        Retitle();

        output.Clear();
        messages.Clear();
        Say(thenRun ? "Running..." : "Building...");

        String[] arguments = [thenRun ? "run" : "build", path];
        var finished = Process.Run(compiler, arguments);
        if (!finished.Ok) {
            Show("could not start '" + compiler + "' -- is it on the path?");
            Say("The compiler could not be started.");
            return;
        }

        var result = finished.Value;
        // The compiler writes its diagnostics to the error stream and what the
        // program printed to the output one, so both are shown and in that
        // order: what went wrong first, then what the program said.
        ShowAll(result.Errors);
        ShowAll(result.Output);

        Say(result.ExitCode == 0
            ? (thenRun ? "Ran." : "Built.")
            : "Failed, with " + Standard.Text.FromInteger(result.ExitCode) + ".");
        status.SetPanelText(1, CountErrors());
    }

    void ShowAll(String text) {
        if (text.ByteLength() == 0u) { return; }
        foreach (var line in text.Replace("\r\n", "\n").Split("\n")) {
            Show(line);
        }
    }

    /// Adds one line to the output pane, remembering what file and line it
    /// points at if it points at one.
    void Show(String line) {
        output.Add(line);
        messages.Add(BuildMessage.Parse(line));
    }

    String CountErrors() {
        nuint errors = 0u;
        foreach (var message in messages) {
            if (message.IsError) { errors += 1u; }
        }
        if (errors == 0u) { return ""; }
        return Standard.Text.FromInteger(errors)
             + (errors == 1u ? " error" : " errors");
    }

    /// A line of the output was double-clicked: go to what it points at.
    void OnOutputChosen(Control sender) {
        nuint index = (nuint)output.SelectedIndex;
        if (output.SelectedIndex < 0 || index >= messages.Count()) { return; }

        var message = messages[index];
        if (!message.HasPlace) { return; }

        // Only when it is this file. Opening the one it names instead is what
        // a project tree makes reasonable, and there is not one yet.
        if (message.File != editor.Contents.Location) {
            Say(message.File + ":" + Standard.Text.FromInteger(message.Line)
                + " is in another file.");
            return;
        }

        editor.GoTo(message.Line - 1u, message.Column > 0u ? message.Column - 1u : 0u);
        editor.Focus();
    }

    // ------------------------------------------------------------ the rest

    void OnToggleTheme(MenuItem sender) {
        bool dark = !themeItem.Checked;
        themeItem.Checked = dark;
        editor.Palette = dark ? Theme.Dark() : Theme.Light();
    }

    void OnCaretMoved(Control sender) {
        var at = editor.CaretPosition;
        String line = editor.Contents.TextAt(at.Row);
        status.SetPanelText(2,
            "Ln " + Standard.Text.FromInteger(at.Row + 1u)
          + ", Col " + Standard.Text.FromInteger(editor.ColumnOf(line, at.Column) + 1u));
    }

    void OnEdited(Control sender) { Retitle(); }

    /// The title says what is open and whether it has been changed, which is
    /// the one piece of state a person checks without being told to.
    void Retitle() {
        String path = editor.Contents.Location;
        String name = path.ByteLength() == 0u ? "Untitled" : path.AfterLast(Separator());
        if (name.ByteLength() == 0u) { name = path; }
        Text = (editor.Contents.Edited ? "* " : "") + name + " -- Stainless";
        status.SetPanelText(0, path.ByteLength() == 0u ? "Not saved" : path);
    }

    void Say(String what) { status.SetPanelText(1, what); }

    /// What the self test checks, since a window cannot be typed into by a
    /// machine.
    public bool SelfTest() {
        bool ok = true;

        editor.Focus();
        Application.DoEvents();
        if (!editor.Focused) {
            Say("the editor did not take the focus");
            ok = false;
        }

        editor.Type("int Main() { return 0; }");
        if (editor.Contents.TextAt(0u) != "int Main() { return 0; }") { ok = false; }

        // The line has to have lexed, or nothing would be coloured.
        var tokens = editor.Contents.LineAt(0u).Tokens;
        if (tokens.Count() == 0u) { ok = false; }

        editor.Type("\nint Second() { return 1; }");
        if (editor.Contents.LineCount() != 2u) { ok = false; }
        if (editor.Contents.LineAt(1u).Tokens.Count() == 0u) { ok = false; }

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
public struct BuildMessage {
    public String File;
    public nuint  Line;
    public nuint  Column;
    public bool   IsError;

    public bool HasPlace => Line > 0u;

    public static BuildMessage Parse(String line) {
        BuildMessage found;
        found.File = "";
        found.Line = 0u;
        found.Column = 0u;
        found.IsError = line.StartsWith("error");

        String trimmed = line.Trim();
        if (!trimmed.StartsWith("--> ")) { return found; }

        // `path:line:column`, and the path may itself contain a colon after a
        // drive letter -- so the two numbers are taken from the end rather than
        // the path from the beginning.
        String rest = trimmed.Substring(4u);
        long lastColon = rest.LastIndexOf(":");
        if (lastColon < 0) { return found; }
        String columnText = rest.Substring((nuint)lastColon + 1u);

        String upToColumn = rest.Substring(0u, (nuint)lastColon);
        long beforeThat = upToColumn.LastIndexOf(":");
        if (beforeThat < 0) { return found; }

        found.File = upToColumn.Substring(0u, (nuint)beforeThat);
        found.Line = ParseNumber(upToColumn.Substring((nuint)beforeThat + 1u));
        found.Column = ParseNumber(columnText);
        return found;
    }

    /// A run of digits as a number, and zero for anything else. Deliberately
    /// forgiving: this is reading a message meant for a person.
    static nuint ParseNumber(String text) {
        nuint value = 0u;
        nuint at = 0u;
        if (text.ByteLength() == 0u) { return 0u; }
        while (at < text.ByteLength()) {
            byte c = text.ByteAt(at);
            if (c < (byte)'0' || c > (byte)'9') { return at == 0u ? 0u : value; }
            value = value * 10u + (nuint)(c - (byte)'0');
            at += 1u;
        }
        return value;
    }
}
