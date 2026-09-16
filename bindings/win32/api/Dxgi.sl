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

// dxgi.dll: adapters, outputs, formats and the swap chain.
//
// DXGI is the half of DirectX that is not about drawing. It enumerates the
// graphics hardware, describes what a pixel is, and owns the chain of buffers
// a rendered frame is shown through -- and Direct3D 10, 11 and 12 all sit on
// the same one, which is why it is a module of its own rather than part of
// either.
//
// Declarations and nothing else, spelled as `dxgi.h` spells them. The method
// order *is* the vtable, so nothing here may be reordered or removed -- a
// method that is not wanted is still declared, because slot 9 has to be slot 9.
// Every interface extends `IUnknown` whether or not it says so, so a
// declaration's own first method is slot 3, and ARC emits the AddRef and
// Release (§8.5).
//
// Declarations cost nothing, so this module needs no library on its own; a
// program that *calls* one of them wants `-l dxgi`, or `Windows.DirectX11`,
// which names it with a pragma.
module Win32.Dxgi;

import Standard.Com;
// For `Rect`, which is `windef.h`'s and which `Win32.User32` is this tree's
// home for. A declaration costs nothing to import: only calling one of that
// module's entry points would make user32 necessary, and nothing here does.
import Win32.User32;

#if WINDOWS

// ================================================================== structs

/// `LUID`: the identity Windows gives an adapter, and the number D3D12 and
/// Vulkan use to tell they are looking at the same one.
public struct LUID
{
    public uint LowPart;
    public int HighPart;
}

/// `DXGI_RATIONAL`: a refresh rate as the fraction it actually is. 60 Hz is
/// 60000/1001 on a television and 60/1 on a monitor, and the difference is
/// what makes this a pair rather than a number.
public struct DXGI_RATIONAL
{
    public uint Numerator;
    public uint Denominator;
}

/// `DXGI_SAMPLE_DESC`: multisampling. `Count` 1 and `Quality` 0 is none, which
/// is what a flip-model swap chain requires.
public struct DXGI_SAMPLE_DESC
{
    public uint Count;
    public uint Quality;
}

/// `DXGI_MODE_DESC`: one display mode.
public struct DXGI_MODE_DESC
{
    public uint Width;
    public uint Height;
    public DXGI_RATIONAL RefreshRate;
    public int Format;
    public int ScanlineOrdering;
    public int Scaling;
}

/// `DXGI_SWAP_CHAIN_DESC`: how a window is presented to.
///
/// A width and height of zero means "whatever the window is", which is what to
/// pass: the alternative is asking for a size and getting a stretched blit
/// when the window turns out to be a different one.
public struct DXGI_SWAP_CHAIN_DESC
{
    public DXGI_MODE_DESC BufferDesc;
    public DXGI_SAMPLE_DESC SampleDesc;
    public uint BufferUsage;
    public uint BufferCount;
    public void* OutputWindow;
    public int Windowed;
    public int SwapEffect;
    public uint Flags;
}

/// `DXGI_ADAPTER_DESC`: what a graphics adapter is.
public struct DXGI_ADAPTER_DESC
{
    public char16[128] Description;
    public uint VendorId;
    public uint DeviceId;
    public uint SubSysId;
    public uint Revision;
    public nuint DedicatedVideoMemory;
    public nuint DedicatedSystemMemory;
    public nuint SharedSystemMemory;
    public LUID AdapterLuid;
}

/// `DXGI_ADAPTER_DESC1`, which adds the flags -- and therefore the bit that
/// says an adapter is the software renderer rather than a card.
public struct DXGI_ADAPTER_DESC1
{
    public char16[128] Description;
    public uint VendorId;
    public uint DeviceId;
    public uint SubSysId;
    public uint Revision;
    public nuint DedicatedVideoMemory;
    public nuint DedicatedSystemMemory;
    public nuint SharedSystemMemory;
    public LUID AdapterLuid;
    public uint Flags;
}

/// `DXGI_OUTPUT_DESC`: one monitor.
public struct DXGI_OUTPUT_DESC
{
    public char16[32] DeviceName;
    public Rect DesktopCoordinates;
    public int AttachedToDesktop;
    public int Rotation;
    public void* Monitor;
}

/// `DXGI_FRAME_STATISTICS`: what the presentation engine did, for a program
/// that wants to pace itself against the display rather than against a clock.
public struct DXGI_FRAME_STATISTICS
{
    public uint PresentCount;
    public uint PresentRefreshCount;
    public uint SyncRefreshCount;
    public long SyncQPCTime;
    public long SyncGPUTime;
}

/// `DXGI_SURFACE_DESC`.
public struct DXGI_SURFACE_DESC
{
    public uint Width;
    public uint Height;
    public int Format;
    public DXGI_SAMPLE_DESC SampleDesc;
}

/// `DXGI_MAPPED_RECT`: what mapping a surface gives back.
public struct DXGI_MAPPED_RECT
{
    public int Pitch;
    public byte* pBits;
}

// =============================================================== interfaces

/// What everything in DXGI is: a COM object that carries private data and
/// knows what made it.
[Guid("AEC22FB8-76F3-4639-9BE0-28EB43A67A2E")]
public com interface IDXGIObject
{
    int SetPrivateData(Guid* Name, uint DataSize, byte* pData);
    int SetPrivateDataInterface(Guid* Name, byte* pUnknown);
    int GetPrivateData(Guid* Name, uint* pDataSize, byte* pData);

    /// The object that made this one -- a factory from an adapter, an adapter
    /// from a device. This is how a program that was handed a device finds the
    /// factory it must use to make a swap chain, and using a *different*
    /// factory is the mistake that makes one silently not present.
    int GetParent(Guid* riid, byte** ppParent);
}

/// Anything a device owns: a surface, a swap chain, a resource.
[Guid("3D3E0379-F9DE-4D58-BB6C-18D62992F1A6")]
public com interface IDXGIDeviceSubObject : IDXGIObject
{
    int GetDevice(Guid* riid, byte** ppDevice);
}

/// The way in: what enumerates adapters and makes swap chains.
[Guid("7B7166EC-21C7-44AE-B21A-C9AE321AE369")]
public com interface IDXGIFactory : IDXGIObject
{
    /// Adapter 0 is the one the system prefers. `DXGI_ERROR_NOT_FOUND` ends
    /// the walk, and is not a failure.
    int EnumAdapters(uint Adapter, byte** ppAdapter);

    /// Which window DXGI watches for Alt+Enter and print-screen. Passing
    /// `DXGI_MWA_NO_ALT_ENTER` is what a program that handles full screen
    /// itself wants, and is the usual answer.
    int MakeWindowAssociation(void* WindowHandle, uint Flags);
    int GetWindowAssociation(void* pWindowHandle);

    /// **The factory must be the one the device came from.** A swap chain made
    /// on a different factory presents to nothing, with no error to say so;
    /// `GetParent` up from the device is how to get the right one.
    int CreateSwapChain(byte* pDevice, DXGI_SWAP_CHAIN_DESC* pDesc, byte** ppSwapChain);

    int CreateSoftwareAdapter(void* Module, byte** ppAdapter);
}

/// The factory to ask for, because `EnumAdapters1` is what reports the
/// software adapter as software.
[Guid("770AAE78-F26F-4DBA-A829-253C83D1B387")]
public com interface IDXGIFactory1 : IDXGIFactory
{
    int EnumAdapters1(uint Adapter, byte** ppAdapter);

    /// False once a display has been added or removed, which is the signal to
    /// make a new factory and look again.
    int IsCurrent();
}

/// One graphics adapter.
[Guid("2411E7E1-12AC-4CCF-BD14-9798E8534DC0")]
public com interface IDXGIAdapter : IDXGIObject
{
    int EnumOutputs(uint Output, byte** ppOutput);
    int GetDesc(DXGI_ADAPTER_DESC* pDesc);
    int CheckInterfaceSupport(Guid* InterfaceName, long* pUMDVersion);
}

/// The same, with the flags that say whether it is real hardware.
[Guid("29038F61-3839-4626-91FD-086879011A05")]
public com interface IDXGIAdapter1 : IDXGIAdapter
{
    int GetDesc1(DXGI_ADAPTER_DESC1* pDesc);
}

/// One monitor attached to an adapter.
[Guid("AE02EEDB-C735-4690-8D52-5A8DC20213AA")]
public com interface IDXGIOutput : IDXGIObject
{
    int GetDesc(DXGI_OUTPUT_DESC* pDesc);

    /// Called twice: once with a null `pDesc` to learn the count, then again
    /// with an array of that many. Which is DXGI's convention throughout.
    int GetDisplayModeList(int EnumFormat, uint Flags, uint* pNumModes, DXGI_MODE_DESC* pDesc);

    int FindClosestMatchingMode(DXGI_MODE_DESC* pModeToMatch, DXGI_MODE_DESC* pClosestMatch,
                                byte* pConcernedDevice);

    /// Blocks until the display's next vertical blank. A way to pace a loop
    /// without spinning, and not a substitute for presenting with a sync
    /// interval.
    int WaitForVBlank();

    int TakeOwnership(byte* pDevice, int Exclusive);
    void ReleaseOwnership();
    int GetGammaControlCapabilities(byte* pGammaCaps);
    int SetGammaControl(byte* pArray);
    int GetGammaControl(byte* pArray);
    int SetDisplaySurface(byte* pScanoutSurface);
    int GetDisplaySurfaceData(byte* pDestination);
    int GetFrameStatistics(DXGI_FRAME_STATISTICS* pStats);
}

/// The chain of buffers a window is drawn into and shown from.
[Guid("310D36A0-D2E7-4C0A-AA04-6A9D23B8886A")]
public com interface IDXGISwapChain : IDXGIDeviceSubObject
{
    /// Shows the back buffer. `SyncInterval` 1 waits for one vertical blank --
    /// which is what "vsync on" means -- and 0 shows it at once and tears.
    int Present(uint SyncInterval, uint Flags);

    /// Buffer 0 is the one to render into. Under the flip models it is the
    /// *only* one a program may ask for.
    int GetBuffer(uint Buffer, Guid* riid, byte** ppSurface);

    int SetFullscreenState(int Fullscreen, byte* pTarget);
    int GetFullscreenState(int* pFullscreen, byte** ppTarget);
    int GetDesc(DXGI_SWAP_CHAIN_DESC* pDesc);

    /// **Every reference to a back buffer must be gone first** -- the render
    /// target view especially -- or this fails and the window stays the size
    /// it was. Zeros mean "keep what is there", which is what a resize wants
    /// for the count and the format.
    int ResizeBuffers(uint BufferCount, uint Width, uint Height, int NewFormat,
                      uint SwapChainFlags);

    int ResizeTarget(DXGI_MODE_DESC* pNewTargetParameters);
    int GetContainingOutput(byte** ppOutput);
    int GetFrameStatistics(DXGI_FRAME_STATISTICS* pStats);
    int GetLastPresentCount(uint* pLastPresentCount);
}

/// The DXGI face of a Direct3D device, which is how a program gets from a
/// device to the adapter and the factory above it.
[Guid("54EC77FA-1377-44E6-8C32-88FD5F44C84C")]
public com interface IDXGIDevice : IDXGIObject
{
    int GetAdapter(byte** pAdapter);
    int CreateSurface(DXGI_SURFACE_DESC* pDesc, uint NumSurfaces, uint Usage,
                      byte* pSharedResource, byte** ppSurface);
    int QueryResourceResidency(byte** ppResources, int* pResidencyStatus, uint NumResources);
    int SetGPUThreadPriority(int Priority);
    int GetGPUThreadPriority(int* pPriority);
}

/// A two-dimensional block of pixels, which is what a swap chain's buffer is
/// before Direct3D has been asked to call it a texture.
[Guid("CAFCB56C-6AC3-4889-BF47-9E23BBD260EC")]
public com interface IDXGISurface : IDXGIDeviceSubObject
{
    int GetDesc(DXGI_SURFACE_DESC* pDesc);
    int Map(DXGI_MAPPED_RECT* pLockedRect, uint MapFlags);
    int Unmap();
}

// ============================================================== entry points

public extern "C" __stdcall
{
    int CreateDXGIFactory(Guid* riid, byte** ppFactory);
    int CreateDXGIFactory1(Guid* riid, byte** ppFactory);

    // `Flags` takes `DXGI_CREATE_FACTORY_DEBUG`, which needs the graphics
    // tools feature installed and fails without it -- so a program that asks
    // for it should fall back rather than stop.
    int CreateDXGIFactory2(uint Flags, Guid* riid, byte** ppFactory);
}

// ================================================================== formats

// `DXGI_FORMAT` has 130 members and a program uses eight of them. These are
// the ones that matter, named as DXGI names them; the rest are in the header
// and are numbers a caller can pass directly.

/// No format. What a swap chain description means by "keep what is there".
public const int DXGI_FORMAT_UNKNOWN = 0;

/// Four 32-bit floats: what a position or a colour is inside a shader, and
/// what a vertex buffer usually holds.
public const int DXGI_FORMAT_R32G32B32A32_FLOAT = 2;

/// Three of them.
public const int DXGI_FORMAT_R32G32B32_FLOAT = 6;

/// Two: a texture coordinate.
public const int DXGI_FORMAT_R32G32_FLOAT = 16;

/// One.
public const int DXGI_FORMAT_R32_FLOAT = 41;

/// Eight bits a channel, unsigned, the ordinary back-buffer format.
public const int DXGI_FORMAT_R8G8B8A8_UNORM = 28;

/// The same, with the hardware doing the sRGB conversion on the way in and
/// out. **Not valid for a flip-model swap chain's buffer**; make the buffer
/// `_UNORM` and the render target view `_SRGB`.
public const int DXGI_FORMAT_R8G8B8A8_UNORM_SRGB = 29;

/// Blue first, which is what GDI and every Windows bitmap use.
public const int DXGI_FORMAT_B8G8R8A8_UNORM = 87;

public const int DXGI_FORMAT_B8G8R8A8_UNORM_SRGB = 91;

/// Sixteen-bit float per channel: the format for anything that has to hold a
/// value outside 0 to 1.
public const int DXGI_FORMAT_R16G16B16A16_FLOAT = 10;

/// Ten bits of colour and two of alpha, which is what HDR output takes.
public const int DXGI_FORMAT_R10G10B10A2_UNORM = 24;

/// Sixteen-bit indices, which is what an index buffer holds until it has more
/// than 65535 vertices.
public const int DXGI_FORMAT_R16_UINT = 57;

/// And thirty-two-bit ones.
public const int DXGI_FORMAT_R32_UINT = 42;

/// A depth buffer: 24 bits of depth and 8 of stencil.
public const int DXGI_FORMAT_D24_UNORM_S8_UINT = 45;

/// A depth buffer with no stencil and more precision.
public const int DXGI_FORMAT_D32_FLOAT = 40;

// ============================================================== swap chains

/// `DXGI_USAGE_RENDER_TARGET_OUTPUT`: what a back buffer is for.
public const uint DXGI_USAGE_RENDER_TARGET_OUTPUT = 0x00000020u;

/// `DXGI_USAGE_SHADER_INPUT`: also readable by a shader.
public const uint DXGI_USAGE_SHADER_INPUT = 0x00000010u;

/// `DXGI_USAGE_BACK_BUFFER`.
public const uint DXGI_USAGE_BACK_BUFFER = 0x00000040u;

/// `DXGI_SWAP_EFFECT_DISCARD`: the old model, one buffer, contents undefined
/// after presenting. Works everywhere and copies every frame.
public const int DXGI_SWAP_EFFECT_DISCARD = 0;

/// `DXGI_SWAP_EFFECT_SEQUENTIAL`.
public const int DXGI_SWAP_EFFECT_SEQUENTIAL = 1;

/// `DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL`: Windows 8 and later. The buffer is
/// handed to the compositor rather than copied, which is what makes a windowed
/// program able to present without tearing and without a blit.
public const int DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL = 3;

/// `DXGI_SWAP_EFFECT_FLIP_DISCARD`: Windows 10 and later, and what a new
/// program should use. **Needs at least two buffers, no multisampling, and a
/// non-sRGB buffer format**, and fails with `DXGI_ERROR_INVALID_CALL` if any
/// of those is wrong.
public const int DXGI_SWAP_EFFECT_FLIP_DISCARD = 4;

/// `DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH`: let Alt+Enter change the display
/// mode.
public const uint DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH = 2u;

/// `DXGI_SWAP_CHAIN_FLAG_ALLOW_TEARING`: present with no sync interval on a
/// variable-refresh display. Needs the factory to have said the feature is
/// there.
public const uint DXGI_SWAP_CHAIN_FLAG_ALLOW_TEARING = 2048u;

/// `DXGI_SWAP_CHAIN_FLAG_FRAME_LATENCY_WAITABLE_OBJECT`.
public const uint DXGI_SWAP_CHAIN_FLAG_FRAME_LATENCY_WAITABLE_OBJECT = 256u;

/// `DXGI_MWA_NO_WINDOW_CHANGES`: DXGI stops watching the window's messages.
public const uint DXGI_MWA_NO_WINDOW_CHANGES = 1u;

/// `DXGI_MWA_NO_ALT_ENTER`: and stops turning Alt+Enter into a mode switch,
/// which is what a program that manages its own window wants.
public const uint DXGI_MWA_NO_ALT_ENTER = 2u;

/// `DXGI_MWA_NO_PRINT_SCREEN`.
public const uint DXGI_MWA_NO_PRINT_SCREEN = 4u;

/// `DXGI_PRESENT_ALLOW_TEARING`: only with a sync interval of zero and only on
/// a swap chain made with the matching flag.
public const uint DXGI_PRESENT_ALLOW_TEARING = 0x00000200u;

/// `DXGI_PRESENT_TEST`: do not present; answer whether it would have worked.
/// How a minimised program checks whether it is worth drawing.
public const uint DXGI_PRESENT_TEST = 0x00000001u;

/// `DXGI_ADAPTER_FLAG_SOFTWARE`: this adapter is WARP, the software renderer.
/// Real and slow, and a program enumerating adapters usually wants to skip it.
public const uint DXGI_ADAPTER_FLAG_SOFTWARE = 2u;

/// `DXGI_CREATE_FACTORY_DEBUG`.
public const uint DXGI_CREATE_FACTORY_DEBUG = 0x1u;

// ================================================================== results

/// `DXGI_ERROR_NOT_FOUND`: the end of an enumeration, and not a failure.
public const int DXGI_ERROR_NOT_FOUND = 0x887A0002;

/// `DXGI_ERROR_INVALID_CALL`: the description asked for something that cannot
/// be made. Nearly always a flip-model swap chain with multisampling, one
/// buffer, or an sRGB format.
public const int DXGI_ERROR_INVALID_CALL = 0x887A0001;

/// `DXGI_ERROR_DEVICE_REMOVED`: the adapter is gone -- a driver update, a
/// hardware reset, or a hang the driver gave up on. Everything made from the
/// device is dead and has to be made again.
public const int DXGI_ERROR_DEVICE_REMOVED = 0x887A0005;

/// `DXGI_ERROR_DEVICE_RESET`.
public const int DXGI_ERROR_DEVICE_RESET = 0x887A0007;

/// `DXGI_ERROR_DEVICE_HUNG`: the program's own commands caused the reset.
public const int DXGI_ERROR_DEVICE_HUNG = 0x887A0006;

/// `DXGI_ERROR_WAS_STILL_DRAWING`.
public const int DXGI_ERROR_WAS_STILL_DRAWING = 0x887A000A;

/// `DXGI_ERROR_UNSUPPORTED`.
public const int DXGI_ERROR_UNSUPPORTED = 0x887A0004;

/// `DXGI_ERROR_SDK_COMPONENT_MISSING`: the debug layer was asked for and the
/// graphics tools feature is not installed.
public const int DXGI_ERROR_SDK_COMPONENT_MISSING = 0x887A002D;

/// `DXGI_STATUS_OCCLUDED`: a success code. The window is hidden, so nothing
/// was presented; a program that sees it should stop drawing until a present
/// succeeds again.
public const int DXGI_STATUS_OCCLUDED = 0x087A0001;

#endif
