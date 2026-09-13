// SPDX-License-Identifier: 0BSD
//
// A user control: a composite widget with events of its own.
//
//   stainless run samples/gtk/control.sl bindings/gtk \
//       -l gtk-3 -l gdk-3 -l gobject-2.0 -l glib-2.0 -l cairo
//
// This is the shape a component library is made of, and the point of it is
// **who knows what**. `SearchBox` is built from an entry and two buttons, and
// the program using it knows about none of them: it sees a `Widget` to put in
// a layout, three events to subscribe to, and a couple of properties. Swapping
// the entry for something else would not touch a line below `// the program`.
//
// The events are `closure` types (§2.14.1) -- a method and the object it
// belongs to -- so a handler can be either:
//
//     search.OnSearch(results.Show);          // a method bound to an object
//     search.OnSearch((text) => { ... });     // or a lambda that captures
//
// and both are the same two words. That is what a component library needs and
// what a bare function pointer cannot be: a handler has to know *which*
// results panel to show them in.
//
// The control raises its own events the same way it would call anything else,
// and the wiring between the widgets it owns and the events it publishes is
// the whole of what it does.
module Control;

import Standard.Collections;
import Standard.Console;
import Gtk;

// ------------------------------------------------------- the control's events

/// What a search asks for.
public closure void SearchRequested(String text);

/// What the text changing reports. Separate from the above because a program
/// usually wants one and not the other: this fires on every keystroke.
public closure void TextChanged(String text);

/// Answered before a search runs; false stops it. The shape a validation hook
/// has, and the reason an event that can refuse is worth having.
public closure bool SearchAllowed(String text);

// ------------------------------------------------------------- the control

/// An entry, a Search button and a Clear button, wired together.
///
/// **It is not a `Widget`.** `Widget`'s constructor takes a GTK handle and
/// takes ownership of it, and a composite control owns several -- so it holds
/// its root rather than being one, and `Root()` is what goes into a layout.
/// Deriving would have meant claiming to be a single widget it is not.
public class SearchBox {
    Box root;
    Entry field;
    Button search;
    Button clear;
    Label status;

    // The subscribers. Empty closures would be a null function pointer, so
    // whether anyone is listening is a flag rather than a comparison.
    SearchRequested onSearch;
    bool hasSearch;

    TextChanged onChanged;
    bool hasChanged;

    SearchAllowed allowed;
    bool hasAllowed;

    int searches;

    public SearchBox(String prompt) {
        searches = 0;
        hasSearch = false;
        hasChanged = false;
        hasAllowed = false;

        root = new Box(true, 4);

        var row = new Box(false, 4);
        root.Pack(row, false);

        field = new Entry();
        field.SetPlaceholder(prompt);
        row.Pack(field, true);

        search = new Button("Search");
        row.Pack(search, false);

        clear = new Button("Clear");
        row.Pack(clear, false);

        status = new Label("");
        root.Pack(status, false);

        // The wiring, and the reason a control is worth writing: every one of
        // these is a method of *this* control bound to *this* object, so the
        // handlers know which SearchBox they belong to without a `sender`
        // parameter or a lookup table.
        search.OnClicked(this.Run);
        field.OnEntered(this.Run);
        clear.OnClicked(this.Clear);
        field.OnChanged(this.Changed);
    }

    // ------------------------------------------------------------ the surface

    /// What a layout puts in. Borrowed: the control owns it.
    public Widget Root() { return root; }

    public String Text() { return field.Text(); }

    public void SetText(String text) { field.SetText(text); }

    public void SetEnabled(bool enabled) {
        field.SetEnabled(enabled);
        search.SetEnabled(enabled);
        clear.SetEnabled(enabled);
    }

    /// Runs the search as if the button had been pressed, refusal and all.
    /// What a program calls to restore a saved search on startup.
    public void Submit() { Run(); }

    /// How many searches have run, which the demo prints and a real control
    /// would not have.
    public int Count() { return searches; }

    // ------------------------------------------------------------- the events

    /// Runs when the user presses Search, or Enter in the field.
    public void OnSearch(SearchRequested handler) {
        onSearch = handler;
        hasSearch = true;
    }

    /// Runs on every keystroke.
    public void OnChanged(TextChanged handler) {
        onChanged = handler;
        hasChanged = true;
    }

    /// Asked before a search runs. Answering false stops it, and the control
    /// says so in its own status line -- which is the sort of thing a control
    /// does that a raw widget will not.
    public void OnAllowed(SearchAllowed handler) {
        allowed = handler;
        hasAllowed = true;
    }

    // ------------------------------------------------------------- the wiring

    /// The one that does the work. Private, and bound to two widgets above.
    void Run() {
        var text = field.Text();

        if (text.ByteLength() == 0u) {
            status.SetText("nothing to search for");
            return;
        }

        if (hasAllowed && !allowed(text)) {
            status.SetText("refused: " + text);
            return;
        }

        searches = searches + 1;
        status.SetText("searched for " + text);

        if (hasSearch) { onSearch(text); }
    }

    void Clear() {
        field.SetText("");
        status.SetText("");
        if (hasChanged) { onChanged(""); }
    }

    void Changed() {
        if (hasChanged) { onChanged(field.Text()); }
    }
}

// ------------------------------------------------------------- the program

/// Somewhere for the results to go, so that a handler has an object to be
/// bound to rather than a lambda closing over one.
class Results {
    List<String> seen;
    Label view;

    public Results(Label into) {
        seen = new List<String>();
        view = into;
    }

    /// A method with exactly the shape of `SearchRequested`, which is what
    /// lets `search.OnSearch(results.Show)` work.
    public void Show(String text) {
        seen.Add(text);

        var all = new StringBuilder();
        for (nuint i = 0u; i < seen.Count(); i = i + 1u) {
            if (i > 0u) { all.Append(", "); }
            all.Append(seen.At(i));
        }

        view.SetText("results: " + all.ToText());
        Console.WriteLine("searched: " + text);
    }

    public nuint Count() { return seen.Count(); }
}

public int Main() {
    var app = new Application();

    if (!app.Start()) {
        Console.WriteLine("no display; set DISPLAY or run this on a desktop");
        return 1;
    }

    var window = new Window("A user control");
    window.SetDefaultSize(420, 220);
    app.AddWindow(window);

    var page = new Box(true, 8);
    page.SetPadding(12);
    window.Add(page);

    var heading = new Label("Type something and press Search");
    page.Pack(heading, false);

    // The control. Everything the program knows about it is on these lines.
    var search = new SearchBox("search terms");
    page.Pack(search.Root(), false);

    var found = new Label("results:");
    page.Pack(found, false);

    var results = new Results(found);

    // A bound method as the handler: the object it belongs to is the one that
    // has somewhere to put the answer.
    search.OnSearch(results.Show);

    // A lambda where there is no object to bind to, which is the other half of
    // the same type.
    search.OnChanged((text) => {
        heading.SetText(text.ByteLength() == 0u
            ? "Type something and press Search"
            : "About to search for " + text);
    });

    // And a refusal, which the control honours.
    search.OnAllowed((text) => { return text != "no"; });

    window.ShowAll();
    app.Run();
    return 0;
}
