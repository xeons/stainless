// SPDX-License-Identifier: 0BSD
module Bad;

interface IBad
{
    bool Same(int other);
    bool Same(String other);      // an interface method has one dispatch slot
}

class Duplicate
{
    public int Take(int n) => n;
    public bool Take(int n) => true; // the same parameters
}

class Choices
{
    public String Show(long n) => "long";
    public String Show(nuint n) => "nuint";
    public String Pair(int a, long b) => "int, long";
    public String Pair(long a, int b) => "long, int";
}

String Ambiguous()
{
    var choices = new Choices();
    return choices.Pair(1, 2);    // each is better for one argument
}

String Missing()
{
    var choices = new Choices();
    return choices.Show("text");  // fits neither
}

int Main() => 0;
