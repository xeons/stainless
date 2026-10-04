// A binding the program names and reaches nothing of: its framework, which
// no Mac has, is not linked, so the program builds and runs.
module Unused;

#pragma comment(framework, "SLNoSuchFramework")

public extern "C" int SLNoSuchFunction();
