// `zeroable` refuses a type whose zero would hold a null, and a `class`
// constraint beside it could never be met.
module Bad;

public struct Named
{
    public String Name;
}

T ZeroOf<T>() where T : zeroable => default(T);

T Never<T>() where T : class, zeroable => default(T);

int Main()
{
    String text = ZeroOf<String>();
    Named named = ZeroOf<Named>();
    return 0;
}
