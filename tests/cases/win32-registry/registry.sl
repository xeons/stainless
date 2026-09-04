// The registry, read only.
//
// This case never writes. A test that ran on every build should not leave a key
// behind on the machine that ran it, so what is checked here is the shape of the
// API rather than a round trip: that a key opens, that a value of the right kind
// reads, that a value of the wrong kind is refused rather than reinterpreted,
// and that a missing name is `NotFound` rather than an empty string.
//
// `SOFTWARE\Microsoft\Windows NT\CurrentVersion` is used because it is present
// and readable on every Windows since NT. Its *values* differ from machine to
// machine, so none of them is printed.
module Win32Registry;

import Standard.Console;
import Win32;
import Win32.AdvApi32;
import Win32.Handles;
import Win32.Registry;

static readonly String CurrentVersion = "SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion";

String Why(RegistryError error) {
    switch (error) {
        case RegistryError.None:         return "none";
        case RegistryError.NotFound:     return "not found";
        case RegistryError.AccessDenied: return "access denied";
        case RegistryError.MoreData:     return "more data";
        case RegistryError.NoMoreItems:  return "no more items";
        default:                         return "other";
    }
}

int Main() {
    // --- a key that is not there --------------------------------------------
    var missing = Registry.OpenRead(AdvApi32.LocalMachine(), "SOFTWARE\\NoSuchKeyHere");
    switch (missing) {
        case Ok found:
            Console.WriteLine("WRONG: a key that should not exist opened");
            Registry.Close(found.Value);
            break;
        case Fail why:
            Console.WriteLine("a missing key fails with: " + Why(why.Error));
            break;
    }

    // --- a key that is -------------------------------------------------------
    var opened = Registry.OpenRead(AdvApi32.LocalMachine(), CurrentVersion);
    switch (opened) {
        case Fail why:
            Console.WriteLine("WRONG: could not open CurrentVersion: " + Why(why.Error));
            return 1;

        case Ok held:
            HKEY key = held.Value;

            // ProductName is a REG_SZ on every Windows. Its text differs, so
            // only its shape is checked.
            var product = Registry.ReadString(key, "ProductName");
            switch (product) {
                case Ok text:
                    Console.WriteLine("ProductName is a non-empty string: "
                        + Text.FromBool(!text.Value.IsEmpty()));
                    Console.WriteLine("and it begins with 'Windows': "
                        + Text.FromBool(text.Value.Substring(0u, 7u) == "Windows"));
                    break;
                case Fail why:
                    Console.WriteLine("WRONG: ProductName did not read: " + Why(why.Error));
                    break;
            }

            // A REG_SZ read as a REG_DWORD is refused rather than reinterpreted:
            // the kind is checked, and four bytes of text is not a number.
            var wrongKind = Registry.ReadUInt(key, "ProductName");
            Console.WriteLine("reading a string as a number fails: "
                + Text.FromBool(!wrongKind.Ok));

            // A name that is not there.
            var absent = Registry.ReadString(key, "NoSuchValueHere");
            switch (absent) {
                case Ok text:
                    Console.WriteLine("WRONG: a value that should not exist read");
                    break;
                case Fail why:
                    Console.WriteLine("a missing value fails with: " + Why(why.Error));
                    break;
            }

            // Enumeration. The names differ per machine; the counts agreeing
            // with what enumeration produces does not.
            var counts = Registry.Counts(key);
            Console.WriteLine("it has subkeys: " + Text.FromBool(counts.SubKeys > 0u));
            Console.WriteLine("it has values: " + Text.FromBool(counts.Values > 0u));
            Console.WriteLine("the first value has a name: "
                + Text.FromBool(!Registry.ValueName(key, 0u).IsEmpty()));
            Console.WriteLine("the first subkey has a name: "
                + Text.FromBool(!Registry.SubKey(key, 0u).IsEmpty()));
            Console.WriteLine("one past the end is empty: "
                + Text.FromBool(Registry.SubKey(key, counts.SubKeys).IsEmpty()));

            Console.WriteLine("closed: " + Text.FromBool(Registry.Close(key)));
            break;
    }

    // --- the access mask -------------------------------------------------------
    //
    // Asking for write access to a key that is not there is still NotFound: the
    // path is resolved before the rights are, so the mask is not what decides
    // this. Whether HKLM itself opens for writing depends on whether the test
    // is running elevated, which is why that is not what is asked.
    var writable = Registry.Open(AdvApi32.LocalMachine(), "SOFTWARE\\NoSuchKeyHere", KeyWrite);
    switch (writable) {
        case Ok key:
            Console.WriteLine("WRONG: a key that should not exist opened for writing");
            Registry.Close(key.Value);
            break;
        case Fail why:
            Console.WriteLine("a missing key is missing whatever is asked of it: "
                + Why(why.Error));
            break;
    }

    // HKEY_CURRENT_USER is always openable by the user running the program, and
    // opening it reads nothing and changes nothing.
    var mine = Registry.OpenRead(AdvApi32.CurrentUser(), "Software");
    switch (mine) {
        case Ok key:
            Console.WriteLine("HKCU\\Software opens: true");
            Registry.Close(key.Value);
            break;
        case Fail why:
            Console.WriteLine("WRONG: HKCU\\Software did not open: " + Why(why.Error));
            break;
    }
    return 0;
}
