// A member's own `where` leaves it out of an instantiation that fails it, so
// calling it there is an error at the call. A dispatched member cannot be
// left out, so it may not have one.
module Bad;

public struct Box<T>
{
    public T Value;

    public Box(T value)
    {
        Value = value;
    }

    public void Reset() where T : zeroable
    {
        Value = default(T);
    }
}

public class Shelf<T>
{
    public virtual void Clear() where T : zeroable
    {
    }
}

public interface IResettable
{
    void Reset();
}

// An interface's table has a slot for Reset in every instantiation.
public class Tray<T> : IResettable
{
    public void Reset() where T : zeroable
    {
    }
}

int Main()
{
    var text = new Box<String>("kept");
    text.Reset();
    IResettable tray = new Tray<String>();
    return 0;
}
