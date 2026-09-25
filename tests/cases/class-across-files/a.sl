module Parts;

import Standard.Console;
import Standard.Text;

public class Surface
{
    public int Width;

    public Surface(int width) => Width = width;

    public virtual String Describe() => "a surface";
}

public class Window : Surface
{
    public String Note;

    public Window()
    {
        base(640);
        InitializeComponent();
        Note = "own state";
    }

    public override String Describe() => Caption + ", " + Note;

    public void Click() => Clicks++;
}

int Main()
{
    var window = new Window();
    window.Click();
    window.Click();

    Surface surface = window;
    Console.WriteLine(surface.Describe());
    Console.WriteLine(Text.FromInteger(window.Width));
    Console.WriteLine(Text.FromInteger(window.Clicks));
    return 0;
}
