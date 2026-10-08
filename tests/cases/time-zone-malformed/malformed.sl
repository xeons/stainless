// SPDX-License-Identifier: 0BSD
//
// A zone file whose header claims more entries than the file could hold is
// refused, not read. Taken at its word, a count of 0xFFFFFFFF wraps the
// offsets round to small numbers that pass the length check.
module TimeZoneMalformed;

import Standard.Console;
import Standard.Directory;
import Standard.Env;
import Standard.File;
import Standard.Path;
import Standard.Time;

int Main()
{
    var temp = Env.GetEnvironmentVariableOrDefault("TMPDIR", "/tmp");
    var directory = Path.Join(temp, "stainless-time-zone-malformed");
    Directory.CreateDirectory(directory);

    // "TZif", version 1, reserved, then the six counts: isUt, isStd, leap,
    // time, type, char. `time` is the hostile one.
    var data = new byte[64];
    data[0u] = (byte)'T';
    data[1u] = (byte)'Z';
    data[2u] = (byte)'i';
    data[3u] = (byte)'f';
    for (nuint i = 32u; i < 36u; i++)
        data[i] = 0xFF;
    data[39u] = 1;

    var path = Path.Join(directory, "Bad");
    File.WriteAllBytes(path, data);
    Env.SetEnvironmentVariable("TZDIR", directory);

    var found = TimeZoneInfo.FindSystemTimeZoneById("Bad");
    Console.WriteLine(found.Ok ? "read" : "refused");

    File.Delete(path);
    Directory.Delete(directory);
    return 0;
}
