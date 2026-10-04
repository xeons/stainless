module ObjCCategories;

import Standard.Console;
import Standard.ObjC;
import Strings;
import Drawing;

String Text(NSString text) => Standard.Text.FromBytes(text.Utf8, text.Length);

int Main()
{
    var hello = NSString.FromUtf8("Hello");
    Console.WriteLine(Text(hello.Shouted()));
    Console.WriteLine(Text(hello.Lowercase));

    Uppering upper = hello;
    Console.WriteLine(Text(upper.Uppercase));
    return 0;
}
