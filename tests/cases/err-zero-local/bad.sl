// A local declared without a value is read only once every slot of it that
// has no zero value has been written, on every path. A struct may be written
// a field at a time; reading it whole, or a field not yet written, is refused.
module Bad;

public struct Holder
{
    public byte[] Data;
    public int Count;
}

String Pick(bool flag)
{
    String picked;
    if (flag)
        picked = "yes";
    return picked;
}

Holder Build(bool flag)
{
    Holder made;
    made.Count = 1;
    if (flag)
        return made;
    made.Data = [1];
    return made;
}

int Main()
{
    Holder partial;
    partial.Count = 2;
    var length = partial.Data.Length;
    return (int)length;
}
