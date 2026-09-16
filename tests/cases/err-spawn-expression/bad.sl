// SPDX-License-Identifier: 0BSD
module Bad;

int Work() => 1;

int Main()
{
    int total = 0;

    parallel
    {
        // A spawned call has no value until the join, so there is nothing here
        // for the addition to add, and nothing for the declaration to hold.
        total = spawn Work() + 1;
        int local = spawn Work();
    }

    return total;
}
