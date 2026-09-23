// SPDX-License-Identifier: 0BSD
//
// A `@tag` is a claim about the declaration under it, and every claim here is
// one the compiler has already resolved for itself: whether there is a
// parameter of that name, whether the call can fail that way, whether the name
// it points at exists. Each of these gets that wrong, and the one at the
// bottom gets all of it right and says nothing.
module Notes;

import Standard.Console;
import Standard.Text;

public enum ReadError
{
    None,
    NotFound,
    NoSpace,
}

/// Reads one.
///
/// @param pth where to read from
/// @typeparam T it takes none
/// @failure ReadError.Vanished no such case
/// @see Standard.NoSuchModule
/// @summary the prose above is the summary
public Result<String, ReadError> ReadText(String path)
{
    return Ok(path);
}

/// Adds them.
///
/// @param a the first
/// @param a and again
public int Add(int a, int b) => a + b;

/// Says nothing.
///
/// @returns what a void function answers
/// @failure ReadError.NoSpace it cannot fail
public void Quiet() { }

/// A shape.
///
/// @param x a type takes no parameters
public class Shape
{
    /// What it is called.
    ///
    /// @value the name, never empty
    public String Name { get; set; }
}

/// Reads one properly, and warns about nothing.
///
/// @param path  where to read from, absolute or relative to the working
///              directory
/// @returns the contents
/// @failure ReadError.NotFound  there is no file there
/// @failure ReadError.NoSpace   the disk filled up
/// @see Shape
/// @seealso Standard.Console
public Result<String, ReadError> ReadProperly(String path)
{
    return Ok(path);
}

int Main()
{
    var shape = new Shape();
    shape.Name = "circle";

    Console.WriteLine(shape.Name + " " + Text.FromInteger((long)Add(1, 2)));
    Quiet();
    return 0;
}
