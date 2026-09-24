// SPDX-License-Identifier: 0BSD
//
// `--static-teardown`: what a mutable static holds is let go of when the
// program ends, in the opposite order to the one it was given it in.
//
// Reverse, because that is the order in which nothing is yet depended on. The
// binder sorts the initializers so a static is made after everything it reads,
// so undoing them backwards means a destructor never runs against a static
// that has already been emptied -- C++'s rule, for C++'s reason.
//
// A `readonly` static is not torn down. It is made immortal as it is stored,
// which is what takes the reference traffic off a value every thread can see,
// and an immortal object is one nothing releases. What it holds lives to
// process exit, and that is the bargain the word makes.
module Teardown;

import Standard.Console;
import Standard.Collections;

public class Noisy
{
    public String Tag;
    public Noisy(String tag) { Tag = tag; }
    ~Noisy() { Console.WriteLine("  ~" + Tag); }
}

// Initialized in this order, so torn down bottom to top.
static Noisy s_first = new Noisy("first");
static List<Noisy> s_second = new List<Noisy>();
static Noisy s_third = new Noisy("third");

// Never released: immortal from the moment it is stored.
static readonly Noisy s_kept = new Noisy("readonly, and so kept");

int Main()
{
    s_second.Add(new Noisy("held by the list"));

    Console.WriteLine("first  " + s_first.Tag);
    Console.WriteLine("third  " + s_third.Tag);
    Console.WriteLine("kept   " + s_kept.Tag);
    Console.WriteLine("main returning");
    return 0;
}
