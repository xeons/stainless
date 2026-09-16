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
}

String Ambiguous()
{
    var choices = new Choices();
    return choices.Show(1);       // a literal fits both
}

String Missing()
{
    var choices = new Choices();
    return choices.Show("text");  // fits neither
}

int Main() => 0;
