// SPDX-License-Identifier: 0BSD
//
// A library whose functions take `params`. The consumer gathers the elements
// at its own call sites, so the metadata has to say which parameter is one.
module Library.Numbers;

public int Total(params int[] values)
{
    int total = 0;
    foreach (int value in values)
        total += value;
    return total;
}

public String Joined(String separator, params String[:] parts)
{
    var joined = "";
    for (nuint i = 0; i < parts.Length; i++)
        joined = i == 0 ? parts[i] : joined + separator + parts[i];
    return joined;
}
