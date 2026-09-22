// SPDX-License-Identifier: 0BSD
//
// `Convert.ToDouble` reads all of its text however long it is, and a number
// too large for a double is out of range rather than an infinity. Base64
// padding is only padding at the end.
module TextConvertEdges;

import Standard.Console;
import Standard.Text;
import Standard.Convert;

void ShowDouble(String label, Result<double, ConvertError> parsed)
{
    switch (parsed)
    {
        case Ok ok: Console.WriteLine(label + " " + Text.FromDouble(ok.Value)); break;
        case Fail failed: Console.WriteLine(label + " " + ErrorName(failed.Error)); break;
    }
}

void ShowBytes(String label, Result<byte[], ConvertError> decoded)
{
    switch (decoded)
    {
        case Ok ok:
            var built = new StringBuilder();
            built.Append(label);
            for (nuint i = 0; i < ok.Value.Length; i++)
            {
                built.Append(" ");
                built.AppendInteger((long)ok.Value[i]);
            }
            Console.WriteLine(built.ToText());
            break;

        case Fail failed:
            Console.WriteLine(label + " " + ErrorName(failed.Error));
            break;
    }
}

String ErrorName(ConvertError error)
{
    switch (error)
    {
        case ConvertError.Empty: return "empty";
        case ConvertError.Malformed: return "malformed";
        case ConvertError.OutOfRange: return "out-of-range";
        default: return "unknown";
    }
}

int Main()
{
    ShowDouble("leading-zeros", Convert.ToDouble("0".Repeat(600) + "1.5"));
    ShowDouble("long-mantissa", Convert.ToDouble("1" + "0".Repeat(520) + "e-520"));
    ShowDouble("long-fraction", Convert.ToDouble("0." + "0".Repeat(700) + "1e701"));
    ShowDouble("huge", Convert.ToDouble("1e999"));
    ShowDouble("huge-negative", Convert.ToDouble("-1e999"));
    ShowDouble("huge-digits", Convert.ToDouble("9".Repeat(400)));
    ShowDouble("tiny", Convert.ToDouble("1e-999"));
    ShowDouble("largest", Convert.ToDouble("1.7976931348623157e308"));

    ShowBytes("b64-padded", Convert.FromBase64("QQ=="));
    ShowBytes("b64-unpadded", Convert.FromBase64("QQ"));
    ShowBytes("b64-wrapped-padding", Convert.FromBase64("QUI=\n"));
    ShowBytes("b64-middle", Convert.FromBase64("QQ==QQ=="));
    ShowBytes("b64-middle-one", Convert.FromBase64("QUI=QQ"));
    ShowBytes("b64-short-padding", Convert.FromBase64("QQ="));
    ShowBytes("b64-long-padding", Convert.FromBase64("QUJD===="));
    return 0;
}
