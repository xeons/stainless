// A class declared in two files, as a form designer writes one.
//
// This file sorts first and says nothing about what the class derives from;
// the other one does. Each adds fields.
module Parts;

public class Window
{
    public String Caption;
    public int Clicks;

    void InitializeComponent()
    {
        Caption = "Hello";
        Clicks = 0;
    }
}
