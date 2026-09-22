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

// Project properties: `stainless.json`, edited in a window.
//
// **Modal, unlike the find window**, and for the opposite reason: this edits the
// thing every other pane is showing, so leaving it open while the project tree
// and the build read a half-changed model is a class of bug rather than a
// convenience. It opens, it is answered, it closes.
//
// **Four pages over one model.** The pages are the groups `docs/packages.md`
// already describes -- what the program is, how it is built, what it is built
// from, and where the output goes -- rather than a page per screenful, so that
// someone who has read the format finds each field where the documentation put
// it.
//
// **Nothing is written to the project until OK.** The controls are filled from
// a `ProjectFile` and read back into it in one pass, so Cancel is genuinely
// nothing having happened rather than a set of changes undone.
module Ide.App;

import Standard.Collections;
import Standard.Text;
import Forms;
import Forms.Drawing;
import Forms.Platform;
import Ide.Project;

/// The project properties window.
public class ProjectDialog : Form
{
    TabControl _pages;

    // General.
    TextBox _name;
    TextBox _version;
    ComboBox _kind;
    TextBox _output;

    // Build.
    ComboBox _optimize;
    CheckBox _debug;
    TextBox _defines;
    ComboBox _abi;
    ComboBox _runtime;

    // References.
    ListBox _references;
    TextBox _libraries;

    // Paths.
    TextBox _sources;
    TextBox _buildDirectory;
    TextBox _objectDirectory;
    TextBox _header;

    Button _ok;
    Button _cancel;

    /// Whether OK was pressed. `Form.ShowModal` answers nothing by design --
    /// `forms/Form.sl` argues that a dialog with an answer should carry it as a
    /// property typed as whatever the answer actually is -- so this is it.
    public bool Accepted;

    /// The project `Load` was given, so that OK can read the controls back into
    /// it **before** the window goes away.
    ///
    /// **This is not a convenience.** A `TextBox`'s text lives in the native
    /// control, not in the object, so reading `.Text` after the window has
    /// closed answers the empty string -- and the first version of this dialog
    /// called `Store` after `ShowModal` returned and wrote a project with no
    /// name, no version and no sources over a perfectly good file. Reading has
    /// to happen while the controls still exist, which means inside the click.
    ProjectFile? _editing;

    public ProjectDialog()
    {
        base(WindowBorder.Fixed);
        Title = "Project properties";
        SetBounds(0, 0, 520, 420);
        Accepted = false;
        _editing = null;

        _pages = new TabControl(this);
        _pages.SetBounds(8, 8, 496, 330);
        _pages.Anchors = AnchorStyles.Top | AnchorStyles.Left
                       | AnchorStyles.Right | AnchorStyles.Bottom;

        var general = new TabPage(_pages, "General");
        _name = Field(general, "Name:", 0);
        _version = Field(general, "Version:", 1);
        _kind = Choice(general, "Kind:", 2, ["executable", "library"]);
        _output = Field(general, "Output file:", 3);

        var build = new TabPage(_pages, "Build");
        _optimize = Choice(build, "Optimize:", 0,
                           ["0 - none", "1 - some", "2 - default", "3 - most"]);
        _abi = Choice(build, "ABI:", 1, ["", "c", "stainless"]);
        _runtime = Choice(build, "Runtime:", 2, ["", "static", "shared"]);
        _defines = Field(build, "Defines:", 3);
        _debug = new CheckBox(build);
        _debug.Text = "Debug information";
        _debug.SetBounds(120, 4 * RowHeight + 14, 220, 22);

        var references = new TabPage(_pages, "References");
        _references = new ListBox(references);
        _references.SetBounds(12, 12, 460, 180);
        _references.Anchors = AnchorStyles.Top | AnchorStyles.Left
                            | AnchorStyles.Right | AnchorStyles.Bottom;
        _libraries = Field(references, "Libraries:", 6);

        var paths = new TabPage(_pages, "Paths");
        _sources = Field(paths, "Sources:", 0);
        _buildDirectory = Field(paths, "Build:", 1);
        _objectDirectory = Field(paths, "Objects:", 2);
        _header = Field(paths, "Header:", 3);

        _ok = new Button(this);
        _ok.Text = "OK";
        _ok.SetBounds(324, 348, 88, 28);
        _ok.Anchors = AnchorStyles.Bottom | AnchorStyles.Right;
        _ok.Click += this.OnOk;

        _cancel = new Button(this);
        _cancel.Text = "Cancel";
        _cancel.SetBounds(418, 348, 88, 28);
        _cancel.Anchors = AnchorStyles.Bottom | AnchorStyles.Right;
        _cancel.Click += this.OnCancel;
    }

    /// One row of a page, in pixels.
    static readonly int RowHeight = 32;

    /// A label and an edit on one row. Returns the edit.
    ///
    /// A helper rather than sixteen near-identical four-line blocks, because
    /// this dialog is mostly rows and the only thing that differs between them
    /// is the caption and which field it is bound to.
    TextBox Field(WindowedControl page, String caption, int row)
    {
        var label = new Label(page);
        label.Text = caption;
        label.SetBounds(12, row * RowHeight + 16, 104, 20);

        var box = new TextBox(page, false);
        box.SetBounds(120, row * RowHeight + 12, 344, 24);
        box.Anchors = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        return box;
    }

    /// The same, with a drop-down of the values the format allows.
    ComboBox Choice(WindowedControl page, String caption, int row, String[] values)
    {
        var label = new Label(page);
        label.Text = caption;
        label.SetBounds(12, row * RowHeight + 16, 104, 20);

        var list = new ComboBox(page);
        list.SetBounds(120, row * RowHeight + 12, 200, 24);
        foreach (var value in values)
        {
            list.Add(value);
        }
        return list;
    }

    // ------------------------------------------------------------- the model

    /// Fills the controls from a project.
    ///
    /// **A list joined by spaces for the three arrays**, rather than a list box
    /// with Add and Remove buttons for each. `sources`, `defines` and
    /// `libraries` are short lists of short words, and a text field is both the
    /// quickest thing to edit and the one that shows the whole of it at once --
    /// which three buttons around a list box does not. Anything with spaces in
    /// it would need quoting, and a path with a space in it is the one real
    /// limit here; it is named in `ide/README.md` rather than half-solved.
    public void Load(ProjectFile project)
    {
        _editing = project;
        _name.Text = project.Name;
        _version.Text = project.Version;
        Select(_kind, project.Kind == "" ? "executable" : project.Kind);
        _output.Text = project.Output;

        int level = project.Optimize;
        _optimize.SelectedIndex = (level < 0 || level > 3) ? 2 : level;
        _debug.Checked = project.Debug;
        _defines.Text = Joined(project.Defines);
        Select(_abi, project.Abi);
        Select(_runtime, project.Runtime);

        _references.Clear();
        foreach (var dependency in project.Dependencies)
        {
            _references.Add(dependency.Name + "  --  " + dependency.ToDisplayText());
        }
        if (project.Dependencies.IsEmpty)
            _references.Add("(no dependencies)");
        _libraries.Text = Joined(project.Libraries);

        _sources.Text = Joined(project.Sources);
        _buildDirectory.Text = project.BuildDirectory;
        _objectDirectory.Text = project.ObjectDirectory;
        _header.Text = project.Header;
    }

    /// Reads the controls back into the project. Called by OK and by nothing
    /// else -- in particular not by the caller after the dialog has closed,
    /// which is what made the first version of this destroy a project file.
    ///
    /// **`dependencies` is not written back**, and the References page says so
    /// by being a list rather than an editor: a dependency is a name, a source,
    /// a version requirement and a link mode, and editing one properly is its
    /// own dialog. Showing them read-only is honest; a half-editor that dropped
    /// the fields it did not show would not be.
    void Store(ProjectFile project)
    {
        project.Name = _name.Text;
        project.Version = _version.Text;
        project.Kind = Chosen(_kind);
        project.Output = _output.Text;

        int level = _optimize.SelectedIndex;
        project.Optimize = (level < 0) ? 2 : level;
        project.Debug = _debug.Checked;
        project.Defines = Split(_defines.Text);
        project.Abi = Chosen(_abi);
        project.Runtime = Chosen(_runtime);

        project.Libraries = Split(_libraries.Text);

        project.Sources = Split(_sources.Text);
        project.BuildDirectory = _buildDirectory.Text;
        project.ObjectDirectory = _objectDirectory.Text;
        project.Header = _header.Text;
    }

    /// The text of the chosen entry, empty when nothing is chosen -- which for
    /// `abi` and `runtime` is what "leave it at the default" means, and is why
    /// the empty string is the first entry in both of those lists.
    ///
    /// The `optimize` list is read by index instead, because its entries say
    /// `2 - default` and the number is what the file holds.
    String Chosen(ComboBox list)
    {
        var chosen = list.SelectedItem;
        return chosen == null ? "" : (String)chosen;
    }

    void Select(ComboBox list, String value)
    {
        for (nuint i = 0u; i < list.Count; i++)
        {
            if (list.ItemAt(i) == value)
            {
                list.SelectedIndex = (int)i;
                return;
            }
        }
        list.SelectedIndex = 0;
    }

    /// An array as one line. Public and static-shaped so that the self test can
    /// check the round trip without a window.
    public static String Joined(String[] values)
    {
        var text = new StringBuilder();
        for (nuint i = 0u; i < values.Length; i++)
        {
            if (i > 0u)
                text.Append(" ");
            text.Append(values[i]);
        }
        return text.ToText();
    }

    /// And back, dropping the empty pieces that runs of spaces produce -- so
    /// that a trailing space does not become an entry that names nothing and
    /// makes the compiler look for a directory called "".
    public static String[] Split(String text)
    {
        var kept = new List<String>();
        foreach (var piece in text.Split(" "))
        {
            String trimmed = piece.Trim();
            if (trimmed != "")
                kept.Add(trimmed);
        }

        var answer = new String[kept.Count];
        for (nuint i = 0u; i < kept.Count; i++)
        {
            answer[i] = kept[i];
        }
        return answer;
    }

    void OnOk(Control sender)
    {
        // Read here, not after `ShowModal` returns: see `_editing`.
        var project = _editing;
        if (project == null)
            return;

        Store((ProjectFile)project);
        Accepted = true;
        Close();
    }

    void OnCancel(Control sender)
    {
        Accepted = false;
        Close();
    }
}
