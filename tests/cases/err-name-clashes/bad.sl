// One name, declared twice or reachable two ways.
module Clashes;

import Net;
import Disk;

// A module is the unit of declaration, so a second one of any kind is a clash:
// a type, a generic, a constant and a static all share the one namespace.
public struct Thing { public int X; }
public struct Thing { public int Y; }               // SLN0001

public class Pair<T> { public T Held; }
public class Pair<T> { public T Other; }            // SLN0001

public const int Limit = 1;
public const int Limit = 2;                         // SLN0001

using Alias = int;
using Alias = long;                                 // SLN0001

// Two imported modules both export 'Buffer', so naming it bare has no answer.
Buffer Pick() // SLN0015
{
    Buffer b;
    return b;
}

int Main() => 0;
