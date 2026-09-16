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

// d3d11.dll: Direct3D 11.
//
// Declarations and nothing else, spelled as `d3d11.h` spells them. The method
// order *is* the vtable and was read out of the header's own `Vtbl` structs
// rather than transcribed, so nothing here may be reordered or removed -- a
// method that is not wanted is still declared, because `Draw` has to be slot
// 13. Every interface extends `IUnknown` whether or not it says so, so a
// declaration's own first method is slot 3, and ARC emits the AddRef and
// Release (§8.5).
//
// **Two objects, and knowing which is which is most of Direct3D 11.** An
// `ID3D11Device` makes things -- buffers, textures, views, shaders, states --
// and is free-threaded. An `ID3D11DeviceContext` is the one that draws, and is
// a hundred and eight methods of pipeline state with no locking at all: one
// thread at a time, or a deferred context per thread and a command list at the
// end.
//
// **Interfaces cross as `byte*`.** A parameter that takes an `ID3D11Buffer*`
// is declared `byte*` here, and an out-parameter `byte**`, which is what the
// shell bindings do for the same reason: it is what a cast from a raw pointer
// adopts, and it keeps a binding from having to declare every interface that
// appears in a signature. `Windows.DirectX11` is where that becomes typed.
//
// Declarations cost nothing, so this module needs no library on its own; a
// program that *calls* one of them wants `-l d3d11`, or `Windows.DirectX11`,
// which names it with a pragma.
module Win32.D3D11;

import Standard.Com;
import Win32.Dxgi;
// For `Rect`, which the scissor calls take.
import Win32.User32;

#if WINDOWS

// ================================================================== structs

/// `D3D11_BUFFER_DESC`: a block of memory the GPU can read.
///
/// A constant buffer's `ByteWidth` must be a multiple of 16, and a vertex
/// buffer's should be a multiple of its stride. Neither is checked here, and
/// the first is checked by the runtime with a message nothing prints unless
/// the debug layer is on.
public struct D3D11_BUFFER_DESC
{
    public uint ByteWidth;
    public int Usage;
    public uint BindFlags;
    public uint CPUAccessFlags;
    public uint MiscFlags;
    public uint StructureByteStride;
}

/// `D3D11_SUBRESOURCE_DATA`: what a resource starts out holding.
public struct D3D11_SUBRESOURCE_DATA
{
    public byte* pSysMem;
    public uint SysMemPitch;
    public uint SysMemSlicePitch;
}

/// `D3D11_TEXTURE2D_DESC`.
public struct D3D11_TEXTURE2D_DESC
{
    public uint Width;
    public uint Height;
    public uint MipLevels;
    public uint ArraySize;
    public int Format;
    public DXGI_SAMPLE_DESC SampleDesc;
    public int Usage;
    public uint BindFlags;
    public uint CPUAccessFlags;
    public uint MiscFlags;
}

/// `D3D11_INPUT_ELEMENT_DESC`: one field of a vertex, as the input assembler
/// sees it.
///
/// `SemanticName` is a byte string the shader matches by name -- `"POSITION"`,
/// `"COLOR"` -- and it must outlive the `CreateInputLayout` call.
/// `D3D11_APPEND_ALIGNED_ELEMENT` in `AlignedByteOffset` means "straight after
/// the one before", which is what a packed vertex wants.
public struct D3D11_INPUT_ELEMENT_DESC
{
    public byte* SemanticName;
    public uint SemanticIndex;
    public int Format;
    public uint InputSlot;
    public uint AlignedByteOffset;
    public int InputSlotClass;
    public uint InstanceDataStepRate;
}

/// `D3D11_VIEWPORT`. The depth range is 0 to 1 and both ends must be set:
/// a viewport with `MaxDepth` left at zero clips everything away.
public struct D3D11_VIEWPORT
{
    public float TopLeftX;
    public float TopLeftY;
    public float Width;
    public float Height;
    public float MinDepth;
    public float MaxDepth;
}

/// `D3D11_MAPPED_SUBRESOURCE`: where a mapped resource's bytes are, and how
/// far apart its rows are -- which is not the same as its width times the
/// pixel size, and assuming it is is the classic way to corrupt a texture.
public struct D3D11_MAPPED_SUBRESOURCE
{
    public byte* pData;
    public uint RowPitch;
    public uint DepthPitch;
}

/// `D3D11_RASTERIZER_DESC`.
public struct D3D11_RASTERIZER_DESC
{
    public int FillMode;
    public int CullMode;
    public int FrontCounterClockwise;
    public int DepthBias;
    public float DepthBiasClamp;
    public float SlopeScaledDepthBias;
    public int DepthClipEnable;
    public int ScissorEnable;
    public int MultisampleEnable;
    public int AntialiasedLineEnable;
}

/// `D3D11_SAMPLER_DESC`: how a texture is read.
public struct D3D11_SAMPLER_DESC
{
    public int Filter;
    public int AddressU;
    public int AddressV;
    public int AddressW;
    public float MipLODBias;
    public uint MaxAnisotropy;
    public int ComparisonFunc;
    public float[4] BorderColor;
    public float MinLOD;
    public float MaxLOD;
}

/// `D3D11_RENDER_TARGET_BLEND_DESC`: blending for one render target.
public struct D3D11_RENDER_TARGET_BLEND_DESC
{
    public int BlendEnable;
    public int SrcBlend;
    public int DestBlend;
    public int BlendOp;
    public int SrcBlendAlpha;
    public int DestBlendAlpha;
    public int BlendOpAlpha;
    public byte RenderTargetWriteMask;
}

/// `D3D11_BLEND_DESC`. With `IndependentBlendEnable` false only
/// `RenderTarget[0]` is read, and it applies to all eight.
public struct D3D11_BLEND_DESC
{
    public int AlphaToCoverageEnable;
    public int IndependentBlendEnable;
    public D3D11_RENDER_TARGET_BLEND_DESC[8] RenderTarget;
}

/// `D3D11_DEPTH_STENCILOP_DESC`.
public struct D3D11_DEPTH_STENCILOP_DESC
{
    public int StencilFailOp;
    public int StencilDepthFailOp;
    public int StencilPassOp;
    public int StencilFunc;
}

/// `D3D11_DEPTH_STENCIL_DESC`.
public struct D3D11_DEPTH_STENCIL_DESC
{
    public int DepthEnable;
    public int DepthWriteMask;
    public int DepthFunc;
    public int StencilEnable;
    public byte StencilReadMask;
    public byte StencilWriteMask;
    public D3D11_DEPTH_STENCILOP_DESC FrontFace;
    public D3D11_DEPTH_STENCILOP_DESC BackFace;
}

/// `D3D11_BOX`: a region of a resource, half-open at the high end as
/// everything here is. A one-dimensional copy still needs `bottom` and `back`
/// set to 1, which is the rule that catches everyone once.
public struct D3D11_BOX
{
    public uint left;
    public uint top;
    public uint front;
    public uint right;
    public uint bottom;
    public uint back;
}

// --------------------------------------------------------------- view descs

// A view description is a format, a dimension, and a union of the cases that
// dimension can be. Written out rather than generated, because the union is
// the whole shape of them and a generator cannot see which case a caller
// means.

/// The buffer case of a view: elements rather than pixels.
public struct D3D11_BUFFER_VIEW
{
    public uint FirstElement;
    public uint NumElements;
}

/// The 2D-texture case of a render target or depth view.
public struct D3D11_TEX2D_VIEW
{
    public uint MipSlice;
}

/// The 2D-texture case of a shader resource view, which also says how many
/// mip levels it can see. `MipLevels` of -1 means all of them from `MostDetailedMip`
/// down, which is what a texture bound for sampling wants.
public struct D3D11_TEX2D_SRV
{
    public uint MostDetailedMip;
    public uint MipLevels;
}

/// `D3D11_RENDER_TARGET_VIEW_DESC`, with the cases this binding covers.
///
/// **The union is every case at offset zero** and only the one the dimension
/// names may be read (§2.7). A dimension this union has no member for -- a 3D
/// texture, an array slice -- is not describable here and wants the header's
/// own layout; the common ones are a buffer and a 2D texture.
public union D3D11_RENDER_TARGET_VIEW_UNION
{
    public D3D11_BUFFER_VIEW Buffer;
    public D3D11_TEX2D_VIEW Texture2D;
    public uint[4] Raw;
}

public struct D3D11_RENDER_TARGET_VIEW_DESC
{
    public int Format;
    public int ViewDimension;
    public D3D11_RENDER_TARGET_VIEW_UNION View;
}

/// `D3D11_DEPTH_STENCIL_VIEW_DESC`.
public union D3D11_DEPTH_STENCIL_VIEW_UNION
{
    public D3D11_TEX2D_VIEW Texture2D;
    public uint[4] Raw;
}

public struct D3D11_DEPTH_STENCIL_VIEW_DESC
{
    public int Format;
    public int ViewDimension;
    public uint Flags;
    public D3D11_DEPTH_STENCIL_VIEW_UNION View;
}

/// `D3D11_SHADER_RESOURCE_VIEW_DESC`.
public union D3D11_SHADER_RESOURCE_VIEW_UNION
{
    public D3D11_BUFFER_VIEW Buffer;
    public D3D11_TEX2D_SRV Texture2D;
    public uint[4] Raw;
}

public struct D3D11_SHADER_RESOURCE_VIEW_DESC
{
    public int Format;
    public int ViewDimension;
    public D3D11_SHADER_RESOURCE_VIEW_UNION View;
}

// =============================================================== interfaces

/// Everything a device made. The four methods are private data and a way back
/// to the device, and every other interface here begins with them.
[Guid("1841E5C8-16B0-489B-BCC8-44CFB0D5DEAE")]
public com interface ID3D11DeviceChild
{
    void GetDevice(byte** ppDevice);
    int GetPrivateData(Guid* guid, uint* pDataSize, byte* pData);
    int SetPrivateData(Guid* guid, uint DataSize, byte* pData);
    int SetPrivateDataInterface(Guid* guid, byte* pData);
}

/// A buffer or a texture: something with bytes the GPU reads.
[Guid("DC8E63F3-D12B-4952-B47B-5E45026A862D")]
public com interface ID3D11Resource : ID3D11DeviceChild
{
    void GetType(int* pResourceDimension);
    void SetEvictionPriority(uint EvictionPriority);
    uint GetEvictionPriority();
}

/// A linear block: vertices, indices, or a constant buffer.
[Guid("48570B85-D1EE-4FCD-A250-EB350722B037")]
public com interface ID3D11Buffer : ID3D11Resource
{
    void GetDesc(D3D11_BUFFER_DESC* pDesc);
}

/// A two-dimensional texture, which is also what a swap chain's back buffer
/// is once Direct3D has been asked for it.
[Guid("6F15AAF2-D208-4E89-9AB4-489535D34F9C")]
public com interface ID3D11Texture2D : ID3D11Resource
{
    void GetDesc(D3D11_TEXTURE2D_DESC* pDesc);
}

/// A way of looking at a resource. A resource is bytes; a view says what those
/// bytes mean to one stage of the pipeline, and the same texture may have
/// several at once.
[Guid("839D1216-BB2E-412B-B7F4-A9DBEBE08ED1")]
public com interface ID3D11View : ID3D11DeviceChild
{
    void GetResource(byte** ppResource);
}

/// Somewhere to draw.
[Guid("DFDBA067-0B8D-4865-875B-D7B4516CC164")]
public com interface ID3D11RenderTargetView : ID3D11View
{
    void GetDesc(D3D11_RENDER_TARGET_VIEW_DESC* pDesc);
}

/// A depth buffer, as the output merger sees it.
[Guid("9FDAC92A-1876-48C3-AFAD-25B94F84A9B6")]
public com interface ID3D11DepthStencilView : ID3D11View
{
    void GetDesc(D3D11_DEPTH_STENCIL_VIEW_DESC* pDesc);
}

/// A texture, as a shader sees it.
[Guid("B0E06FE0-8192-4E1A-B1CA-36D7414710B2")]
public com interface ID3D11ShaderResourceView : ID3D11View
{
    void GetDesc(D3D11_SHADER_RESOURCE_VIEW_DESC* pDesc);
}

/// Somewhere a compute or pixel shader can write.
[Guid("28ACF509-7F5C-48F6-8611-F316010A6380")]
public com interface ID3D11UnorderedAccessView : ID3D11View
{
    void GetDesc(byte* pDesc);
}

/// How the bytes of a vertex buffer line up with the vertex shader's inputs.
[Guid("E4819DDC-4CF0-4025-BD26-5DE82A3E07B7")]
public com interface ID3D11InputLayout : ID3D11DeviceChild
{
}

/// A compiled shader. There is nothing to ask one -- the bytecode said it all
/// at creation -- which is why each of these adds no methods.
[Guid("3B301D64-D678-4289-8897-22F8928B72F3")]
public com interface ID3D11VertexShader : ID3D11DeviceChild
{
}

[Guid("EA82E40D-51DC-4F33-93D4-DB7C9125AE8C")]
public com interface ID3D11PixelShader : ID3D11DeviceChild
{
}

[Guid("38325B96-EFFB-4022-BA02-2E795B70275C")]
public com interface ID3D11GeometryShader : ID3D11DeviceChild
{
}

[Guid("4F5B196E-C2BD-495E-BD01-1FDED38E4969")]
public com interface ID3D11ComputeShader : ID3D11DeviceChild
{
}

/// The pipeline state objects: immutable once made, which is the point of
/// them. A program makes the handful it needs at startup and binds them.
[Guid("75B68FAA-347D-4159-8F45-A0640F01CD9A")]
public com interface ID3D11BlendState : ID3D11DeviceChild
{
    void GetDesc(D3D11_BLEND_DESC* pDesc);
}

[Guid("03823EFB-8D8F-4E1C-9AA2-F64BB2CBFDF1")]
public com interface ID3D11DepthStencilState : ID3D11DeviceChild
{
    void GetDesc(D3D11_DEPTH_STENCIL_DESC* pDesc);
}

[Guid("9BB4AB81-AB1A-4D8F-B506-FC04200B6EE7")]
public com interface ID3D11RasterizerState : ID3D11DeviceChild
{
    void GetDesc(D3D11_RASTERIZER_DESC* pDesc);
}

[Guid("DA6FEA51-564C-4487-9810-F0D0F9B4E3A5")]
public com interface ID3D11SamplerState : ID3D11DeviceChild
{
    void GetDesc(D3D11_SAMPLER_DESC* pDesc);
}

/// Recorded commands from a deferred context, replayed on the immediate one.
[Guid("A24BC4D1-769E-43F7-8013-98FF566C18E2")]
public com interface ID3D11CommandList : ID3D11DeviceChild
{
    uint GetContextFlags();
}

// ------------------------------------------------------------------ device

/// The thing that makes things. Free-threaded: any number of threads may call
/// it at once, which is what makes loading resources on a worker possible.
[Guid("DB6F6DDB-AC77-4E88-8253-819DF9BBF140")]
public com interface ID3D11Device
{
    int CreateBuffer(D3D11_BUFFER_DESC* pDesc, D3D11_SUBRESOURCE_DATA* pInitialData,
                     byte** ppBuffer);
    int CreateTexture1D(byte* pDesc, D3D11_SUBRESOURCE_DATA* pInitialData, byte** ppTexture1D);
    int CreateTexture2D(D3D11_TEXTURE2D_DESC* pDesc, D3D11_SUBRESOURCE_DATA* pInitialData,
                        byte** ppTexture2D);
    int CreateTexture3D(byte* pDesc, D3D11_SUBRESOURCE_DATA* pInitialData, byte** ppTexture3D);
    int CreateShaderResourceView(byte* pResource, D3D11_SHADER_RESOURCE_VIEW_DESC* pDesc,
                                 byte** ppSRView);
    int CreateUnorderedAccessView(byte* pResource, byte* pDesc, byte** ppUAView);

    /// A null `pDesc` means "the whole resource in its own format", which is
    /// what a back buffer's view wants.
    int CreateRenderTargetView(byte* pResource, D3D11_RENDER_TARGET_VIEW_DESC* pDesc,
                               byte** ppRTView);
    int CreateDepthStencilView(byte* pResource, D3D11_DEPTH_STENCIL_VIEW_DESC* pDesc,
                               byte** ppDepthStencilView);

    /// The bytecode must be the *vertex* shader's: the layout is validated
    /// against its input signature, and a pixel shader's bytecode here fails
    /// with a message only the debug layer prints.
    int CreateInputLayout(D3D11_INPUT_ELEMENT_DESC* pInputElementDescs, uint NumElements,
                          byte* pShaderBytecodeWithInputSignature, nuint BytecodeLength,
                          byte** ppInputLayout);

    int CreateVertexShader(byte* pShaderBytecode, nuint BytecodeLength, byte* pClassLinkage,
                           byte** ppVertexShader);
    int CreateGeometryShader(byte* pShaderBytecode, nuint BytecodeLength, byte* pClassLinkage,
                             byte** ppGeometryShader);
    int CreateGeometryShaderWithStreamOutput(byte* pShaderBytecode, nuint BytecodeLength,
                                             byte* pSODeclaration, uint NumEntries,
                                             uint* pBufferStrides, uint NumStrides,
                                             uint RasterizedStream, byte* pClassLinkage,
                                             byte** ppGeometryShader);
    int CreatePixelShader(byte* pShaderBytecode, nuint BytecodeLength, byte* pClassLinkage,
                          byte** ppPixelShader);
    int CreateHullShader(byte* pShaderBytecode, nuint BytecodeLength, byte* pClassLinkage,
                         byte** ppHullShader);
    int CreateDomainShader(byte* pShaderBytecode, nuint BytecodeLength, byte* pClassLinkage,
                           byte** ppDomainShader);
    int CreateComputeShader(byte* pShaderBytecode, nuint BytecodeLength, byte* pClassLinkage,
                            byte** ppComputeShader);
    int CreateClassLinkage(byte** ppLinkage);
    int CreateBlendState(D3D11_BLEND_DESC* pBlendStateDesc, byte** ppBlendState);
    int CreateDepthStencilState(D3D11_DEPTH_STENCIL_DESC* pDepthStencilDesc,
                                byte** ppDepthStencilState);
    int CreateRasterizerState(D3D11_RASTERIZER_DESC* pRasterizerDesc, byte** ppRasterizerState);
    int CreateSamplerState(D3D11_SAMPLER_DESC* pSamplerDesc, byte** ppSamplerState);
    int CreateQuery(byte* pQueryDesc, byte** ppQuery);
    int CreatePredicate(byte* pPredicateDesc, byte** ppPredicate);
    int CreateCounter(byte* pCounterDesc, byte** ppCounter);
    int CreateDeferredContext(uint ContextFlags, byte** ppDeferredContext);
    int OpenSharedResource(void* hResource, Guid* ReturnedInterface, byte** ppResource);
    int CheckFormatSupport(int Format, uint* pFormatSupport);
    int CheckMultisampleQualityLevels(int Format, uint SampleCount, uint* pNumQualityLevels);
    void CheckCounterInfo(byte* pCounterInfo);
    int CheckCounter(byte* pDesc, int* pType, uint* pActiveCounters, byte* szName,
                     uint* pNameLength, byte* szUnits, uint* pUnitsLength,
                     byte* szDescription, uint* pDescriptionLength);
    int CheckFeatureSupport(int Feature, byte* pFeatureSupportData, uint FeatureSupportDataSize);
    int GetPrivateData(Guid* guid, uint* pDataSize, byte* pData);
    int SetPrivateData(Guid* guid, uint DataSize, byte* pData);
    int SetPrivateDataInterface(Guid* guid, byte* pData);

    /// What the device actually got, which may be lower than what was asked
    /// for -- `D3D11CreateDevice` walks the array it was given.
    int GetFeatureLevel();

    uint GetCreationFlags();

    /// `S_OK` while the adapter is alive. Anything else means every object
    /// made from this device is dead; see `DXGI_ERROR_DEVICE_REMOVED`.
    int GetDeviceRemovedReason();

    /// The context that draws. **Not a new reference to keep casually**: it is
    /// AddRef'd like anything else, and a program that never releases it keeps
    /// the device alive for ever.
    void GetImmediateContext(byte** ppImmediateContext);

    int SetExceptionMode(uint RaiseFlags);
    uint GetExceptionMode();
}

// ----------------------------------------------------------------- context

/// The pipeline, and the only thing that draws.
///
/// **One thread at a time.** Nothing here locks; the device is free-threaded
/// and this is not. A program that renders from several threads makes a
/// deferred context per thread with `CreateDeferredContext`, records into it,
/// and replays the command lists on the immediate one.
///
/// The naming is the pipeline's: `IA` is the input assembler, `VS` the vertex
/// shader, `RS` the rasterizer, `PS` the pixel shader, `OM` the output merger,
/// and `HS`, `DS`, `GS` and `CS` the hull, domain, geometry and compute
/// stages. A `Set` binds and the matching `Get` reads back -- and every `Get`
/// returns a *reference*, so a program that calls one in a loop and does not
/// release what it got has written a leak that looks like nothing.
[Guid("C0BFA96C-E089-44FB-8EAF-26F8796190DA")]
public com interface ID3D11DeviceContext : ID3D11DeviceChild
{
    void VSSetConstantBuffers(uint StartSlot, uint NumBuffers, byte** ppConstantBuffers);
    void PSSetShaderResources(uint StartSlot, uint NumViews, byte** ppShaderResourceViews);
    void PSSetShader(byte* pPixelShader, byte** ppClassInstances, uint NumClassInstances);
    void PSSetSamplers(uint StartSlot, uint NumSamplers, byte** ppSamplers);
    void VSSetShader(byte* pVertexShader, byte** ppClassInstances, uint NumClassInstances);
    void DrawIndexed(uint IndexCount, uint StartIndexLocation, int BaseVertexLocation);
    void Draw(uint VertexCount, uint StartVertexLocation);

    /// Locks a resource's memory. `D3D11_MAP_WRITE_DISCARD` on a dynamic
    /// buffer is the fast path -- the driver hands back fresh memory rather
    /// than waiting for the GPU to finish with the old.
    int Map(byte* pResource, uint Subresource, int MapType, uint MapFlags,
            D3D11_MAPPED_SUBRESOURCE* pMappedResource);
    void Unmap(byte* pResource, uint Subresource);

    void PSSetConstantBuffers(uint StartSlot, uint NumBuffers, byte** ppConstantBuffers);
    void IASetInputLayout(byte* pInputLayout);
    void IASetVertexBuffers(uint StartSlot, uint NumBuffers, byte** ppVertexBuffers,
                            uint* pStrides, uint* pOffsets);
    void IASetIndexBuffer(byte* pIndexBuffer, int Format, uint Offset);
    void DrawIndexedInstanced(uint IndexCountPerInstance, uint InstanceCount,
                              uint StartIndexLocation, int BaseVertexLocation,
                              uint StartInstanceLocation);
    void DrawInstanced(uint VertexCountPerInstance, uint InstanceCount,
                       uint StartVertexLocation, uint StartInstanceLocation);
    void GSSetConstantBuffers(uint StartSlot, uint NumBuffers, byte** ppConstantBuffers);
    void GSSetShader(byte* pShader, byte** ppClassInstances, uint NumClassInstances);
    void IASetPrimitiveTopology(int Topology);
    void VSSetShaderResources(uint StartSlot, uint NumViews, byte** ppShaderResourceViews);
    void VSSetSamplers(uint StartSlot, uint NumSamplers, byte** ppSamplers);
    void Begin(byte* pAsync);
    void End(byte* pAsync);
    int GetData(byte* pAsync, byte* pData, uint DataSize, uint GetDataFlags);
    void SetPredication(byte* pPredicate, int PredicateValue);
    void GSSetShaderResources(uint StartSlot, uint NumViews, byte** ppShaderResourceViews);
    void GSSetSamplers(uint StartSlot, uint NumSamplers, byte** ppSamplers);
    void OMSetRenderTargets(uint NumViews, byte** ppRenderTargetViews, byte* pDepthStencilView);
    void OMSetRenderTargetsAndUnorderedAccessViews(uint NumRTVs, byte** ppRenderTargetViews,
                                                   byte* pDepthStencilView, uint UAVStartSlot,
                                                   uint NumUAVs, byte** ppUnorderedAccessViews,
                                                   uint* pUAVInitialCounts);
    void OMSetBlendState(byte* pBlendState, float* BlendFactor, uint SampleMask);
    void OMSetDepthStencilState(byte* pDepthStencilState, uint StencilRef);
    void SOSetTargets(uint NumBuffers, byte** ppSOTargets, uint* pOffsets);
    void DrawAuto();
    void DrawIndexedInstancedIndirect(byte* pBufferForArgs, uint AlignedByteOffsetForArgs);
    void DrawInstancedIndirect(byte* pBufferForArgs, uint AlignedByteOffsetForArgs);
    void Dispatch(uint ThreadGroupCountX, uint ThreadGroupCountY, uint ThreadGroupCountZ);
    void DispatchIndirect(byte* pBufferForArgs, uint AlignedByteOffsetForArgs);
    void RSSetState(byte* pRasterizerState);

    /// **Nothing is drawn without one.** A context with no viewport rasterizes
    /// nothing at all, and the failure looks exactly like a shader that does
    /// not work.
    void RSSetViewports(uint NumViewports, D3D11_VIEWPORT* pViewports);

    void RSSetScissorRects(uint NumRects, Rect* pRects);
    void CopySubresourceRegion(byte* pDstResource, uint DstSubresource, uint DstX, uint DstY,
                               uint DstZ, byte* pSrcResource, uint SrcSubresource,
                               D3D11_BOX* pSrcBox);
    void CopyResource(byte* pDstResource, byte* pSrcResource);
    void UpdateSubresource(byte* pDstResource, uint DstSubresource, D3D11_BOX* pDstBox,
                           byte* pSrcData, uint SrcRowPitch, uint SrcDepthPitch);
    void CopyStructureCount(byte* pDstBuffer, uint DstAlignedByteOffset, byte* pSrcView);

    /// `ColorRGBA` is four floats and they are *not* premultiplied and *not*
    /// gamma corrected: a view with an sRGB format converts them.
    void ClearRenderTargetView(byte* pRenderTargetView, float* ColorRGBA);

    void ClearUnorderedAccessViewUint(byte* pUnorderedAccessView, uint* Values);
    void ClearUnorderedAccessViewFloat(byte* pUnorderedAccessView, float* Values);
    void ClearDepthStencilView(byte* pDepthStencilView, uint ClearFlags, float Depth,
                               byte Stencil);
    void GenerateMips(byte* pShaderResourceView);
    void SetResourceMinLOD(byte* pResource, float MinLOD);
    float GetResourceMinLOD(byte* pResource);
    void ResolveSubresource(byte* pDstResource, uint DstSubresource, byte* pSrcResource,
                            uint SrcSubresource, int Format);
    void ExecuteCommandList(byte* pCommandList, int RestoreContextState);
    void HSSetShaderResources(uint StartSlot, uint NumViews, byte** ppShaderResourceViews);
    void HSSetShader(byte* pHullShader, byte** ppClassInstances, uint NumClassInstances);
    void HSSetSamplers(uint StartSlot, uint NumSamplers, byte** ppSamplers);
    void HSSetConstantBuffers(uint StartSlot, uint NumBuffers, byte** ppConstantBuffers);
    void DSSetShaderResources(uint StartSlot, uint NumViews, byte** ppShaderResourceViews);
    void DSSetShader(byte* pDomainShader, byte** ppClassInstances, uint NumClassInstances);
    void DSSetSamplers(uint StartSlot, uint NumSamplers, byte** ppSamplers);
    void DSSetConstantBuffers(uint StartSlot, uint NumBuffers, byte** ppConstantBuffers);
    void CSSetShaderResources(uint StartSlot, uint NumViews, byte** ppShaderResourceViews);
    void CSSetUnorderedAccessViews(uint StartSlot, uint NumUAVs, byte** ppUnorderedAccessViews,
                                   uint* pUAVInitialCounts);
    void CSSetShader(byte* pComputeShader, byte** ppClassInstances, uint NumClassInstances);
    void CSSetSamplers(uint StartSlot, uint NumSamplers, byte** ppSamplers);
    void CSSetConstantBuffers(uint StartSlot, uint NumBuffers, byte** ppConstantBuffers);
    void VSGetConstantBuffers(uint StartSlot, uint NumBuffers, byte** ppConstantBuffers);
    void PSGetShaderResources(uint StartSlot, uint NumViews, byte** ppShaderResourceViews);
    void PSGetShader(byte** ppPixelShader, byte** ppClassInstances, uint* pNumClassInstances);
    void PSGetSamplers(uint StartSlot, uint NumSamplers, byte** ppSamplers);
    void VSGetShader(byte** ppVertexShader, byte** ppClassInstances, uint* pNumClassInstances);
    void PSGetConstantBuffers(uint StartSlot, uint NumBuffers, byte** ppConstantBuffers);
    void IAGetInputLayout(byte** ppInputLayout);
    void IAGetVertexBuffers(uint StartSlot, uint NumBuffers, byte** ppVertexBuffers,
                            uint* pStrides, uint* pOffsets);
    void IAGetIndexBuffer(byte** pIndexBuffer, int* Format, uint* Offset);
    void GSGetConstantBuffers(uint StartSlot, uint NumBuffers, byte** ppConstantBuffers);
    void GSGetShader(byte** ppGeometryShader, byte** ppClassInstances, uint* pNumClassInstances);
    void IAGetPrimitiveTopology(int* pTopology);
    void VSGetShaderResources(uint StartSlot, uint NumViews, byte** ppShaderResourceViews);
    void VSGetSamplers(uint StartSlot, uint NumSamplers, byte** ppSamplers);
    void GetPredication(byte** ppPredicate, int* pPredicateValue);
    void GSGetShaderResources(uint StartSlot, uint NumViews, byte** ppShaderResourceViews);
    void GSGetSamplers(uint StartSlot, uint NumSamplers, byte** ppSamplers);
    void OMGetRenderTargets(uint NumViews, byte** ppRenderTargetViews,
                            byte** ppDepthStencilView);
    void OMGetRenderTargetsAndUnorderedAccessViews(uint NumRTVs, byte** ppRenderTargetViews,
                                                   byte** ppDepthStencilView, uint UAVStartSlot,
                                                   uint NumUAVs, byte** ppUnorderedAccessViews);
    void OMGetBlendState(byte** ppBlendState, float* BlendFactor, uint* pSampleMask);
    void OMGetDepthStencilState(byte** ppDepthStencilState, uint* pStencilRef);
    void SOGetTargets(uint NumBuffers, byte** ppSOTargets);
    void RSGetState(byte** ppRasterizerState);
    void RSGetViewports(uint* pNumViewports, D3D11_VIEWPORT* pViewports);
    void RSGetScissorRects(uint* pNumRects, Rect* pRects);
    void HSGetShaderResources(uint StartSlot, uint NumViews, byte** ppShaderResourceViews);
    void HSGetShader(byte** ppHullShader, byte** ppClassInstances, uint* pNumClassInstances);
    void HSGetSamplers(uint StartSlot, uint NumSamplers, byte** ppSamplers);
    void HSGetConstantBuffers(uint StartSlot, uint NumBuffers, byte** ppConstantBuffers);
    void DSGetShaderResources(uint StartSlot, uint NumViews, byte** ppShaderResourceViews);
    void DSGetShader(byte** ppDomainShader, byte** ppClassInstances, uint* pNumClassInstances);
    void DSGetSamplers(uint StartSlot, uint NumSamplers, byte** ppSamplers);
    void DSGetConstantBuffers(uint StartSlot, uint NumBuffers, byte** ppConstantBuffers);
    void CSGetShaderResources(uint StartSlot, uint NumViews, byte** ppShaderResourceViews);
    void CSGetUnorderedAccessViews(uint StartSlot, uint NumUAVs, byte** ppUnorderedAccessViews);
    void CSGetShader(byte** ppComputeShader, byte** ppClassInstances, uint* pNumClassInstances);
    void CSGetSamplers(uint StartSlot, uint NumSamplers, byte** ppSamplers);
    void CSGetConstantBuffers(uint StartSlot, uint NumBuffers, byte** ppConstantBuffers);
    void ClearState();
    void Flush();
    int GetType();
    uint GetContextFlags();
    int FinishCommandList(int RestoreDeferredContextState, byte** ppCommandList);
}

// ============================================================== entry points

public extern "C" __stdcall
{
    // `pAdapter` null with a driver type of hardware means "the default
    // adapter"; a named adapter must be paired with `D3D_DRIVER_TYPE_UNKNOWN`,
    // and getting that pair wrong is `E_INVALIDARG` with nothing to say why.
    int D3D11CreateDevice(byte* pAdapter, int DriverType, void* Software, uint Flags,
                          int* pFeatureLevels, uint FeatureLevels, uint SDKVersion,
                          byte** ppDevice, int* pFeatureLevel, byte** ppImmediateContext);

    int D3D11CreateDeviceAndSwapChain(byte* pAdapter, int DriverType, void* Software,
                                      uint Flags, int* pFeatureLevels, uint FeatureLevels,
                                      uint SDKVersion, DXGI_SWAP_CHAIN_DESC* pSwapChainDesc,
                                      byte** ppSwapChain, byte** ppDevice,
                                      int* pFeatureLevel, byte** ppImmediateContext);
}

/// `D3D11_SDK_VERSION`. Passed to the create calls and never anything else.
public const uint D3D11_SDK_VERSION = 7u;

// ================================================================ constants

// ------------------------------------------------------------ driver types

public const int D3D_DRIVER_TYPE_UNKNOWN = 0;

/// Real hardware. What to ask for.
public const int D3D_DRIVER_TYPE_HARDWARE = 1;

public const int D3D_DRIVER_TYPE_REFERENCE = 2;
public const int D3D_DRIVER_TYPE_NULL = 3;
public const int D3D_DRIVER_TYPE_SOFTWARE = 4;

/// WARP: a software rasterizer that is genuinely correct and genuinely slow.
/// The right fallback for a machine with no usable driver, and the right thing
/// to use in a test, because it gives the same pixels everywhere.
public const int D3D_DRIVER_TYPE_WARP = 5;

// ---------------------------------------------------------- feature levels

public const int D3D_FEATURE_LEVEL_9_1 = 0x9100;
public const int D3D_FEATURE_LEVEL_9_2 = 0x9200;
public const int D3D_FEATURE_LEVEL_9_3 = 0x9300;
public const int D3D_FEATURE_LEVEL_10_0 = 0xa000;
public const int D3D_FEATURE_LEVEL_10_1 = 0xa100;

/// Everything Direct3D 11 describes. What a program should ask for first.
public const int D3D_FEATURE_LEVEL_11_0 = 0xb000;

public const int D3D_FEATURE_LEVEL_11_1 = 0xb100;
public const int D3D_FEATURE_LEVEL_12_0 = 0xc000;
public const int D3D_FEATURE_LEVEL_12_1 = 0xc100;

// --------------------------------------------------------- creation flags

/// `D3D11_CREATE_DEVICE_DEBUG`: every mistake is reported to the debug output
/// instead of being silent. **Needs the graphics tools feature installed**,
/// and fails device creation without it -- so a program that asks for it
/// should try again without.
public const uint D3D11_CREATE_DEVICE_DEBUG = 0x2u;

/// `D3D11_CREATE_DEVICE_BGRA_SUPPORT`: required if Direct2D is going to share
/// the device.
public const uint D3D11_CREATE_DEVICE_BGRA_SUPPORT = 0x20u;

/// `D3D11_CREATE_DEVICE_SINGLETHREADED`: promise that only one thread will
/// touch it, and the runtime stops locking.
public const uint D3D11_CREATE_DEVICE_SINGLETHREADED = 0x1u;

// ------------------------------------------------------------------ usage

/// `D3D11_USAGE_DEFAULT`: the GPU reads and writes it, the CPU does neither.
public const int D3D11_USAGE_DEFAULT = 0;

/// `D3D11_USAGE_IMMUTABLE`: set once at creation and never again. The fastest,
/// and it *requires* initial data.
public const int D3D11_USAGE_IMMUTABLE = 1;

/// `D3D11_USAGE_DYNAMIC`: the CPU writes it every frame, through `Map` with
/// `D3D11_MAP_WRITE_DISCARD`.
public const int D3D11_USAGE_DYNAMIC = 2;

/// `D3D11_USAGE_STAGING`: the CPU reads it. The only way to get pixels back
/// from the GPU, and it cannot be bound to the pipeline at all.
public const int D3D11_USAGE_STAGING = 3;

// -------------------------------------------------------------- bind flags

public const uint D3D11_BIND_VERTEX_BUFFER = 0x1u;
public const uint D3D11_BIND_INDEX_BUFFER = 0x2u;
public const uint D3D11_BIND_CONSTANT_BUFFER = 0x4u;
public const uint D3D11_BIND_SHADER_RESOURCE = 0x8u;
public const uint D3D11_BIND_STREAM_OUTPUT = 0x10u;
public const uint D3D11_BIND_RENDER_TARGET = 0x20u;
public const uint D3D11_BIND_DEPTH_STENCIL = 0x40u;
public const uint D3D11_BIND_UNORDERED_ACCESS = 0x80u;

/// `D3D11_CPU_ACCESS_WRITE` and `_READ`. Write goes with `DYNAMIC`, read with
/// `STAGING`, and neither with `DEFAULT`.
public const uint D3D11_CPU_ACCESS_WRITE = 0x10000u;
public const uint D3D11_CPU_ACCESS_READ = 0x20000u;

// ------------------------------------------------------------------ mapping

public const int D3D11_MAP_READ = 1;
public const int D3D11_MAP_WRITE = 2;
public const int D3D11_MAP_READ_WRITE = 3;

/// `D3D11_MAP_WRITE_DISCARD`: throw away what was there and hand back fresh
/// memory. The one to use on a dynamic buffer written every frame, because it
/// never waits for the GPU.
public const int D3D11_MAP_WRITE_DISCARD = 4;

/// `D3D11_MAP_WRITE_NO_OVERWRITE`: promise not to touch anything the GPU may
/// still be reading. Appending to a vertex buffer within one frame.
public const int D3D11_MAP_WRITE_NO_OVERWRITE = 5;

// ------------------------------------------------------------------ topology

public const int D3D11_PRIMITIVE_TOPOLOGY_UNDEFINED = 0;
public const int D3D11_PRIMITIVE_TOPOLOGY_POINTLIST = 1;
public const int D3D11_PRIMITIVE_TOPOLOGY_LINELIST = 2;
public const int D3D11_PRIMITIVE_TOPOLOGY_LINESTRIP = 3;
public const int D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST = 4;
public const int D3D11_PRIMITIVE_TOPOLOGY_TRIANGLESTRIP = 5;

// ------------------------------------------------------------- input layout

/// `D3D11_INPUT_PER_VERTEX_DATA`.
public const int D3D11_INPUT_PER_VERTEX_DATA = 0;

/// `D3D11_INPUT_PER_INSTANCE_DATA`.
public const int D3D11_INPUT_PER_INSTANCE_DATA = 1;

/// `D3D11_APPEND_ALIGNED_ELEMENT`: this element sits straight after the one
/// before it, which is what a packed vertex struct wants and saves counting
/// bytes by hand.
public const uint D3D11_APPEND_ALIGNED_ELEMENT = 0xFFFFFFFFu;

// ------------------------------------------------------------------- views

public const int D3D11_RTV_DIMENSION_UNKNOWN = 0;
public const int D3D11_RTV_DIMENSION_BUFFER = 1;
public const int D3D11_RTV_DIMENSION_TEXTURE2D = 4;

public const int D3D11_DSV_DIMENSION_UNKNOWN = 0;
public const int D3D11_DSV_DIMENSION_TEXTURE2D = 3;

public const int D3D11_SRV_DIMENSION_UNKNOWN = 0;
public const int D3D11_SRV_DIMENSION_BUFFER = 1;
public const int D3D11_SRV_DIMENSION_TEXTURE2D = 4;

/// `D3D11_CLEAR_DEPTH` and `_STENCIL`, for `ClearDepthStencilView`.
public const uint D3D11_CLEAR_DEPTH = 0x1u;
public const uint D3D11_CLEAR_STENCIL = 0x2u;

// ---------------------------------------------------------------- rasterizer

public const int D3D11_FILL_WIREFRAME = 2;
public const int D3D11_FILL_SOLID = 3;

public const int D3D11_CULL_NONE = 1;
public const int D3D11_CULL_FRONT = 2;

/// The default, and what a right-handed program with clockwise winding wants.
public const int D3D11_CULL_BACK = 3;

// --------------------------------------------------------------- comparison

public const int D3D11_COMPARISON_NEVER = 1;
public const int D3D11_COMPARISON_LESS = 2;
public const int D3D11_COMPARISON_EQUAL = 3;
public const int D3D11_COMPARISON_LESS_EQUAL = 4;
public const int D3D11_COMPARISON_GREATER = 5;
public const int D3D11_COMPARISON_NOT_EQUAL = 6;
public const int D3D11_COMPARISON_GREATER_EQUAL = 7;
public const int D3D11_COMPARISON_ALWAYS = 8;

public const int D3D11_DEPTH_WRITE_MASK_ZERO = 0;
public const int D3D11_DEPTH_WRITE_MASK_ALL = 1;

// ------------------------------------------------------------------ sampler

/// `D3D11_FILTER_MIN_MAG_MIP_POINT`: nearest neighbour, which is what pixel
/// art wants and what everything else does not.
public const int D3D11_FILTER_MIN_MAG_MIP_POINT = 0;

/// `D3D11_FILTER_MIN_MAG_MIP_LINEAR`: trilinear, the ordinary choice.
public const int D3D11_FILTER_MIN_MAG_MIP_LINEAR = 0x15;

/// `D3D11_FILTER_ANISOTROPIC`.
public const int D3D11_FILTER_ANISOTROPIC = 0x55;

public const int D3D11_TEXTURE_ADDRESS_WRAP = 1;
public const int D3D11_TEXTURE_ADDRESS_MIRROR = 2;
public const int D3D11_TEXTURE_ADDRESS_CLAMP = 3;
public const int D3D11_TEXTURE_ADDRESS_BORDER = 4;

/// `D3D11_FLOAT32_MAX`, which is what a sampler's `MaxLOD` should be to mean
/// "all of them".
public const float D3D11_FLOAT32_MAX = 3.402823466e+38f;

// -------------------------------------------------------------------- blend

public const int D3D11_BLEND_ZERO = 1;
public const int D3D11_BLEND_ONE = 2;
public const int D3D11_BLEND_SRC_ALPHA = 5;
public const int D3D11_BLEND_INV_SRC_ALPHA = 6;
public const int D3D11_BLEND_DEST_ALPHA = 7;
public const int D3D11_BLEND_INV_DEST_ALPHA = 8;

public const int D3D11_BLEND_OP_ADD = 1;
public const int D3D11_BLEND_OP_SUBTRACT = 2;
public const int D3D11_BLEND_OP_MIN = 4;
public const int D3D11_BLEND_OP_MAX = 5;

/// `D3D11_COLOR_WRITE_ENABLE_ALL`.
public const byte D3D11_COLOR_WRITE_ENABLE_ALL = 15;

#endif
