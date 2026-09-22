// SPDX-License-Identifier: 0BSD
//
// Direct3D 11: a window, a device, a shader and a triangle.
//
//   stainless run samples/directx/triangle.sl bindings/win32 -l user32
//
//   stainless run samples/directx/triangle.sl bindings/win32 -l user32 -- 60
//
// The argument is how many frames to draw before closing, which is what makes
// this usable from a script: with none it runs until the window is closed.
//
// **The only proof that a graphics layer works is a picture**, so this one
// draws something recognisable rather than clearing to a colour: a triangle
// whose corners are red, green and blue, on a dark blue field, with the
// interpolation between them doing the one thing a broken pipeline cannot
// fake.
module Triangle;

import Standard.Console;
import Standard.Env;
import Standard.Convert;
import Standard.Text;
import Win32;
import Win32.Handles;
import Win32.Kernel32;
import Win32.User32;
import Win32.Ui;
import Win32.Dxgi;
import Win32.D3D11;
import Windows.DirectX;
import Windows.DirectX11;

// The shader, as source rather than as a compiled blob: a sample that ships
// bytecode is a sample nobody can edit.
//
// `SV_Position` is the one output a vertex shader must produce, and it is in
// clip space -- so the coordinates below are already where they will appear,
// with -1 at the left and +1 at the top.
String GetShaderSource() =>
    "struct Vertex { float3 Position : POSITION; float3 Colour : COLOR; };\n" +
    "struct Fragment { float4 Position : SV_Position; float3 Colour : COLOR; };\n" +
    "\n" +
    "Fragment VertexMain(Vertex input)\n" +
    "{\n" +
    "    Fragment output;\n" +
    "    output.Position = float4(input.Position, 1.0);\n" +
    "    output.Colour = input.Colour;\n" +
    "    return output;\n" +
    "}\n" +
    "\n" +
    "float4 PixelMain(Fragment input) : SV_Target\n" +
    "{\n" +
    "    return float4(input.Colour, 1.0);\n" +
    "}\n";

// Six floats a vertex: a position and a colour. Written as bytes because that
// is what a vertex buffer takes, and `Float` is the one conversion needed.
byte[] BuildVertices()
{
    double[] numbers = [
        //  x      y     z      r     g     b
         0.0,   0.75, 0.0,   1.0,  0.2,  0.2,
         0.72, -0.6,  0.0,   0.2,  1.0,  0.3,
        -0.72, -0.6,  0.0,   0.3,  0.4,  1.0,
    ];

    byte[] bytes = new byte[numbers.Length * 4u];
    for (nuint i = 0u; i < numbers.Length; i++)
        WriteFloat(bytes, i * 4u, (float)numbers[i]);
    return bytes;
}

// A float's bits, little-endian. There is no reinterpret in the language, so
// this goes through a pointer -- which is what the cast is for.
void WriteFloat(byte[] into, nuint at, float value)
{
    float held = value;
    byte* bits = (byte*)&held;
    into[at] = bits[0u];
    into[at + 1u] = bits[1u];
    into[at + 2u] = bits[2u];
    into[at + 3u] = bits[3u];
}

// --------------------------------------------------------------- the window

nint HandleWindowMessage(HWND window, uint message, nuint wParam, nint lParam)
{
    if (message == WmDestroy)
    {
        PostQuitMessage(0);
        return 0;
    }

    return DefWindowProcW(window, message, wParam, lParam);
}

int Main()
{
    HMODULE instance = GetModuleHandleW(null);

    var windowClass = CreateWindowClass();
    windowClass.Procedure = HandleWindowMessage;
    windowClass.Instance = instance;
    windowClass.Cursor = LoadCursorW(null, CursorArrow());
    windowClass.ClassName = "StainlessDirectX".ToUtf16().ToPointer();

    if (RegisterClassExW(&windowClass) == 0u)
    {
        Console.WriteError("could not register the class: " + Win32.GetLastErrorMessage());
        return 1;
    }

    Rect wanted = CreateRect(0, 0, 640, 480);
    Rect outer = AdjustRectForFrame(wanted, WsOverlappedWindow, 0u);

    HWND window = CreateWindow("StainlessDirectX", "Stainless on Direct3D 11",
                               WsOverlappedWindow, UseDefault, UseDefault,
                               GetRectWidth(outer), GetRectHeight(outer), instance);
    if (window == null)
    {
        Console.WriteError("could not create the window: " + Win32.GetLastErrorMessage());
        return 1;
    }

    ShowWindow(window, SwShowNormal);

    // A window whose process was started from a console does not reliably take
    // the foreground, and sits behind the terminal that launched it.
    SetForegroundWindow(window);
    UpdateWindow(window);

    // ------------------------------------------------------------ the device

    var started = Graphics.CreateForWindow((void*)window, 640u, 480u);
    if (!started.Ok)
    {
        Console.WriteError("no Direct3D device");
        return 1;
    }

    var graphics = started.Value;
    Console.WriteLine("feature level " + DescribeFeatureLevel(graphics.FeatureLevel));

    var adapters = EnumerateAdapters();
    if (adapters.Count > 0u)
        Console.WriteLine("adapter: " + GetAdapterName(adapters[0u]));

    // ----------------------------------------------------------- the shaders

    var vertexCode = Hlsl.CompileShader(GetShaderSource(), "VertexMain", "vs_5_0");
    if (!vertexCode.Ok)
    {
        Console.WriteError("vertex shader:\n" + vertexCode.Error);
        return 1;
    }

    var pixelCode = Hlsl.CompileShader(GetShaderSource(), "PixelMain", "ps_5_0");
    if (!pixelCode.Ok)
    {
        Console.WriteError("pixel shader:\n" + pixelCode.Error);
        return 1;
    }

    VertexField[] fields = [
        VertexField.FromSemantic("POSITION", DXGI_FORMAT_R32G32B32_FLOAT),
        VertexField.FromSemantic("COLOR", DXGI_FORMAT_R32G32B32_FLOAT),
    ];

    var made = graphics.CreateMaterial(vertexCode.Value, pixelCode.Value, fields);
    if (!made.Ok)
    {
        Console.WriteError("could not make the material");
        return 1;
    }

    var material = made.Value;

    // 24 bytes a vertex: six floats.
    var built = graphics.CreateMesh(BuildVertices(), 24u, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    if (!built.Ok)
    {
        Console.WriteError("could not make the mesh");
        return 1;
    }

    var mesh = built.Value;
    Console.WriteLine("drawing " + Text.FromInteger((long)mesh.Count) + " vertices");

    // ------------------------------------------------------------- the frames

    long limit = 0;
    if (Env.ArgumentCount() > 0u)
        limit = Convert.ToLong(Env.ArgumentAt(0u)).GetValueOrDefault(0);

    long drawn = 0;
    while (PumpMessages())
    {
        graphics.Clear(0.06f, 0.07f, 0.12f, 1.0f);
        graphics.DrawMesh(material, mesh);

        // The frame, read back before it is presented -- a flip-model swap
        // chain leaves the buffer undefined afterwards.
        if (drawn == 2)
            graphics.SaveFrame("triangle.png");

        // The frame read back as a picture, which is the only thing that
        // proves anything was drawn. A flip-model present leaves the buffer
        // undefined, so this has to happen before it.
        if (drawn == 1)
            graphics.SaveFrame("triangle.png");

        int shown = graphics.PresentFrame(true);
        if (IsDeviceLost(shown))
        {
            Console.WriteError("the device was lost: " + DescribeHResult(shown));
            return 1;
        }

        drawn++;
        if (limit > 0 && drawn >= limit)
            break;
    }

    Console.WriteLine("drew " + Text.FromInteger(drawn) + " frames");
    graphics.Dispose();
    return 0;
}
