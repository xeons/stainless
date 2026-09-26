// SPDX-License-Identifier: 0BSD
//
// C#'s other ways of writing a string -- verbatim, raw, interpolated either
// way -- and `"..."u8`, the bytes of one, and `@name`, a keyword as a name.
module LiteralForms;

import Standard.Console;
import Standard.Collections;

// A keyword as a name, across the boundary: C sees the bare word.
extern "C" int @abstract(int @int);
export "C" int @class(int @int) => @int * 2;

public class Template
{
    public String @default { get; }

    public Template(String @default)
    {
        this.@default = @default;
    }
}

public struct Header
{
    public byte[:] Magic;
    public int Version;
}

nuint CountBytes<T>(T[:] items)
{
    nuint count = 0u;
    foreach (var item in items)
        count++;
    return count;
}

String DescribeBytes(byte[:] bytes)
{
    var built = new StringBuilder();
    foreach (var b in bytes)
    {
        if (!built.IsEmpty)
            built.Append(" ");
        built.Append(Text.FormatInteger((ulong)b, "X2"));
    }
    return built.ToText();
}

int Main()
{
    // Verbatim: a backslash is itself, a doubled quote is one.
    Console.WriteLine(@"C:\temp\new ""quoted""");
    Console.WriteLine(@"first
second");

    // Raw, on one line: nothing is special but the closing quotes.
    Console.WriteLine("""a "quoted" \n word""");
    Console.WriteLine(""""three """ in a row"""");

    // Raw across lines: the closing line's indentation comes off every line.
    String json = """
        {
          "name": "stainless",

          "tags": ["c", "arc"]
        }
        """;
    Console.WriteLine(json);

    // Interpolated, verbatim and raw.
    int n = 42;
    String name = "arc";
    Console.WriteLine($@"C:\{name}\{n}.txt");
    Console.WriteLine(@$"say ""{name}""");
    Console.WriteLine($"""{name} = "{n}" """);
    Console.WriteLine($$"""{"name": "{{name}}", "braces": "{{{n}}}"}""");
    Console.WriteLine($"""
        [{name}]
          value = {n}
        """);

    // Bytes, not a String: static, immortal and a view.
    byte[:] greeting = "héllo"u8;
    Console.WriteLine($"{greeting.Length} bytes: {DescribeBytes(greeting)}");
    Console.WriteLine($"{DescribeBytes(greeting[1:3])}");
    Console.WriteLine($"{CountBytes("abc"u8)} {DescribeBytes(@"\n"u8)} {DescribeBytes("""{}"""u8)}");

    Header header;
    header.Magic = "SLv1"u8;
    header.Version = 1;
    var copy = header;
    Console.WriteLine($"{DescribeBytes(copy.Magic)} v{copy.Version}");

    var views = new List<byte[:]>();
    views.Add("ab"u8);
    views.Add("cd"u8);
    nuint total = 0u;
    foreach (var view in views)
        total += view.Length;
    Console.WriteLine($"{total}");

    IFunc<byte[:]> later = () => "later"u8;
    Console.WriteLine(DescribeBytes(later.Invoke()));

    // Keywords as names.
    int @int = 5;
    int @checked = @int + 1;
    var @var = new Template("tpl");
    Console.WriteLine($"{@int} {@checked} {@var.@default} {@class(4)} {@abstract(9)}");
    return 0;
}

public interface IFunc<T> { T Invoke(); }
