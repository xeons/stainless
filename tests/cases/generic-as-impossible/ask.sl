// SPDX-License-Identifier: 0BSD
//
// An 'as' that can never succeed is an error where it is written with the
// types known (SL0612), and null inside a generic, where the template asks it
// for every type argument.
module GenericAsImpossible;

import Standard.Console;

public interface IClosable
{
    void Close();
}

public sealed class Plain
{
}

public sealed class Door : IClosable
{
    public void Close() => Console.WriteLine("closed");
}

static int s_asked = 0;

T Counted<T>(T value)
{
    s_asked++;
    return value;
}

bool TryClose<T>(T value)
    where T : class
{
    IClosable? closable = Counted<T>(value) as IClosable;
    if (closable == null)
        return false;
    closable.Close();
    return true;
}

public int Main()
{
    Console.WriteLine($"door {TryClose<Door>(new Door())}");
    Console.WriteLine($"plain {TryClose<Plain>(new Plain())}");
    Console.WriteLine($"evaluated {s_asked}");
    return 0;
}
