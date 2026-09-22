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

// Direct3D 11, as a program wants it.
//
// ```csharp
// var graphics = try Graphics.CreateForWindow(window, 800u, 600u);
// graphics.Clear(0.1f, 0.1f, 0.15f, 1.0f);
// graphics.Draw(material, mesh);
// graphics.Present(true);
// ```
//
// A convenience layer over `Win32.D3D11`, `Win32.Dxgi` and `Win32.D3DCompiler`.
// It names d3d11 itself with a pragma, and `Windows.DirectX` names the other
// two, so a program compiling it needs no `-l`.
//
// **What this is and is not.** It is the six objects every Direct3D 11 program
// makes in the same order, with the mistakes that are easy to make and hard to
// see already made correctly -- the render target view released before a
// resize, the viewport that nothing draws without, the flip-model swap chain's
// three requirements. It is not an engine: there is no scene, no camera, no
// material system and no batching, and a program that wants those will reach
// past it to `Win32.D3D11`, which is right there and complete.
//
// **The raw interfaces stay reachable.** `Device` and `Context` are the actual
// COM references, so anything this module does not wrap is a call away rather
// than a wall.
module Windows.DirectX11;

import Standard.Text;
import Standard.Collections;
import Standard.Com;
import Standard.Drawing;
import Win32.Dxgi;
import Win32.D3D11;
import Windows.DirectX;

#if WINDOWS

#pragma comment(lib, "d3d11")

/// One field of a vertex: what it is called in the shader, and what shape it
/// has.
///
/// `Semantic` is matched by name against the vertex shader's inputs --
/// `"POSITION"`, `"COLOR"`, `"TEXCOORD"` -- and is case-insensitive, as HLSL
/// is. `Format` is a `DXGI_FORMAT_*`.
public struct VertexField
{
    public String Semantic;
    public uint SemanticIndex;
    public int Format;

    /// A field, laid out straight after the one before it.
    public static VertexField FromSemantic(String semantic, int format)
    {
        VertexField field;
        field.Semantic = semantic;
        field.SemanticIndex = 0u;
        field.Format = format;
        return field;
    }

    /// The same, where a shader has `TEXCOORD0` and `TEXCOORD1`.
    public static VertexField FromSemantic(String semantic, uint index, int format)
    {
        VertexField field;
        field.Semantic = semantic;
        field.SemanticIndex = index;
        field.Format = format;
        return field;
    }
}

/// Vertices on the GPU, and how many there are.
public sealed class Mesh
{
    ID3D11Buffer _vertices;
    ID3D11Buffer? _indices;
    uint _stride;
    uint _count;
    int _topology;

    /// Made by `Graphics.CreateMesh`, which is where the buffer comes from.
    /// Module-visible rather than public for that reason.
    Mesh(ID3D11Buffer vertices, ID3D11Buffer? indices, uint stride, uint count, int topology)
    {
        _vertices = vertices;
        _indices = indices;
        _stride = stride;
        _count = count;
        _topology = topology;
    }

    /// How many vertices, or how many indices when there are any -- either
    /// way, how many `DrawMesh` will send.
    public uint Count => _count;

    /// How many bytes one vertex is.
    public uint Stride => _stride;

    /// Whether it draws through an index buffer.
    public bool IsIndexed => _indices != null;

    /// The topology it was made with: one of the
    /// `D3D11_PRIMITIVE_TOPOLOGY_*` values.
    public int Topology => _topology;

    /// The vertex buffer itself, for a program that wants to map it.
    public ID3D11Buffer Vertices => _vertices;

    /// The index buffer, or null. Not public: an indexed mesh is drawn
    /// through `Graphics.DrawMesh`, which is the only thing that needs to know.
    ID3D11Buffer? Indices => _indices;
}

/// A vertex shader, a pixel shader and the layout that feeds them.
///
/// The three are one object because they are validated against each other: an
/// input layout is checked against a vertex shader's signature when it is
/// made, so a layout that works with one shader is not a thing to share
/// casually with another.
public sealed class Material
{
    ID3D11VertexShader _vertex;
    ID3D11PixelShader _pixel;
    ID3D11InputLayout _layout;

    /// Made by `Graphics.CreateMaterial`.
    Material(ID3D11VertexShader vertex, ID3D11PixelShader pixel, ID3D11InputLayout layout)
    {
        _vertex = vertex;
        _pixel = pixel;
        _layout = layout;
    }

    public ID3D11VertexShader VertexShader => _vertex;
    public ID3D11PixelShader PixelShader => _pixel;
    public ID3D11InputLayout Layout => _layout;
}

/// A block of values every shader invocation sees the same way: a transform,
/// a light, a time.
///
/// Dynamic, because that is what a buffer written once a frame should be --
/// `Graphics.UpdateConstantBuffer` maps it with `WRITE_DISCARD`, which hands
/// back fresh memory rather than waiting for the GPU to finish with the old.
///
/// **The size is rounded up to a multiple of sixteen**, which Direct3D
/// requires and does not say when it refuses.
public sealed class ConstantBuffer
{
    ID3D11Buffer _buffer;
    nuint _size;

    /// Made by `Graphics.CreateConstantBuffer`.
    ConstantBuffer(ID3D11Buffer buffer, nuint size)
    {
        _buffer = buffer;
        _size = size;
    }

    /// How many bytes it holds, after rounding.
    public nuint Size => _size;

    /// The buffer itself, for a program binding it by hand.
    public ID3D11Buffer Buffer => _buffer;
}

/// A device, a context, a swap chain and the view of its back buffer.
///
/// **Everything is released by the destructor**, in the order Direct3D
/// requires: the view before the buffers it names, the swap chain before the
/// device that made it. A `Graphics` that goes out of scope leaves nothing
/// behind, which matters here more than for a file -- a leaked device keeps
/// the driver's allocations alive for the life of the process.
public sealed class Graphics
{
    ID3D11Device _device;
    ID3D11DeviceContext _context;
    IDXGISwapChain _chain;
    ID3D11RenderTargetView? _target;
    ID3D11DepthStencilView? _depth;
    ID3D11BlendState? _opaque;
    ID3D11BlendState? _blended;

    /// Whether the back buffer is bound to the output merger right now.
    ///
    /// **A flip-model `Present` unbinds it.** That is documented DXGI
    /// behaviour and not a bug: the buffer is handed to the compositor, so the
    /// runtime takes it off the pipeline, and a program that binds once at
    /// startup draws exactly one frame and then draws into nothing for ever.
    /// The symptom is a window that shows the clear colour and no geometry,
    /// which looks precisely like a broken shader.
    bool _bound;

    int _level;
    uint _wide;
    uint _high;
    bool _closed;

    Graphics(ID3D11Device device, ID3D11DeviceContext context, IDXGISwapChain chain,
             int level, uint width, uint height)
    {
        _device = device;
        _context = context;
        _chain = chain;
        _level = level;
        _wide = width;
        _high = height;
        _bound = false;
        _closed = false;
    }

    ~Graphics()
    {
        Dispose();
    }

    /// A device and a swap chain on `window`, which is an `HWND`.
    ///
    /// Feature level 11.0 first, then 10.1 and 10.0, so a machine with older
    /// hardware gets a device rather than a failure -- `FeatureLevel` says
    /// which it got. The swap chain is flip-discard with two buffers and no
    /// multisampling, which is what Windows 10 wants and what the compositor
    /// can present without copying.
    public static Result<Graphics, GraphicsError> CreateForWindow(void* window, uint width,
                                                                  uint height)
    {
        return CreateForWindow(window, width, height, false);
    }

    /// The same, optionally with the debug layer -- which reports every
    /// mistake to the debug output and **fails outright if the graphics tools
    /// feature is not installed**, so this falls back to a device without it
    /// rather than refusing.
    public static Result<Graphics, GraphicsError> CreateForWindow(void* window, uint width,
                                                                  uint height, bool debug)
    {
        if (window == null || width == 0u || height == 0u)
            return Fail(GraphicsError.NoSwapChain);

        int[] levels = [D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_1, D3D_FEATURE_LEVEL_10_0];

        DXGI_SWAP_CHAIN_DESC description;
        description.BufferDesc.Width = width;
        description.BufferDesc.Height = height;
        description.BufferDesc.RefreshRate.Numerator = 0u;
        description.BufferDesc.RefreshRate.Denominator = 1u;
        description.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
        description.BufferDesc.ScanlineOrdering = 0;
        description.BufferDesc.Scaling = 0;

        // Flip-discard takes no multisampling at all, and asking for some is
        // DXGI_ERROR_INVALID_CALL with nothing to say which part was wrong.
        description.SampleDesc.Count = 1u;
        description.SampleDesc.Quality = 0u;

        description.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
        description.BufferCount = 2u;
        description.OutputWindow = window;
        description.Windowed = 1;
        description.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
        description.Flags = 0u;

        // Written out rather than as a ternary: a `uint` constant and an
        // unsuffixed literal meet at a type that is neither.
        uint flags = 0u;
        if (debug)
            flags = D3D11_CREATE_DEVICE_DEBUG;

        var made = CreateDeviceAndSwapChain(&description, levels, flags);
        if (!made.Ok && debug)
        {
            // No graphics tools, which is the ordinary state of a machine that
            // is not a developer's. Worth trying again rather than refusing.
            made = CreateDeviceAndSwapChain(&description, levels, 0u);
        }

        if (!made.Ok)
            return Fail(made.Error);

        var graphics = made.Value;
        var attached = graphics.AttachBackBuffer();
        if (!attached.Ok)
            return Fail(attached.Error);

        return Ok(graphics);
    }

    static Result<Graphics, GraphicsError> CreateDeviceAndSwapChain(
        DXGI_SWAP_CHAIN_DESC* description, int[] levels, uint flags)
    {
        byte* rawChain = null;
        byte* rawDevice = null;
        byte* rawContext = null;
        int level = 0;

        int code = D3D11CreateDeviceAndSwapChain(
            null, D3D_DRIVER_TYPE_HARDWARE, null, flags,
            &levels[0u], (uint)levels.Length, D3D11_SDK_VERSION,
            description, &rawChain, &rawDevice, &level, &rawContext);

        if (code < 0)
        {
            // WARP is real and correct and slow, and a machine with no usable
            // driver is better served by a picture than by a message.
            code = D3D11CreateDeviceAndSwapChain(
                null, D3D_DRIVER_TYPE_WARP, null, flags,
                &levels[0u], (uint)levels.Length, D3D11_SDK_VERSION,
                description, &rawChain, &rawDevice, &level, &rawContext);
        }

        if (code < 0)
            return Fail(code == DXGI_ERROR_INVALID_CALL
                ? GraphicsError.NoSwapChain
                : GraphicsError.NoDevice);

        if (rawDevice == null || rawContext == null || rawChain == null)
            return Fail(GraphicsError.NoDevice);

        return Ok(new Graphics((ID3D11Device)rawDevice, (ID3D11DeviceContext)rawContext,
                               (IDXGISwapChain)rawChain, level,
                               (*description).BufferDesc.Width,
                               (*description).BufferDesc.Height));
    }

    /// The device, which makes things and is free-threaded.
    public ID3D11Device Device => _device;

    /// The immediate context, which draws and is not.
    public ID3D11DeviceContext Context => _context;

    /// The swap chain.
    public IDXGISwapChain SwapChain => _chain;

    /// Which feature level the device actually got --
    /// `Describe FeatureLevel` in `Windows.DirectX` turns it into text.
    public int FeatureLevel => _level;

    public uint Width => _wide;

    public uint Height => _high;

    /// Whether the device is still usable.
    public bool IsOpen => !_closed;

    /// Paints the whole back buffer.
    ///
    /// The four numbers are linear and not premultiplied. A render target
    /// whose view has an sRGB format converts them on the way in; one that
    /// does not takes them as they are, which is why a "0.5 grey" looks too
    /// dark on the second and right on the first.
    public void Clear(float red, float green, float blue, float alpha)
    {
        if (_closed)
            return;

        BindRenderTargets();

        var view = _target;
        if (view == null)
            return;

        float[] colour = [red, green, blue, alpha];
        _context.ClearRenderTargetView((byte*)(ID3D11RenderTargetView)view, &colour[0u]);

        // Depth goes back to 1.0, which is the far plane: anything drawn this
        // frame is in front of nothing, which is what a cleared frame means.
        var depth = _depth;
        if (depth != null)
            _context.ClearDepthStencilView((byte*)(ID3D11DepthStencilView)depth,
                                           D3D11_CLEAR_DEPTH | D3D11_CLEAR_STENCIL, 1.0f, 0);
    }

    /// Draws a mesh with a material, binding everything it needs first.
    ///
    /// The bindings are set every call rather than tracked, which costs a
    /// dozen calls into the driver per draw and is the honest thing for a
    /// layer that does not know what else has touched the context. A program
    /// drawing thousands of meshes should sort by material and bind through
    /// `Context` itself.
    public void DrawMesh(Material material, Mesh mesh)
    {
        if (_closed || mesh.Count == 0u)
            return;

        BindRenderTargets();

        uint stride = mesh.Stride;
        uint offset = 0u;
        byte* buffer = (byte*)mesh.Vertices;

        _context.IASetInputLayout((byte*)material.Layout);
        _context.IASetVertexBuffers(0u, 1u, &buffer, &stride, &offset);
        _context.IASetPrimitiveTopology(mesh.Topology);
        _context.VSSetShader((byte*)material.VertexShader, null, 0u);
        _context.PSSetShader((byte*)material.PixelShader, null, 0u);

        var indices = mesh.Indices;
        if (indices == null)
        {
            _context.Draw(mesh.Count, 0u);
            return;
        }

        _context.IASetIndexBuffer((byte*)(ID3D11Buffer)indices, DXGI_FORMAT_R32_UINT, 0u);
        _context.DrawIndexed(mesh.Count, 0u, 0);
    }

    /// Shows what was drawn, and answers the `HRESULT`.
    ///
    /// `waitForVBlank` true is what "vsync on" means and caps the program at
    /// the display's rate. The result is worth checking: `DXGI_STATUS_OCCLUDED`
    /// means the window is hidden and drawing is wasted, and
    /// `DXGI_ERROR_DEVICE_REMOVED` means everything has to be built again --
    /// `IsDeviceLost` in `Windows.DirectX` asks that question.
    public int PresentFrame(bool waitForVBlank)
    {
        if (_closed)
            return DXGI_ERROR_DEVICE_REMOVED;
        uint interval = 0u;
        if (waitForVBlank)
            interval = 1u;

        int shown = _chain.Present(interval, 0u);

        // The runtime has taken the back buffer off the output merger, so the
        // next frame has to put it back.
        _bound = false;
        return shown;
    }

    /// Resizes the back buffer to match a window that changed.
    ///
    /// **Every reference to the old buffer has to be gone first**, which is
    /// what this does with the render target view before calling
    /// `ResizeBuffers` -- and is the single most common reason a hand-written
    /// resize fails and leaves the window stretched.
    public Result<bool, GraphicsError> ResizeBuffers(uint width, uint height)
    {
        if (_closed)
            return Fail(GraphicsError.DeviceLost);
        if (width == 0u || height == 0u)
            return Ok(true);
        if (width == _wide && height == _high)
            return Ok(true);

        // Unbound and dropped: the context holds a reference of its own to
        // whatever is bound, and ResizeBuffers counts that one too.
        _context.OMSetRenderTargets(0u, null, null);
        _target = null;
        _depth = null;
        _bound = false;
        _context.Flush();

        int code = _chain.ResizeBuffers(0u, width, height, DXGI_FORMAT_UNKNOWN, 0u);
        if (code < 0)
            return Fail(IsDeviceLost(code) ? GraphicsError.DeviceLost : GraphicsError.Resource);

        _wide = width;
        _high = height;
        return AttachBackBuffer();
    }

    /// A vertex buffer, and a mesh over it.
    ///
    /// `vertices` is the raw bytes and `stride` is how many of them one vertex
    /// takes; the count follows from the two. The buffer is immutable, which
    /// is the fastest kind and the right one for geometry that does not
    /// change.
    public Result<Mesh, GraphicsError> CreateMesh(byte[] vertices, uint stride, int topology)
    {
        if (_closed)
            return Fail(GraphicsError.DeviceLost);
        if (stride == 0u || vertices.Length == 0u || vertices.Length % (nuint)stride != 0u)
            return Fail(GraphicsError.Resource);

        var made = CreateGpuBuffer(vertices, D3D11_BIND_VERTEX_BUFFER);
        if (!made.Ok)
            return Fail(made.Error);

        uint count = (uint)(vertices.Length / (nuint)stride);
        return Ok(new Mesh(made.Value, null, stride, count, topology));
    }

    /// The same with an index buffer, whose indices are 32-bit.
    public Result<Mesh, GraphicsError> CreateIndexedMesh(byte[] vertices, uint stride,
                                                         uint[] indices, int topology)
    {
        if (_closed)
            return Fail(GraphicsError.DeviceLost);
        if (stride == 0u || vertices.Length == 0u || indices.Length == 0u)
            return Fail(GraphicsError.Resource);

        var vertexBuffer = CreateGpuBuffer(vertices, D3D11_BIND_VERTEX_BUFFER);
        if (!vertexBuffer.Ok)
            return Fail(vertexBuffer.Error);

        byte[] raw = new byte[indices.Length * 4u];
        for (nuint i = 0u; i < indices.Length; i++)
        {
            raw[i * 4u] = (byte)(indices[i] & 0xFFu);
            raw[i * 4u + 1u] = (byte)((indices[i] >> 8) & 0xFFu);
            raw[i * 4u + 2u] = (byte)((indices[i] >> 16) & 0xFFu);
            raw[i * 4u + 3u] = (byte)((indices[i] >> 24) & 0xFFu);
        }

        var indexBuffer = CreateGpuBuffer(raw, D3D11_BIND_INDEX_BUFFER);
        if (!indexBuffer.Ok)
            return Fail(indexBuffer.Error);

        return Ok(new Mesh(vertexBuffer.Value, indexBuffer.Value, stride,
                           (uint)indices.Length, topology));
    }

    /// A material from compiled bytecode and the vertex shape it expects.
    ///
    /// `Hlsl.CompileShader` in `Windows.DirectX` is what produces the two
    /// arrays. The layout is validated against the vertex shader here, so a mismatch
    /// between the fields and the shader's inputs is caught at creation rather
    /// than showing up as nothing being drawn.
    public Result<Material, GraphicsError> CreateMaterial(byte[] vertexBytecode,
                                                          byte[] pixelBytecode,
                                                          VertexField[] fields)
    {
        if (_closed)
            return Fail(GraphicsError.DeviceLost);
        if (vertexBytecode.Length == 0u || pixelBytecode.Length == 0u || fields.Length == 0u)
            return Fail(GraphicsError.Shader);

        byte* rawVertex = null;
        if (_device.CreateVertexShader(&vertexBytecode[0u], vertexBytecode.Length,
                                       null, &rawVertex) < 0 || rawVertex == null)
            return Fail(GraphicsError.Shader);

        byte* rawPixel = null;
        if (_device.CreatePixelShader(&pixelBytecode[0u], pixelBytecode.Length,
                                      null, &rawPixel) < 0 || rawPixel == null)
            return Fail(GraphicsError.Shader);

        var elements = new D3D11_INPUT_ELEMENT_DESC[fields.Length];
        for (nuint i = 0u; i < fields.Length; i++)
        {
            // `SemanticName` is read during the call and not copied, so the
            // String has to be alive for it -- which it is, because `fields`
            // holds every one until this function returns.
            elements[i].SemanticName = fields[i].Semantic.ToPointer();
            elements[i].SemanticIndex = fields[i].SemanticIndex;
            elements[i].Format = fields[i].Format;
            elements[i].InputSlot = 0u;
            elements[i].AlignedByteOffset = D3D11_APPEND_ALIGNED_ELEMENT;
            elements[i].InputSlotClass = D3D11_INPUT_PER_VERTEX_DATA;
            elements[i].InstanceDataStepRate = 0u;
        }

        byte* rawLayout = null;
        if (_device.CreateInputLayout(&elements[0u], (uint)fields.Length,
                                      &vertexBytecode[0u], vertexBytecode.Length,
                                      &rawLayout) < 0 || rawLayout == null)
            return Fail(GraphicsError.Shader);

        return Ok(new Material((ID3D11VertexShader)rawVertex, (ID3D11PixelShader)rawPixel,
                               (ID3D11InputLayout)rawLayout));
    }

    /// A constant buffer of `size` bytes, rounded up to a multiple of sixteen.
    public Result<ConstantBuffer, GraphicsError> CreateConstantBuffer(nuint size)
    {
        if (_closed || size == 0u)
            return Fail(GraphicsError.Resource);

        nuint rounded = size;
        if (rounded % 16u != 0u)
            rounded = rounded + (16u - (rounded % 16u));

        D3D11_BUFFER_DESC description;
        description.ByteWidth = (uint)rounded;
        description.Usage = D3D11_USAGE_DYNAMIC;
        description.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
        description.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
        description.MiscFlags = 0u;
        description.StructureByteStride = 0u;

        byte* raw = null;
        if (_device.CreateBuffer(&description, null, &raw) < 0 || raw == null)
            return Fail(GraphicsError.Resource);

        return Ok(new ConstantBuffer((ID3D11Buffer)raw, rounded));
    }

    /// New values into a constant buffer. Anything past what it holds is
    /// dropped, and anything short of it is left as it was.
    public bool UpdateConstantBuffer(ConstantBuffer constants, byte[] data)
    {
        if (_closed || data.Length == 0u)
            return false;

        D3D11_MAPPED_SUBRESOURCE mapped;
        if (_context.Map((byte*)constants.Buffer, 0u, D3D11_MAP_WRITE_DISCARD, 0u,
                         &mapped) < 0 || mapped.pData == null)
            return false;

        nuint span = data.Length;
        if (span > constants.Size)
            span = constants.Size;

        for (nuint i = 0u; i < span; i++)
            mapped.pData[i] = data[i];

        _context.Unmap((byte*)constants.Buffer, 0u);
        return true;
    }

    /// Binds a constant buffer to both shader stages at `slot`.
    ///
    /// Both, because a transform is nearly always wanted in the vertex shader
    /// and a light in the pixel shader, and one call is what a program that
    /// puts them in the same block should have to make.
    public void SetConstantBuffer(ConstantBuffer constants, uint slot)
    {
        if (_closed)
            return;

        byte* buffer = (byte*)constants.Buffer;
        _context.VSSetConstantBuffers(slot, 1u, &buffer);
        _context.PSSetConstantBuffers(slot, 1u, &buffer);
    }

    /// Turns ordinary source-alpha blending on or off.
    ///
    /// Off is the default and is what opaque geometry wants. On is what a
    /// shadow, a particle or a user interface wants, and it makes draw order
    /// matter -- blended things have to come after the opaque ones and in
    /// back-to-front order among themselves.
    public bool SetAlphaBlend(bool enabled)
    {
        if (_closed)
            return false;

        if (_opaque == null || _blended == null)
        {
            var made = CreateBlendStates();
            if (!made.Ok)
                return false;
        }

        var state = enabled ? _blended : _opaque;
        if (state == null)
            return false;

        float[] factor = [1.0f, 1.0f, 1.0f, 1.0f];
        _context.OMSetBlendState((byte*)(ID3D11BlendState)state, &factor[0u], 0xFFFFFFFFu);
        return true;
    }

    Result<bool, GraphicsError> CreateBlendStates()
    {
        D3D11_BLEND_DESC description;
        description.AlphaToCoverageEnable = 0;
        description.IndependentBlendEnable = 0;

        for (nuint i = 0u; i < 8u; i++)
        {
            description.RenderTarget[i].BlendEnable = 0;
            description.RenderTarget[i].SrcBlend = D3D11_BLEND_ONE;
            description.RenderTarget[i].DestBlend = D3D11_BLEND_ZERO;
            description.RenderTarget[i].BlendOp = D3D11_BLEND_OP_ADD;
            description.RenderTarget[i].SrcBlendAlpha = D3D11_BLEND_ONE;
            description.RenderTarget[i].DestBlendAlpha = D3D11_BLEND_ZERO;
            description.RenderTarget[i].BlendOpAlpha = D3D11_BLEND_OP_ADD;
            description.RenderTarget[i].RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL;
        }

        byte* rawOpaque = null;
        if (_device.CreateBlendState(&description, &rawOpaque) < 0 || rawOpaque == null)
            return Fail(GraphicsError.Resource);

        description.RenderTarget[0u].BlendEnable = 1;
        description.RenderTarget[0u].SrcBlend = D3D11_BLEND_SRC_ALPHA;
        description.RenderTarget[0u].DestBlend = D3D11_BLEND_INV_SRC_ALPHA;

        byte* rawBlended = null;
        if (_device.CreateBlendState(&description, &rawBlended) < 0 || rawBlended == null)
            return Fail(GraphicsError.Resource);

        _opaque = (ID3D11BlendState)rawOpaque;
        _blended = (ID3D11BlendState)rawBlended;
        return Ok(true);
    }

    /// The back buffer, read back as a picture.
    ///
    /// **This is the only thing that proves a frame was drawn.** A program can
    /// report that it presented sixty frames and be presenting sixty black
    /// ones; a self-test cannot tell the difference and a picture can. It is
    /// what a headless check should do after a frame, and what to reach for the
    /// moment something is not on screen that should be.
    ///
    /// It costs a full copy to system memory and a pixel-by-pixel conversion,
    /// so it is a diagnostic rather than something to call in a loop. Call it
    /// *before* `Present` under a flip-model swap chain: flipping leaves the
    /// buffer's contents undefined, which is what the "discard" means.
    public Result<Image, GraphicsError> CaptureFrame()
    {
        if (_closed)
            return Fail(GraphicsError.DeviceLost);

        byte* rawBuffer = null;
        if (_chain.GetBuffer(0u, iidof(ID3D11Texture2D), &rawBuffer) < 0 || rawBuffer == null)
            return Fail(GraphicsError.Resource);

        var backBuffer = (ID3D11Texture2D)rawBuffer;

        D3D11_TEXTURE2D_DESC description;
        backBuffer.GetDesc(&description);

        // A staging texture is the only kind the CPU may read, and it cannot
        // be bound to the pipeline at all -- which is why this is a copy
        // rather than a map of the buffer itself.
        description.Usage = D3D11_USAGE_STAGING;
        description.BindFlags = 0u;
        description.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
        description.MiscFlags = 0u;

        byte* rawStaging = null;
        if (_device.CreateTexture2D(&description, null, &rawStaging) < 0 || rawStaging == null)
            return Fail(GraphicsError.Resource);

        var staging = (ID3D11Texture2D)rawStaging;
        _context.CopyResource((byte*)staging, (byte*)backBuffer);

        D3D11_MAPPED_SUBRESOURCE mapped;
        if (_context.Map((byte*)staging, 0u, D3D11_MAP_READ, 0u, &mapped) < 0 ||
            mapped.pData == null)
            return Fail(GraphicsError.Resource);

        var picture = Image.Create((int)description.Width, (int)description.Height);
        if (!picture.Ok)
        {
            _context.Unmap((byte*)staging, 0u);
            return Fail(GraphicsError.Resource);
        }

        var image = picture.Value;

        // **The row pitch is not the width times four.** The driver pads rows
        // to whatever alignment it likes, and reading as though it did not is
        // the classic way to get a picture that shears.
        for (uint y = 0u; y < description.Height; y++)
        {
            byte* row = &mapped.pData[(nuint)y * (nuint)mapped.RowPitch];
            for (uint x = 0u; x < description.Width; x++)
            {
                nuint at = (nuint)x * 4u;
                image.SetPixel((int)x, (int)y,
                               Rgba.Rgb(row[at], row[at + 1u], row[at + 2u]));
            }
        }

        _context.Unmap((byte*)staging, 0u);
        return Ok(image);
    }

    /// The back buffer, written to a PNG. What a headless check calls.
    public Result<bool, GraphicsError> SaveFrame(String path)
    {
        var captured = CaptureFrame();
        if (!captured.Ok)
            return Fail(captured.Error);

        if (captured.Value.Save(path, ImageFormat.Png) != ImageError.None)
            return Fail(GraphicsError.Resource);

        return Ok(true);
    }

    /// Releases everything, in the order Direct3D requires. Idempotent, and
    /// the destructor calls it.
    public void Dispose()
    {
        if (_closed)
            return;
        _closed = true;

        // Unbound first: the context keeps a reference to whatever is bound,
        // and releasing the view while it is still bound leaves the driver
        // holding the buffer.
        _context.OMSetRenderTargets(0u, null, null);
        _context.ClearState();
        _context.Flush();
        _target = null;
        _depth = null;
        _opaque = null;
        _blended = null;
        _bound = false;
    }

    /// The back buffer's render target view, made and bound, with a viewport
    /// that covers it.
    ///
    /// **The viewport is the part nothing tells you about.** A context with no
    /// viewport rasterizes nothing, and the symptom is a black window that
    /// looks exactly like a broken shader.
    Result<bool, GraphicsError> AttachBackBuffer()
    {
        byte* rawBuffer = null;
        if (_chain.GetBuffer(0u, iidof(ID3D11Texture2D), &rawBuffer) < 0 || rawBuffer == null)
            return Fail(GraphicsError.Resource);

        var backBuffer = (ID3D11Texture2D)rawBuffer;

        byte* rawView = null;
        if (_device.CreateRenderTargetView((byte*)backBuffer, null, &rawView) < 0 ||
            rawView == null)
            return Fail(GraphicsError.Resource);

        var view = (ID3D11RenderTargetView)rawView;
        _target = view;

        var madeDepth = CreateDepthBuffer();
        if (!madeDepth.Ok)
            return Fail(madeDepth.Error);

        _depth = madeDepth.Value;
        _bound = false;
        BindRenderTargets();

        return Ok(true);
    }

    /// The back buffer and its depth buffer onto the output merger, if they
    /// are not there already.
    ///
    /// Called by `Clear` and by `DrawMesh` rather than left to the program,
    /// because the one thing a program cannot be expected to know is that
    /// presenting took the binding away.
    void BindRenderTargets()
    {
        if (_bound || _closed)
            return;

        var view = _target;
        if (view == null)
            return;

        byte* bound = (byte*)(ID3D11RenderTargetView)view;
        var depth = _depth;

        if (depth == null)
            _context.OMSetRenderTargets(1u, &bound, null);
        else
            _context.OMSetRenderTargets(1u, &bound, (byte*)(ID3D11DepthStencilView)depth);

        // A viewport is part of the same story: `ClearState` drops it, and a
        // context with none rasterizes nothing at all.
        D3D11_VIEWPORT viewport;
        viewport.TopLeftX = 0.0f;
        viewport.TopLeftY = 0.0f;
        viewport.Width = (float)_wide;
        viewport.Height = (float)_high;
        viewport.MinDepth = 0.0f;
        viewport.MaxDepth = 1.0f;
        _context.RSSetViewports(1u, &viewport);

        _bound = true;
    }

    /// A depth buffer the size of the back buffer, and a view of it.
    ///
    /// **Nothing is three-dimensional without one.** With no depth buffer the
    /// order things are drawn in is the order they appear in, and a cube looks
    /// like a cube only from the angle it was built at.
    Result<ID3D11DepthStencilView, GraphicsError> CreateDepthBuffer()
    {
        D3D11_TEXTURE2D_DESC description;
        description.Width = _wide;
        description.Height = _high;
        description.MipLevels = 1u;
        description.ArraySize = 1u;
        description.Format = DXGI_FORMAT_D24_UNORM_S8_UINT;
        description.SampleDesc.Count = 1u;
        description.SampleDesc.Quality = 0u;
        description.Usage = D3D11_USAGE_DEFAULT;
        description.BindFlags = D3D11_BIND_DEPTH_STENCIL;
        description.CPUAccessFlags = 0u;
        description.MiscFlags = 0u;

        byte* rawTexture = null;
        if (_device.CreateTexture2D(&description, null, &rawTexture) < 0 || rawTexture == null)
            return Fail(GraphicsError.Resource);

        var texture = (ID3D11Texture2D)rawTexture;

        byte* rawView = null;
        if (_device.CreateDepthStencilView((byte*)texture, null, &rawView) < 0 ||
            rawView == null)
            return Fail(GraphicsError.Resource);

        return Ok((ID3D11DepthStencilView)rawView);
    }

    Result<ID3D11Buffer, GraphicsError> CreateGpuBuffer(byte[] data, uint bind)
    {
        D3D11_BUFFER_DESC description;
        description.ByteWidth = (uint)data.Length;
        description.Usage = D3D11_USAGE_IMMUTABLE;
        description.BindFlags = bind;
        description.CPUAccessFlags = 0u;
        description.MiscFlags = 0u;
        description.StructureByteStride = 0u;

        D3D11_SUBRESOURCE_DATA initial;
        initial.pSysMem = &data[0u];
        initial.SysMemPitch = 0u;
        initial.SysMemSlicePitch = 0u;

        byte* raw = null;
        if (_device.CreateBuffer(&description, &initial, &raw) < 0 || raw == null)
            return Fail(GraphicsError.Resource);

        return Ok((ID3D11Buffer)raw);
    }
}

#endif
