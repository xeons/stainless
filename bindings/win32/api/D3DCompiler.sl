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

// d3dcompiler_47.dll: HLSL into bytecode.
//
// One entry point that matters and one interface to carry its output.
// `D3DCompile` turns HLSL source into the DXBC a `CreateVertexShader` takes,
// and the same blob is what `CreateInputLayout` validates a layout against.
//
// **Compiling at run time is a choice, and not the only one.** A shipped
// program usually compiles its shaders at build time with `fxc` and loads the
// bytecode, because the compiler is a 3 MB DLL that need not be there and
// because compiling forty shaders at startup is a visible pause. Compiling at
// run time is what a tool, a sample and a shader editor want, and it is what
// this binds.
//
// Declarations cost nothing, so this module needs no library on its own; a
// program that *calls* one of them wants `-l d3dcompiler`, or
// `Windows.DirectX`, which names it with a pragma.
module Win32.D3DCompiler;

import Standard.Com;

#if WINDOWS

/// A block of bytes the D3D compiler allocated: bytecode, or an error message.
///
/// The one COM interface in DirectX that is just a buffer. It is released like
/// anything else, which is what ARC does at the end of the scope that holds it.
[Guid("8BA5FB08-5195-40E2-AC58-0D989C3A0102")]
public com interface ID3DBlob
{
    /// **Not null-terminated for bytecode, and is for an error message** --
    /// the compiler writes a C string into the error blob, and the size counts
    /// the terminator. A caller printing one should stop at the first zero.
    byte* GetBufferPointer();

    nuint GetBufferSize();
}

public extern "C" __stdcall
{
    // `pSourceName` is what appears in an error message and may be null.
    // `pDefines` and `pInclude` are the preprocessor's, and null for source
    // that includes nothing.
    //
    // **Both output blobs must be released**, including the error one after a
    // successful compile -- a compile that only produced warnings fills it and
    // still returns S_OK.
    int D3DCompile(byte* pSrcData, nuint SrcDataSize, byte* pSourceName,
                   byte* pDefines, byte* pInclude, byte* pEntrypoint,
                   byte* pTarget, uint Flags1, uint Flags2,
                   byte** ppCode, byte** ppErrorMsgs);

    int D3DCompile2(byte* pSrcData, nuint SrcDataSize, byte* pSourceName,
                    byte* pDefines, byte* pInclude, byte* pEntrypoint,
                    byte* pTarget, uint Flags1, uint Flags2,
                    uint SecondaryDataFlags, byte* pSecondaryData,
                    nuint SecondaryDataSize, byte** ppCode, byte** ppErrorMsgs);

    // The preprocessor on its own, which is how a program that generates HLSL
    // sees what its macros expanded to.
    int D3DPreprocess(byte* pSrcData, nuint SrcDataSize, byte* pSourceName,
                      byte* pDefines, byte* pInclude, byte** ppCodeText,
                      byte** ppErrorMsgs);

    // Bytecode back into readable assembly, for a program that wants to show
    // what the compiler produced.
    int D3DDisassemble(byte* pSrcData, nuint SrcDataSize, uint Flags,
                       byte* szComments, byte** ppDisassembly);

    // The signature alone, which is all `CreateInputLayout` actually needs --
    // and is a few hundred bytes rather than a few thousand, so a program that
    // keeps layouts around can keep these instead of whole shaders.
    int D3DGetInputSignatureBlob(byte* pSrcData, nuint SrcDataSize, byte** ppSignatureBlob);
}

// ================================================================== targets

// The target is a byte string naming the stage and the shader model, and it is
// passed as text: `"vs_5_0"`, `"ps_5_0"`. 5.0 is what feature level 11.0 runs
// and what a program should compile for unless it knows better; 4.0 level 9_1
// and 9_3 are the ones that reach the oldest hardware.

// ================================================================== flags

/// `D3DCOMPILE_DEBUG`: keep the names and the line numbers, so a graphics
/// debugger can show the source. Costs size and nothing else.
public const uint D3DCOMPILE_DEBUG = 1u;

/// `D3DCOMPILE_SKIP_VALIDATION`.
public const uint D3DCOMPILE_SKIP_VALIDATION = 2u;

/// `D3DCOMPILE_SKIP_OPTIMIZATION`: what to pair with `DEBUG` while stepping
/// through a shader, and never otherwise.
public const uint D3DCOMPILE_SKIP_OPTIMIZATION = 4u;

/// `D3DCOMPILE_PACK_MATRIX_ROW_MAJOR`: matrices are rows, as C and most maths
/// libraries write them. **HLSL's default is the other one**, so a program
/// whose matrices come from ordinary array-of-rows code wants this or wants to
/// transpose on the way in.
public const uint D3DCOMPILE_PACK_MATRIX_ROW_MAJOR = 8u;

/// `D3DCOMPILE_PACK_MATRIX_COLUMN_MAJOR`, which is HLSL's default.
public const uint D3DCOMPILE_PACK_MATRIX_COLUMN_MAJOR = 16u;

/// `D3DCOMPILE_ENABLE_STRICTNESS`: refuse the legacy syntax rather than
/// quietly accepting it.
public const uint D3DCOMPILE_ENABLE_STRICTNESS = 0x800u;

/// `D3DCOMPILE_WARNINGS_ARE_ERRORS`.
public const uint D3DCOMPILE_WARNINGS_ARE_ERRORS = 0x40000u;

/// `D3DCOMPILE_OPTIMIZATION_LEVEL0` through `3`. Level 1 is the default and
/// level 3 is what a shipped shader wants.
public const uint D3DCOMPILE_OPTIMIZATION_LEVEL0 = 0x4000u;
public const uint D3DCOMPILE_OPTIMIZATION_LEVEL1 = 0u;
public const uint D3DCOMPILE_OPTIMIZATION_LEVEL2 = 0xC000u;
public const uint D3DCOMPILE_OPTIMIZATION_LEVEL3 = 0x8000u;

#endif
