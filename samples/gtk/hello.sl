// SPDX-License-Identifier: 0BSD
//
// A GTK program: widgets, layout, events, a menu, a timer and custom drawing.
//
//   # GTK 3, with the development packages installed
//   stainless run samples/gtk/hello.sl bindings/gtk \
//       -l gtk-3 -l gdk-3 -l gobject-2.0 -l glib-2.0 -l cairo
//
//   # GTK 3, with only the runtime libraries
//   stainless run samples/gtk/hello.sl bindings/gtk \
//       -l :libgtk-3.so.0 -l :libgdk-3.so.0 -l :libgobject-2.0.so.0 \
//       -l :libglib-2.0.so.0 -l :libcairo.so.2
//
// The thing to notice is that **a handler is a closure** (§2.14.1): either a
// lambda that captures what it needs, or a method bound to the object that
// cares. There is no `sender` parameter to cast, no user-data pointer and no
// registration table -- the closure is boxed, retained for as long as GTK holds
// it, and released when the widget dies. `bindings/gtk/Signals.sl` is the
// twenty lines that make that true.
module Hello;

import Standard.Console;
import Gtk;

// What the program remembers. An ordinary class: the lambdas below capture it,
// so ARC keeps it alive exactly as long as they do.
class State
{
    public int Clicks;
    public double Fraction;
    public String Name;

    public State()
    {
        Clicks = 0;
        Fraction = 0.0;
        Name = "world";
    }
}

// The drawing, as an object rather than a lambda because it wants a name and
// some state. It implements nothing: `Paint` is an ordinary method, and
// `face.OnPaint(painting.Paint)` binds it to this object.
class Face
{
    State _state;

    public Face(State shared) => _state = shared;

    public void Paint(Canvas canvas, int width, int height)
    {
        // A paint handler is handed the size, because the two GTK versions ask
        // for it differently and a painter should not have to know which.
        canvas.SetHexColor(0x1E1E28);
        canvas.Clear();

        double middleX = (double)width / 2.0;
        double middleY = (double)height / 2.0;
        double radius = (middleX < middleY ? middleX : middleY) - 12.0;
        if (radius < 4.0)
            return;

        // A dial that fills as the progress does.
        canvas.SetHexColor(0x2E2E3E);
        canvas.AddCircle(middleX, middleY, radius);
        canvas.FillPath();

        canvas.SetHexColor(0x6EA8FE);
        canvas.SetLineWidth(8.0);
        canvas.SetRoundEnds(true);
        canvas.AddArc(middleX, middleY, radius - 6.0,
            -1.5707963, -1.5707963 + 6.283185 * _state.Fraction);
        canvas.StrokePath();

        // Text is drawn from its baseline, which is the one thing to remember.
        var count = Text.FromInteger((long)_state.Clicks);
        canvas.SetHexColor(0xE8E8F0);
        canvas.SetFont("Sans", radius / 2.0, true);
        canvas.DrawText(count, middleX - canvas.MeasureTextWidth(count) / 2.0,
                        middleY + radius / 6.0);
    }
}

public int Main()
{
    var app = new Application();

    // `gtk_init_check` rather than `gtk_init`: no display is an ordinary
    // outcome over ssh and in a container, and a toolkit that ends the program
    // before Main gets to speak is not a good citizen of a language with no
    // exceptions.
    if (!app.StartToolkit())
    {
        Console.WriteLine("no display; set DISPLAY or run this on a desktop");
        return 1;
    }

    var state = new State();

    var window = new Window("Stainless on GTK");
    window.SetDefaultSize(520, 380);
    app.AddWindow(window);

    var root = new Box(true, 0);
    window.Add(root);

    // ------------------------------------------------------------- the menu

    var bar = new MenuBar();

    var file = new Menu();
    var quit = new MenuItem("_Quit");
    quit.OnChosen(() => { app.Exit(); });
    file.AppendItem(quit);
    bar.AddMenu("_File", file);

    var help = new Menu();
    var about = new MenuItem("_About");
    about.OnChosen(() =>
    {
        Dialogs.ShowInformation(window, "About",
            "A GTK program written in Stainless.\n" +
            "Widgets, layout, events, a menu, a timer and custom drawing.");
    });
    help.AppendItem(about);
    help.AppendItem(MenuItem.CreateDivider());
    bar.AddMenu("_Help", help);

    root.PackStart(bar, false);

    // ------------------------------------------------------------ the body

    var body = new Box(false, 12);
    body.SetPadding(12);
    root.PackStart(body, true);

    // The drawing on the left, taking the slack.
    // A bound method as the painter: two words, the method and the object.
    var painting = new Face(state);

    var face = new DrawingArea();
    face.OnPaint(painting.Paint);
    face.SetSize(220, 220);
    body.PackStart(face, true);

    // The controls on the right.
    var side = new Box(true, 8);
    body.PackStart(side, false);

    var greeting = new Label("Hello, world");
    greeting.SetMarkup("<b>Hello, world</b>");
    side.PackStart(greeting, false);

    var name = new Entry();
    name.SetPlaceholder("your name");
    name.OnChanged(() =>
    {
        var typed = name.GetText();
        state.Name = typed.ByteLength() == 0u ? "world" : typed;
        greeting.SetText("Hello, " + state.Name);
    });
    side.PackStart(name, false);

    var bump = new Button("Click me");
    bump.OnClicked(() =>
    {
        state.Clicks = state.Clicks + 1;
        face.Invalidate();
    });
    side.PackStart(bump, false);

    side.PackStart(new Separator(false), false);

    // A grid: a child goes at a cell with a span, rather than between the
    // four grid lines an older toolkit would have wanted.
    var grid = new Grid();
    grid.SetSpacing(8, 4);
    side.PackStart(grid, false);

    grid.PlaceChild(new Label("Speed"), 0, 0);
    var speed = new SpinBox(1.0, 20.0, 1.0);
    speed.SetValue(5.0);
    grid.PlaceChild(speed, 1, 0);

    grid.PlaceChild(new Label("Style"), 0, 1);
    var style = new ComboBox();
    style.Add("Dial");
    style.Add("Ring");
    style.SetSelectedIndex(0);
    grid.PlaceChild(style, 1, 1);

    var animate = new CheckBox("Animate");
    animate.SetChecked(true);
    side.PackStart(animate, false);

    var progress = new ProgressBar();
    progress.SetText("idle");
    side.PackStart(progress, false);

    // ---------------------------------------------------------- the status

    var status = new StatusBar();
    status.SetText("ready");
    root.PackStart(status, false);

    // ----------------------------------------------------------- the timer

    // The only correct way to do something later in a GUI program: sleeping in
    // a handler stops the loop, and the loop is what repaints.
    app.RepeatEvery(40, () =>
    {
        if (animate.IsChecked())
        {
            state.Fraction = state.Fraction + speed.Value / 500.0;
            if (state.Fraction > 1.0)
                state.Fraction = 0.0;

            progress.SetFraction(state.Fraction);
            progress.SetText(Text.FromInteger((long)(state.Fraction * 100.0)) + "%");
            face.Invalidate();
        }

        status.SetText("clicks: " + Text.FromInteger((long)state.Clicks)
            + "   name: " + state.Name);

        // True keeps the timer running.
        return true;
    });

    // Asking before closing, which is what `OnClosing` answering true means.
    window.OnClosing(() =>
    {
        if (state.Clicks == 0)
            return false;

        switch (Dialogs.AskQuestion(window, "Close", "Close after "
                + Text.FromInteger((long)state.Clicks) + " clicks?"))
        {
            case Yes:       return false;
            case No:        return true;
            case Cancelled: return true;
        }
    });

    window.ShowAll();
    app.Run();
    return 0;
}
