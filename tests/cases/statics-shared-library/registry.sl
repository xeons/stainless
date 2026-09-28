// SPDX-License-Identifier: 0BSD
//
// A library has no entry point, so its statics are made as it is loaded and
// released as it is unloaded, in the same order an executable's would be.
module Registry;

import Standard.Collections;

extern "C" int printf(byte* format, ...);
extern "C" int fflush(void* stream);

class Held
{
    ~Held()
    {
        printf("library torn down\n");
        fflush(null);
    }
}

class Names
{
    public static List<String> All = new List<String>();

    static Names()
    {
        All.Add("registry");
        printf("library loaded\n");
        fflush(null);
    }
}

static readonly String s_name = "registry";
static Held? s_held = new Held();

export "C" int NameCount() => (int)Names.All.Count;

export "C" int NameLength() => (int)s_name.ByteLength();

export "C" int IsHeld() => s_held is null ? 0 : 1;
