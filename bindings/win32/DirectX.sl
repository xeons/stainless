// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This file is part of the Stainless runtime library. It is free
// software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any
// later version.
//
// It is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// As an additional permission under section 7 of that License, compiling
// a program with Stainless does not by itself place that program under
// the GNU General Public License. See LICENSE.RUNTIME.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

// What Direct3D 11 and Direct3D 12 both need.
//
// The two are different enough that almost nothing is shared between them --
// which is the point of D3D12 and is why `Windows.DirectX11` and
// `Windows.DirectX12` are separate modules rather than one with a switch. What
// *is* shared is here: the adapters, because DXGI enumerates for both; the
// shader compiler, because both take DXBC; and the failure vocabulary.
//
// It names dxgi and d3dcompiler with a pragma, so a program compiling it needs
// no `-l` for either.
module Windows.DirectX;

import Standard.Text;
import Standard.Collections;
import Standard.Com;
import Win32.Dxgi;
import Win32.D3DCompiler;

#if WINDOWS

#pragma comment(lib, "dxgi")
#pragma comment(lib, "d3dcompiler")

/// Why something graphical did not happen.
///
/// One enum for both versions: a program that fails to make a device does not
/// much care which API it was asking.
public enum GraphicsError
{
    /// No adapter would make a device at the feature level asked for. On a
    /// machine with a driver this means the feature level; on one without, it
    /// means there is no Direct3D at all.
    NoDevice,

    /// DXGI would not enumerate, which is a broken installation rather than a
    /// missing card.
    NoAdapter,

    /// The swap chain description was refused. Nearly always a flip-model
    /// chain with multisampling, one buffer, or an sRGB buffer format.
    NoSwapChain,

    /// A shader did not compile, or its bytecode was refused.
    /// `Hlsl.CompileShader` answers the compiler's own message, which says far
    /// more than this does.
    Shader,

    /// A buffer, a texture or a view could not be made -- out of video memory,
    /// or a description the runtime refused.
    Resource,

    /// The adapter is gone: a driver update, a reset, or a hang the driver
    /// gave up on. **Everything made from the device is dead** and the only
    /// answer is to build it all again.
    DeviceLost,

    /// The machine has the API and not this part of it.
    Unsupported,
}

/// Whether an `HRESULT` says the call worked. The sign bit is the whole test.
public bool Succeeded(int result) => result >= 0;

/// Whether it says the call did not.
public bool Failed(int result) => result < 0;

/// An `HRESULT` from DXGI or Direct3D as text.
///
/// The DXGI codes are named because they are the ones a program actually sees
/// and because "0x887A0001" says nothing to anybody. Everything else is
/// reported as its hex, since inventing prose for a facility this does not
/// know would be worse than showing the number.
public String DescribeHResult(int result)
{
    if (result == 0)
        return "ok";
    if (result == DXGI_STATUS_OCCLUDED)
        return "the window is hidden, so nothing was presented";
    if (result == DXGI_ERROR_NOT_FOUND)
        return "not found (the end of an enumeration)";
    if (result == DXGI_ERROR_INVALID_CALL)
        return "invalid call: the description asked for something that cannot be made";
    if (result == DXGI_ERROR_DEVICE_REMOVED)
        return "the device was removed; everything made from it is dead";
    if (result == DXGI_ERROR_DEVICE_RESET)
        return "the device was reset";
    if (result == DXGI_ERROR_DEVICE_HUNG)
        return "the device hung on this program's own commands";
    if (result == DXGI_ERROR_WAS_STILL_DRAWING)
        return "still drawing";
    if (result == DXGI_ERROR_UNSUPPORTED)
        return "unsupported";
    if (result == DXGI_ERROR_SDK_COMPONENT_MISSING)
        return "the graphics tools feature is not installed, so there is no debug layer";
    if (result == 0x80070057)
        return "invalid argument";
    if (result == 0x8007000E)
        return "out of memory";
    if (result == 0x80004001)
        return "not implemented";
    if (result == 0x80004002)
        return "no such interface";

    return "error 0x" + FormatHexadecimal((uint)result);
}

/// Whether a failure means the device is gone, which is the one failure a
/// render loop has to tell from the rest: everything else is a mistake in the
/// program, and this one is not.
public bool IsDeviceLost(int result) =>
    result == DXGI_ERROR_DEVICE_REMOVED || result == DXGI_ERROR_DEVICE_RESET ||
    result == DXGI_ERROR_DEVICE_HUNG;

/// A feature level as the version it names.
public String DescribeFeatureLevel(int level)
{
    if (level == 0xc100)
        return "12.1";
    if (level == 0xc000)
        return "12.0";
    if (level == 0xb100)
        return "11.1";
    if (level == 0xb000)
        return "11.0";
    if (level == 0xa100)
        return "10.1";
    if (level == 0xa000)
        return "10.0";
    if (level == 0x9300)
        return "9.3";
    if (level == 0x9200)
        return "9.2";
    if (level == 0x9100)
        return "9.1";
    return "unknown";
}

String FormatHexadecimal(uint value)
{
    var digits = "0123456789ABCDEF";
    var builder = new StringBuilder();

    for (int shift = 28; shift >= 0; shift = shift - 4)
    {
        nuint at = (nuint)((value >> (uint)shift) & 0xFu);
        builder.Append(digits.Substring(at, 1u));
    }
    return builder.ToText();
}

// ================================================================= adapters

/// One graphics adapter, described.
public struct AdapterInfo
{
    /// Which index it was found at, which is what to pass back to `Adapter`.
    public uint Index;

    /// PCI vendor: 0x10DE is NVIDIA, 0x1002 AMD, 0x8086 Intel.
    public uint VendorId;

    public uint DeviceId;

    /// How much memory is the card's own, in bytes. Zero for a software
    /// adapter and for an integrated one that has none of its own.
    public nuint DedicatedMemory;

    /// Whether this is WARP, the software renderer, rather than hardware.
    public bool IsSoftware;
}

/// The name of an adapter, which is UTF-16 in the description and so needs a
/// conversion rather than a field.
public String GetAdapterName(AdapterInfo adapter)
{
    var factory = CreateFactory();
    if (factory == null)
        return "";

    byte* raw = null;
    if (((IDXGIFactory1)factory).EnumAdapters1(adapter.Index, &raw) < 0 || raw == null)
        return "";

    var found = (IDXGIAdapter1)raw;
    DXGI_ADAPTER_DESC1 description;
    if (found.GetDesc1(&description) < 0)
        return "";

    return Text.FromNullTerminatedUtf16(&description.Description[0u]);
}

/// Every adapter DXGI knows about, in the order it prefers them.
///
/// Index 0 is the one to use unless a program has been told otherwise. The
/// software adapter is included and marked, because a program that wants to
/// refuse it has to be able to see it.
public List<AdapterInfo> EnumerateAdapters()
{
    var found = new List<AdapterInfo>();
    var factory = CreateFactory();
    if (factory == null)
        return found;

    var enumerator = (IDXGIFactory1)factory;

    for (uint index = 0u; index < 64u; index++)
    {
        byte* raw = null;
        if (enumerator.EnumAdapters1(index, &raw) < 0 || raw == null)
            break;

        var adapter = (IDXGIAdapter1)raw;
        DXGI_ADAPTER_DESC1 description;
        if (adapter.GetDesc1(&description) < 0)
            continue;

        AdapterInfo info;
        info.Index = index;
        info.VendorId = description.VendorId;
        info.DeviceId = description.DeviceId;
        info.DedicatedMemory = description.DedicatedVideoMemory;
        info.IsSoftware = (description.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) != 0u;
        found.Add(info);
    }

    return found;
}

/// A DXGI factory, or null when DXGI will not start.
///
/// **Made fresh each time on purpose.** A factory stops being current the
/// moment a display is plugged or unplugged, and a cached one then enumerates
/// hardware that is no longer there.
public IDXGIFactory1? CreateFactory()
{
    byte* raw = null;
    if (CreateDXGIFactory1(iidof(IDXGIFactory1), &raw) < 0 || raw == null)
        return null;
    return (IDXGIFactory1)raw;
}

// ================================================================== shaders

/// HLSL, compiled.
///
/// ```csharp
/// var compiled = Hlsl.CompileShader(source, "VertexMain", "vs_5_0");
/// if (!compiled.Ok)
/// {
///     Console.WriteLine(compiled.Error);     // the compiler's own message
///     return;
/// }
/// ```
public static class Hlsl
{
    /// `source` compiled for `target` -- `"vs_5_0"`, `"ps_5_0"` -- starting at
    /// `entryPoint`.
    ///
    /// **The failure is the compiler's text**, not a code: an HLSL error names
    /// a line and a column and says what is wrong, and reducing that to
    /// `GraphicsError.Shader` would throw away the only thing that helps.
    public static Result<byte[], String> CompileShader(String source, String entryPoint,
                                                       String target)
    {
        return CompileShader(source, entryPoint, target,
                       D3DCOMPILE_ENABLE_STRICTNESS | D3DCOMPILE_OPTIMIZATION_LEVEL3);
    }

    /// The same, with the `D3DCOMPILE_*` flags spelled out.
    public static Result<byte[], String> CompileShader(String source, String entryPoint,
                                                       String target, uint flags)
    {
        byte* code = null;
        byte* errors = null;

        int result = D3DCompile(source.ToPointer(), source.ByteLength(), null, null, null,
                                entryPoint.ToPointer(), target.ToPointer(), flags, 0u,
                                &code, &errors);

        // The error blob is filled on a warning as well as on a failure, so it
        // is adopted either way and released by the scope.
        String message = "";
        if (errors != null)
        {
            var blob = (ID3DBlob)errors;
            message = Text.FromNullTerminated(blob.GetBufferPointer());
        }

        if (result < 0)
        {
            return Fail(message.ByteLength() > 0u
                ? message
                : "the shader compiler failed: " + DescribeHResult(result));
        }

        if (code == null)
            return Fail("the shader compiler produced nothing");

        var bytecode = (ID3DBlob)code;
        nuint size = bytecode.GetBufferSize();
        byte* start = bytecode.GetBufferPointer();

        // Copied out rather than handed back as a pointer: the blob is
        // released at the end of this scope, and a `byte[]` is what every
        // caller wants anyway.
        byte[] copy = new byte[size];
        for (nuint i = 0u; i < size; i++)
            copy[i] = start[i];

        return Ok(copy);
    }
}

#endif
