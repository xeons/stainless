// One name, declared twice or reachable two ways.
module Clashes;

import Net;
import Disk;

// A module is the unit of declaration, so a second one of any kind is a clash:
// a type, a generic, a constant and a static all share the one namespace.
public struct Thing { public int X; }
public struct Thing { public int Y; }               // SL0201

public class Pair<T> { public T Held; }
public class Pair<T> { public T Other; }            // SL0201

public const int Limit = 1;
public const int Limit = 2;                         // SL0201

using Alias = int;
using Alias = long;                                 // SL0201

// Two imported modules both export 'Buffer', so naming it bare has no answer.
Buffer Pick() {                                     // SL0273
    Buffer b;
    return b;
}

int Main() { return 0; }
