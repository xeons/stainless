// SPDX-License-Identifier: 0BSD
module Bad;

// A generic function is a template until it is called, and a template with
// no body has nothing to instantiate.
T Pick<T>(T value);

class Helper
{
    public static T Take<T>(T value);
}

int Main() => Pick<int>(1) + Helper.Take<int>(2);
