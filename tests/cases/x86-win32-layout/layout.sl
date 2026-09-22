// The Win32 structures whose shape depends on the width of a pointer,
// measured on x86 against the sizes the Windows headers give there.
//
// `win32-layout` is the same check on x64. A field written `long` where C has
// `LPARAM`, or padding counted for one width only, is right on one of the two
// and wrong on the other, so each width needs its own case.
module Win32LayoutX86;

import Standard.Console;
import Win32.User32;
import Win32.ComDlg32;
import Win32.ComCtl32;

void Check(String name, nuint measured, nuint wanted)
{
    Console.WriteLine((measured == wanted ? "ok   " : "WRONG ") + name
        + " = " + Text.FromInteger(measured)
        + (measured == wanted ? "" : ", wanted " + Text.FromInteger(wanted)));
}

int Main()
{
    Check("MSG", sizeof(Msg), 28u);
    Check("WNDCLASSEXW", sizeof(WindowClass), 48u);
    Check("PAINTSTRUCT", sizeof(PaintStruct), 64u);
    Check("WNDPROC", sizeof(WindowProcedure), 4u);

    Check("OPENFILENAMEW", sizeof(OpenFileName), 88u);
    Check("CHOOSECOLORW", sizeof(ChooseColor), 36u);
    Check("CHOOSEFONTW", sizeof(ChooseFont), 60u);

    Check("TBBUTTON", sizeof(ToolBarButton), 20u);
    Check("TOOLINFOW", sizeof(ToolInfo), 48u);
    Check("TTTOOLINFOW_V1_SIZE", (nuint)ToolInfoV1Size, 40u);
    Check("NMCUSTOMDRAW", sizeof(CustomDraw), 48u);
    return 0;
}
