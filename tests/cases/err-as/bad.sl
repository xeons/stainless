// SPDX-License-Identifier: 0BSD
//
// What `as` refuses, and why each one is a mistake rather than a null.
module Bad;

public class Alpha { }
public sealed class Beta { }
public interface IThing { void Do(); }

variant Payload
{
    Number(int Value);
    Empty;
}

int Main()
{
    Alpha alpha = new Alpha();

    // Neither derives from the other, so this could only ever be null.
    Beta? never = alpha as Beta;

    // The '?' says twice what 'as' already answers.
    Alpha? twice = alpha as Alpha?;

    // A value is not a reference to an object, so there is nothing to ask.
    var number = 3 as Alpha;

    // Sealed, and does not implement it: nothing deriving from it can either.
    Beta beta = new Beta();
    IThing? impossible = beta as IThing;

    // Which case a variant holds is 'is' or a 'switch'.
    Payload payload = Empty();
    var held = payload as Alpha;
    return 0;
}
