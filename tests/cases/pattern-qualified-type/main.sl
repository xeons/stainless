// SPDX-License-Identifier: 0BSD
//
// Two modules each with an `Image`, told apart in a pattern by qualifying
// the type with its module, as a declaration and a `new` already could.
module Main;

import Standard.Console;
import Standard.Text;
import Shapes;
import Paint;
import Photo;

class Holder
{
    public int Image = 7;
}

String Describe(Shape shape)
{
    if (shape is Photo.Image photo)
        return "a photograph " + Text.FromInteger(photo.Width) + " wide";
    return shape switch
    {
        Paint.Image => "a painting",
        _ => "something else",
    };
}

String Name(Shape shape)
{
    switch (shape)
    {
        case Paint.Image:
            return "painted";
        case Photo.Image:
            return "photographed";
        default:
            return "drawn";
    }
}

int Main()
{
    Console.WriteLine(Describe(new Photo.Image(640)));
    Console.WriteLine(Describe(new Paint.Image()));
    Console.WriteLine(Describe(new Shape("a sketch")));
    Console.WriteLine(Name(new Paint.Image()) + ", " + Name(new Photo.Image(1)) + ", " +
                      Name(new Shape("a sketch")));

    // A local named as a module is a value, and `Photo.Image` on it is a field.
    var Photo = new Holder();
    Console.WriteLine(7 is Photo.Image ? "a field" : "not a field");
    return 0;
}
