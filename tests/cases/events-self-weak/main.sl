// An object never keeps itself alive through its own subscriptions.
module Main;

import Standard.Console;
import Standard.Text;

public closure void PressHandler(Button sender);

public class Button
{
    public event PressHandler Pressed;

    public void Press() => Pressed(this);

    /// Drops every subscriber, which only the declaring type may do.
    public void ForgetSubscribers() { Pressed.Clear(); }
}

static int s_formsFreed = 0;
static int s_loggersFreed = 0;
static int s_presses = 0;

/// Holds its button, and subscribes itself to it: the shape of every form.
public class Form
{
    Button _save;

    public Form(bool byLambda)
    {
        _save = new Button();
        if (byLambda)
        {
            _save.Pressed += (sender) => { this.CountPress(); };
        }
        else
        {
            _save.Pressed += this.OnSavePressed;
        }
    }

    ~Form() { s_formsFreed++; }

    public Button SaveButton => _save;

    public void OnSavePressed(Button sender) => CountPress();

    public void CountPress() { s_presses++; }

    public void StopListening() { _save.Pressed -= this.OnSavePressed; }
}

public class Logger
{
    ~Logger() { s_loggersFreed++; }

    public void OnPressed(Button sender) { s_presses++; }
}

void Say(String what, bool passed)
{
    Console.WriteLine((passed ? "ok   " : "FAIL ") + what);
}

void MakeAndDrop(bool byLambda)
{
    var form = new Form(byLambda);
    form.SaveButton.Press();
}

Button KeepButtonOfDroppedForm()
{
    var form = new Form(false);
    return form.SaveButton;
}

int Main()
{
    s_presses = 0;
    MakeAndDrop(false);
    Say("a form subscribed to its own button by method runs its handler", s_presses == 1);
    Say("and is freed when dropped", s_formsFreed == 1);

    MakeAndDrop(true);
    Say("by a lambda using this, it runs too", s_presses == 2);
    Say("and is freed too", s_formsFreed == 2);

    var kept = new Form(false);
    kept.SaveButton.Press();
    kept.StopListening();
    kept.SaveButton.Press();
    Say("-= removes a weak subscription", s_presses == 3);

    var button = new Button();
    {
        var logger = new Logger();
        button.Pressed += logger.OnPressed;
    }
    button.Press();
    Say("another object's subscription still keeps it alive", s_loggersFreed == 0 && s_presses == 4);

    button.ForgetSubscribers();
    button.Press();
    Say("Clear drops every subscriber, and releases them", s_presses == 4 && s_loggersFreed == 1);

    var orphan = KeepButtonOfDroppedForm();
    orphan.Press();
    Say("a button that outlives its form raises harmlessly", s_presses == 4 && s_formsFreed == 3);
    return 0;
}
