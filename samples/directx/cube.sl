// SPDX-License-Identifier: 0BSD
//
// A rotating cube, a light above it, the shadow it casts, bouncing text, and
// chiptune.
//
//   stainless run samples/directx/cube.sl samples/directx/tracker.sl \
//       bindings/win32 -l user32
//
//   ... -- 600                  draw 600 frames and stop
//   ... -- 120 quiet shot       no sound, and write cube.png
//   ... -- song.xm              play that module instead
//
// The number is how many frames to draw before closing; with none it runs
// until the window is closed. `quiet` skips the music, which is what a machine
// with no audio device wants, and `shot` writes `cube.png` from the back
// buffer -- because the only thing that proves a frame was drawn is a picture.
//
// **The music is whichever `.xm` it finds**, and the tune it synthesises
// itself when it finds none. An argument ending in `.xm` names one; otherwise
// it looks for `comicbakery.xm` beside itself. `Tracker` is the player, and it
// is in a file of its own because it is a library rather than part of a
// sample.
//
// **Everything here is this repository's own.** Direct3D 11 through
// `Windows.DirectX11`, XAudio2 through `Win32.Sound`, and the matrix maths in
// this file: there is no engine underneath and nothing is linked but the
// system libraries.
//
// The five pieces, in the order they appear below:
//
//   - **The maths.** A 4x4 matrix, a left-handed perspective and view, and the
//     one trick the shadow needs -- a matrix that flattens geometry onto a
//     plane as seen from a point light.
//   - **The geometry.** Six faces of six colours, each with its own normal,
//     which is why the cube has 24 vertices and not 8. A floor to catch the
//     shadow.
//   - **The letters.** A 5x7 bitmap font, turned into a mesh of little
//     squares, so the overlay is geometry like everything else and needs no
//     texture, no sampler and no font.
//   - **The shaders.** One pair for all of it: a transform, a light, and an
//     override colour that the shadow and the text use to draw flat.
//   - **The music.** An `.xm` module if one is there, played by `Tracker`;
//     otherwise three voices in the C64 idiom, synthesised at startup -- a
//     pulse-width-modulated lead with vibrato, a per-frame arpeggio standing
//     in for chords, and a plucked bass. Either way XAudio2 loops it.
module Cube;

import Standard.Console;
import Standard.Env;
import Standard.Convert;
import Standard.Math;
import Standard.Text;
import Standard.Collections;
import Win32;
import Win32.Handles;
import Win32.Kernel32;
import Win32.User32;
import Win32.Ui;
import Win32.Dxgi;
import Win32.D3D11;
import Win32.D3DCompiler;
import Win32.Sound;
import Windows.DirectX;
import Windows.DirectX11;
import Tracker;

// ==================================================================== maths

/// A 4x4 matrix, row-major, as sixteen floats.
///
/// Row-major because that is how it reads on the page; the shaders are
/// compiled with `D3DCOMPILE_PACK_MATRIX_ROW_MAJOR` so that HLSL agrees, which
/// saves transposing every matrix on the way to the GPU. A point is a row
/// vector, so a transform reads left to right: `model * view * projection`.
public struct Matrix
{
    public float[16] M;

    public static Matrix Identity
    {
        get
        {
            Matrix result;
            for (nuint i = 0u; i < 16u; i++)
                result.M[i] = 0.0f;
            result.M[0u] = 1.0f;
            result.M[5u] = 1.0f;
            result.M[10u] = 1.0f;
            result.M[15u] = 1.0f;
            return result;
        }
    }

    public static Matrix Zero
    {
        get
        {
            Matrix result;
            for (nuint i = 0u; i < 16u; i++)
                result.M[i] = 0.0f;
            return result;
        }
    }
}

Matrix MultiplyMatrices(Matrix left, Matrix right)
{
    var result = Matrix.Zero;
    for (nuint row = 0u; row < 4u; row++)
    {
        for (nuint column = 0u; column < 4u; column++)
        {
            double total = 0.0;
            for (nuint k = 0u; k < 4u; k++)
                total = total + (double)left.M[row * 4u + k] * (double)right.M[k * 4u + column];
            result.M[row * 4u + column] = (float)total;
        }
    }
    return result;
}

Matrix CreateRotationY(double angle)
{
    var result = Matrix.Identity;
    float c = (float)Math.Cos(angle);
    float s = (float)Math.Sin(angle);
    result.M[0u] = c;
    result.M[2u] = -s;
    result.M[8u] = s;
    result.M[10u] = c;
    return result;
}

Matrix CreateRotationX(double angle)
{
    var result = Matrix.Identity;
    float c = (float)Math.Cos(angle);
    float s = (float)Math.Sin(angle);
    result.M[5u] = c;
    result.M[6u] = s;
    result.M[9u] = -s;
    result.M[10u] = c;
    return result;
}

Matrix CreateTranslation(double x, double y, double z)
{
    var result = Matrix.Identity;
    result.M[12u] = (float)x;
    result.M[13u] = (float)y;
    result.M[14u] = (float)z;
    return result;
}

Matrix CreateScale(double x, double y, double z)
{
    var result = Matrix.Identity;
    result.M[0u] = (float)x;
    result.M[5u] = (float)y;
    result.M[10u] = (float)z;
    return result;
}

/// A left-handed perspective projection, which is the convention Direct3D
/// uses: z runs into the screen, and the depth buffer holds 0 at the near
/// plane and 1 at the far one.
Matrix CreatePerspective(double fieldOfView, double aspect, double near, double far)
{
    var result = Matrix.Zero;
    double height = 1.0 / Math.Tan(fieldOfView * 0.5);
    result.M[0u] = (float)(height / aspect);
    result.M[5u] = (float)height;
    result.M[10u] = (float)(far / (far - near));
    result.M[11u] = 1.0f;
    result.M[14u] = (float)(-near * far / (far - near));
    return result;
}

/// A view matrix from an eye and what it is looking at. Left-handed, to match
/// the projection: right is `up x forward`, and up is `forward x right`.
Matrix CreateLookAt(double eyeX, double eyeY, double eyeZ, double atX, double atY, double atZ)
{
    double fx = atX - eyeX;
    double fy = atY - eyeY;
    double fz = atZ - eyeZ;
    double length = Math.Sqrt(fx * fx + fy * fy + fz * fz);
    fx = fx / length;
    fy = fy / length;
    fz = fz / length;

    // right = up x forward, with up being (0, 1, 0), which reduces to this.
    double rx = fz;
    double rz = -fx;
    double rl = Math.Sqrt(rx * rx + rz * rz);
    rx = rx / rl;
    rz = rz / rl;
    double ry = 0.0;

    // up = forward x right.
    double ux = fy * rz - fz * ry;
    double uy = fz * rx - fx * rz;
    double uz = fx * ry - fy * rx;

    Matrix result;
    result.M[0u] = (float)rx;
    result.M[1u] = (float)ux;
    result.M[2u] = (float)fx;
    result.M[3u] = 0.0f;
    result.M[4u] = (float)ry;
    result.M[5u] = (float)uy;
    result.M[6u] = (float)fy;
    result.M[7u] = 0.0f;
    result.M[8u] = (float)rz;
    result.M[9u] = (float)uz;
    result.M[10u] = (float)fz;
    result.M[11u] = 0.0f;
    result.M[12u] = (float)-(rx * eyeX + ry * eyeY + rz * eyeZ);
    result.M[13u] = (float)-(ux * eyeX + uy * eyeY + uz * eyeZ);
    result.M[14u] = (float)-(fx * eyeX + fy * eyeY + fz * eyeZ);
    result.M[15u] = 1.0f;
    return result;
}

/// The shadow, as a matrix.
///
/// **This is the whole trick.** A point light at `L` casting onto the plane
/// `y = height` sends a point `P` to where the line from `L` through `P`
/// crosses that plane, and in homogeneous coordinates that map is linear -- so
/// it is a matrix, and the shadow is the same geometry drawn again with one
/// more transform in front of it.
///
/// Writing it out: with the plane `n·p + d = 0` and `dot = n·L + d`, the
/// shadow of `P` is `(dot·P - (n·P + d)·L, dot - (n·P + d))`, which is exactly
/// the matrix below. It is exact for a flat floor and wrong for anything else,
/// which is why a general renderer uses a shadow map instead; for a cube on a
/// plane it is correct, costs one extra draw, and needs no second render
/// target.
Matrix CreateFloorShadow(double lightX, double lightY, double lightZ, double height)
{
    // The plane is y = height, so n is (0, 1, 0) and d is -height.
    double d = -height;
    double dot = lightY + d;

    var result = Matrix.Zero;
    result.M[0u] = (float)dot;

    result.M[4u] = (float)-lightX;
    result.M[5u] = (float)(dot - lightY);
    result.M[6u] = (float)-lightZ;
    result.M[7u] = -1.0f;

    result.M[10u] = (float)dot;

    result.M[12u] = (float)(-d * lightX);
    result.M[13u] = (float)(-d * lightY);
    result.M[14u] = (float)(-d * lightZ);
    result.M[15u] = (float)(dot - d);
    return result;
}

// ================================================================= geometry

// A vertex is a position, a normal and a colour: nine floats, 36 bytes.

void WriteFloat(byte[] into, nuint at, double value)
{
    float held = (float)value;
    byte* bits = (byte*)&held;
    into[at] = bits[0u];
    into[at + 1u] = bits[1u];
    into[at + 2u] = bits[2u];
    into[at + 3u] = bits[3u];
}

byte[] PackFloats(List<double> numbers)
{
    byte[] bytes = new byte[numbers.Count * 4u];
    for (nuint i = 0u; i < numbers.Count; i++)
        WriteFloat(bytes, i * 4u, numbers[i]);
    return bytes;
}

byte[] PackFloatArray(double[] numbers)
{
    byte[] bytes = new byte[numbers.Length * 4u];
    for (nuint i = 0u; i < numbers.Length; i++)
        WriteFloat(bytes, i * 4u, numbers[i]);
    return bytes;
}

/// Six faces, six colours, four vertices each.
///
/// **24 vertices and not 8**, because a corner of a cube has three different
/// normals and three different colours depending on which face is being drawn.
/// Sharing the eight positions would mean one normal per corner and a cube
/// that looks like a badly lit sphere.
///
/// **Each face is wound clockwise as seen from outside**, which is what
/// Direct3D's default rasterizer calls front-facing -- screen space has y
/// pointing down, so a face that reads anticlockwise on paper is the one that
/// survives. Getting it backwards does not make the cube disappear: it culls
/// the near faces and draws the far ones, so the cube is rendered inside out
/// and looks like a shape with four visible sides.
byte[] BuildCubeVertices()
{
    double[] numbers = [
        // +X, red
        1.0, -1.0, -1.0,   1.0, 0.0, 0.0,   0.92, 0.22, 0.22,
        1.0,  1.0, -1.0,   1.0, 0.0, 0.0,   0.92, 0.22, 0.22,
        1.0,  1.0,  1.0,   1.0, 0.0, 0.0,   0.92, 0.22, 0.22,
        1.0, -1.0,  1.0,   1.0, 0.0, 0.0,   0.92, 0.22, 0.22,

        // -X, green
        -1.0, -1.0,  1.0,  -1.0, 0.0, 0.0,  0.24, 0.82, 0.32,
        -1.0,  1.0,  1.0,  -1.0, 0.0, 0.0,  0.24, 0.82, 0.32,
        -1.0,  1.0, -1.0,  -1.0, 0.0, 0.0,  0.24, 0.82, 0.32,
        -1.0, -1.0, -1.0,  -1.0, 0.0, 0.0,  0.24, 0.82, 0.32,

        // +Y, blue
         1.0,  1.0,  1.0,   0.0, 1.0, 0.0,  0.28, 0.48, 0.96,
         1.0,  1.0, -1.0,   0.0, 1.0, 0.0,  0.28, 0.48, 0.96,
        -1.0,  1.0, -1.0,   0.0, 1.0, 0.0,  0.28, 0.48, 0.96,
        -1.0,  1.0,  1.0,   0.0, 1.0, 0.0,  0.28, 0.48, 0.96,

        // -Y, yellow
         1.0, -1.0, -1.0,   0.0, -1.0, 0.0, 0.96, 0.86, 0.22,
         1.0, -1.0,  1.0,   0.0, -1.0, 0.0, 0.96, 0.86, 0.22,
        -1.0, -1.0,  1.0,   0.0, -1.0, 0.0, 0.96, 0.86, 0.22,
        -1.0, -1.0, -1.0,   0.0, -1.0, 0.0, 0.96, 0.86, 0.22,

        // +Z, magenta
         1.0,  1.0, 1.0,    0.0, 0.0, 1.0,  0.88, 0.28, 0.82,
        -1.0,  1.0, 1.0,    0.0, 0.0, 1.0,  0.88, 0.28, 0.82,
        -1.0, -1.0, 1.0,    0.0, 0.0, 1.0,  0.88, 0.28, 0.82,
         1.0, -1.0, 1.0,    0.0, 0.0, 1.0,  0.88, 0.28, 0.82,

        // -Z, cyan
        -1.0,  1.0, -1.0,   0.0, 0.0, -1.0, 0.22, 0.86, 0.88,
         1.0,  1.0, -1.0,   0.0, 0.0, -1.0, 0.22, 0.86, 0.88,
         1.0, -1.0, -1.0,   0.0, 0.0, -1.0, 0.22, 0.86, 0.88,
        -1.0, -1.0, -1.0,   0.0, 0.0, -1.0, 0.22, 0.86, 0.88,
    ];

    return PackFloatArray(numbers);
}

/// Two triangles per face, from the four corners in the order they were
/// written.
uint[] BuildQuadIndices(uint quads)
{
    uint[] indices = new uint[(nuint)quads * 6u];
    for (uint quad = 0u; quad < quads; quad++)
    {
        uint at = quad * 6u;
        uint corner = quad * 4u;
        indices[(nuint)at] = corner;
        indices[(nuint)(at + 1u)] = corner + 1u;
        indices[(nuint)(at + 2u)] = corner + 2u;
        indices[(nuint)(at + 3u)] = corner;
        indices[(nuint)(at + 4u)] = corner + 2u;
        indices[(nuint)(at + 5u)] = corner + 3u;
    }
    return indices;
}

/// A grey floor at y = -1.6, big enough to catch the shadow.
byte[] BuildFloorVertices()
{
    double[] numbers = [
         7.0, -1.6,  7.0,   0.0, 1.0, 0.0,   0.62, 0.63, 0.70,
         7.0, -1.6, -7.0,   0.0, 1.0, 0.0,   0.44, 0.45, 0.52,
        -7.0, -1.6, -7.0,   0.0, 1.0, 0.0,   0.44, 0.45, 0.52,
        -7.0, -1.6,  7.0,   0.0, 1.0, 0.0,   0.62, 0.63, 0.70,
    ];
    return PackFloatArray(numbers);
}

// ================================================================== letters

/// A 5x7 font, one row per line, `#` for a lit pixel.
///
/// Seven letters is all "STAINLESS" needs. Written as text rather than as hex
/// so that the shapes are visible in the source, which is the whole reason a
/// bitmap font is readable at all.
String[] GetGlyphRows(char letter)
{
    if (letter == 'S')
        return [".####", "#....", "#....", ".###.", "....#", "....#", "####."];
    if (letter == 'T')
        return ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."];
    if (letter == 'A')
        return [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"];
    if (letter == 'I')
        return ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"];
    if (letter == 'N')
        return ["#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"];
    if (letter == 'L')
        return ["#....", "#....", "#....", "#....", "#....", "#....", "#####"];
    if (letter == 'E')
        return ["#####", "#....", "#....", "####.", "#....", "#....", "#####"];

    return [".....", ".....", ".....", ".....", ".....", ".....", "....."];
}

/// How wide the word is, in font pixels: five per letter and one between.
nuint MeasureWordWidth(String word) => word.ByteLength() * 6u - 1u;

/// The word as a mesh of little squares, one per lit pixel.
///
/// Geometry rather than a texture, which means the overlay needs no sampler,
/// no shader resource view and no font file -- and it suits the subject, since
/// a chiptune's letters were squares too. The y axis points up, so row 0 of
/// the glyph is at the top.
byte[] BuildWordVertices(String word)
{
    var numbers = new List<double>();
    var letters = word.ToPointer();

    for (nuint index = 0u; index < word.ByteLength(); index++)
    {
        var glyph = GetGlyphRows((char)letters[index]);
        double left = (double)(index * 6u);

        for (nuint row = 0u; row < 7u; row++)
        {
            var bits = glyph[row].ToPointer();
            for (nuint column = 0u; column < 5u; column++)
            {
                if (bits[column] != (byte)'#')
                    continue;

                double x = left + (double)column;
                double y = 6.0 - (double)row;
                AddSquare(numbers, x, y);
            }
        }
    }

    return PackFloats(numbers);
}

/// One unit square at (x, y), wound clockwise as seen on screen.
void AddSquare(List<double> into, double x, double y)
{
    AddVertex(into, x, y + 1.0);
    AddVertex(into, x + 1.0, y + 1.0);
    AddVertex(into, x + 1.0, y);
    AddVertex(into, x, y);
}

void AddVertex(List<double> into, double x, double y)
{
    into.Add(x);
    into.Add(y);
    into.Add(0.0);

    // A normal and a colour the overrides ignore, and which are there because
    // every vertex in this program has the same shape.
    into.Add(0.0);
    into.Add(1.0);
    into.Add(0.0);
    into.Add(1.0);
    into.Add(1.0);
    into.Add(1.0);
}

// ================================================================== shaders

/// One pair of shaders for everything.
///
/// The constant block is a transform, a light, and a colour that either tints
/// the vertex colour or replaces it -- which is how the shadow and the text
/// reuse the cube's shaders. `Override.w` above zero means "use `Override.rgb`
/// flat, with no lighting", and doubles as the alpha, which is what makes the
/// shadow translucent.
String GetShaderSource() =>
    "cbuffer Frame : register(b0)\n" +
    "{\n" +
    "    float4x4 Transform;\n" +
    "    float4   Light;      // xyz: where the light is\n" +
    "    float4   Override;   // rgb, and w above zero to use it flat\n" +
    "};\n" +
    "\n" +
    "struct Vertex\n" +
    "{\n" +
    "    float3 Position : POSITION;\n" +
    "    float3 Normal   : NORMAL;\n" +
    "    float3 Colour   : COLOR;\n" +
    "};\n" +
    "\n" +
    "struct Fragment\n" +
    "{\n" +
    "    float4 Position : SV_Position;\n" +
    "    float3 Colour   : COLOR;\n" +
    "    float  Shade    : TEXCOORD0;\n" +
    "};\n" +
    "\n" +
    "Fragment VertexMain(Vertex input)\n" +
    "{\n" +
    "    Fragment output;\n" +
    "    output.Position = mul(float4(input.Position, 1.0), Transform);\n" +
    "\n" +
    "    // Lambert against the direction to the light, with an ambient floor\n" +
    "    // so that a face turned away is dark rather than black.\n" +
    "    float lit = saturate(dot(normalize(input.Normal), normalize(Light.xyz)));\n" +
    "    output.Shade = 0.30 + 0.70 * lit;\n" +
    "    output.Colour = input.Colour;\n" +
    "    return output;\n" +
    "}\n" +
    "\n" +
    "float4 PixelMain(Fragment input) : SV_Target\n" +
    "{\n" +
    "    if (Override.w > 0.001)\n" +
    "        return float4(Override.rgb, Override.w);\n" +
    "    return float4(input.Colour * input.Shade, 1.0);\n" +
    "}\n";

// ==================================================================== music

/// What is going to be played, and at what rate and width.
struct Music
{
    public byte[] Samples;
    public uint Rate;
    public uint Channels;
    public String Source;
}

/// A module if one can be found, and the synthesised tune if not.
///
/// A module is thirty kilobytes for two minutes where the same as PCM is
/// twelve megabytes, which is the whole reason the format exists -- and it
/// means a demo can carry real music without carrying a wave file.
Music LoadMusic(String wanted)
{
    Music music;
    music.Rate = 22050u;

    String[] candidates = [
        wanted,
        "comicbakery.xm",
        "samples/directx/comicbakery.xm",
        "../comicbakery.xm",
    ];

    for (nuint i = 0u; i < candidates.Length; i++)
    {
        if (candidates[i].ByteLength() == 0u)
            continue;

        var loaded = Tracker.LoadModule(candidates[i]);
        if (!loaded.Ok)
            continue;

        var song = loaded.Value;
        music.Samples = Tracker.RenderModule(song, music.Rate, 240.0);
        music.Channels = 2u;
        music.Source = song.Name + " (" + candidates[i] + ")";
        return music;
    }

    music.Samples = SynthesizeChiptune(music.Rate);
    music.Channels = 1u;
    music.Source = "the built-in chiptune";
    return music;
}

// A three-voice chiptune, written the way a C64 routine wrote one.
//
// **The sound is the technique, not the waveform.** A SID had three voices and
// no chords, so its music faked them: one voice cycles through the notes of a
// chord at the frame rate, fast enough that the ear hears a chord and slow
// enough that it shimmers. That arpeggio is the single most recognisable thing
// about the era. Two more habits do the rest -- the lead's pulse width is
// swept so a plain square stops sounding like a test tone, and a slow vibrato
// comes in after a note has been held a moment.
//
// Everything below is an original tune in that idiom, in A minor.

/// The player ran once a video frame, which on a PAL machine was 50 Hz. Every
/// per-tick decision here -- which note of the chord, how far through the
/// envelope -- happens at that rate, because that is what gives the style its
/// particular graininess.
const double TicksPerSecond = 50.0;

/// Six ticks a row is about 125 beats a minute in sixteenths.
const nuint TicksPerRow = 6u;

/// A row with nothing in it. Any value no note could have.
const int Rest = -128;

/// The melody, in semitones from A above middle C, one entry per row.
int[] GetLeadNotes() => [
    12, Rest, 10, 12,   15, Rest, 12, 10,
     7, Rest, 10, 12,   15,   17, 15, 12,
    12, Rest, 15, 17,   19, Rest, 17, 15,
    12,   10,  7,  5,    3,    5,  7, 10,
];

/// The chord under each group of four rows: Am, Am, F, F, C, C, G, G. Three
/// notes each, an octave or so below the melody, which is where a SID put
/// them.
int[] GetChordNotes() => [
    -12,  -9,  -5,     -12,  -9,  -5,
    -16, -12,  -7,     -16, -12,  -7,
     -9,  -5,  -2,      -9,  -5,  -2,
    -14, -10,  -7,     -14, -10,  -7,
];

/// The root of each chord, two octaves down, for the bass.
int[] GetBassRoots() => [-24, -24, -28, -28, -21, -21, -26, -26];

/// How many rows the pattern is.
const nuint RowCount = 32u;

/// The tune, rendered as 16-bit mono PCM.
///
/// Three voices are summed and clipped, which is what a chip did too. The
/// phases are accumulated rather than computed from the elapsed time, because
/// a frequency that changes -- and the vibrato changes it every sample --
/// leaves a click at every boundary if the phase is recomputed instead.
byte[] SynthesizeChiptune(uint rate)
{
    nuint samplesPerTick = (nuint)((double)rate / TicksPerSecond);
    nuint samplesPerRow = samplesPerTick * TicksPerRow;
    nuint frames = samplesPerRow * RowCount;

    byte[] samples = new byte[frames * 2u];

    var lead = GetLeadNotes();
    var chords = GetChordNotes();
    var roots = GetBassRoots();

    double leadPhase = 0.0;
    double arpPhase = 0.0;
    double bassPhase = 0.0;

    // The two slow modulations, which run continuously rather than restarting
    // with each note -- that is what makes them sound like one instrument
    // rather than like an effect.
    double pulsePhase = 0.0;
    double vibratoPhase = 0.0;

    for (nuint frame = 0u; frame < frames; frame++)
    {
        nuint row = frame / samplesPerRow;
        nuint intoRow = frame - row * samplesPerRow;
        nuint tick = frame / samplesPerTick;
        double through = (double)intoRow / (double)samplesPerRow;

        nuint chord = row / 4u;

        pulsePhase = pulsePhase + 0.7 / (double)rate;
        vibratoPhase = vibratoPhase + 5.5 / (double)rate;

        // ------------------------------------------------------------ lead

        double leadValue = 0.0;
        int note = lead[row];

        if (note != Rest)
        {
            // Vibrato, held back until the note has sounded for a moment: a
            // C64 routine delayed it by a few ticks for exactly this reason,
            // and it is the difference between expression and seasickness.
            double depth = through < 0.25 ? 0.0 : (through - 0.25) * 0.012;
            double wobble = 1.0 + depth * Math.Sin(vibratoPhase * 6.28318530717958623200);

            leadPhase = leadPhase + ComputeFrequency(note) * wobble / (double)rate;

            // Pulse-width modulation: the duty cycle sweeps between a thin
            // reedy pulse and a hollow square.
            double duty = 0.5 + 0.28 * Math.Sin(pulsePhase * 6.28318530717958623200);

            // A hard attack and a gate that closes before the row ends, which
            // is what separates one note from the next without a rest.
            double envelope = 1.0;
            if (through < 0.03)
                envelope = through / 0.03;
            else if (through > 0.82)
                envelope = (1.0 - through) / 0.18;

            leadValue = ComputePulseWave(leadPhase, duty) * 0.26 * envelope;
        }

        // ------------------------------------------------------- the arpeggio

        // One note of the chord per tick, cycling. This is the whole trick:
        // three notes at 50 Hz is heard as a chord.
        nuint which = tick % 3u;
        int arpNote = chords[chord * 3u + which];
        arpPhase = arpPhase + ComputeFrequency(arpNote) / (double)rate;

        // Softer than the lead and never gated, so it sits underneath as a
        // texture rather than a part.
        double arpValue = ComputePulseWave(arpPhase, 0.5) * 0.11;

        // ------------------------------------------------------------- bass

        // Eighth notes: the root on every other row, plucked.
        double bassValue = 0.0;
        if (row % 2u == 0u)
        {
            bassPhase = bassPhase + ComputeFrequency(roots[chord]) / (double)rate;
            double decay = Math.Pow(1.0 - through, 1.4);
            bassValue = ComputePulseWave(bassPhase, 0.5) * 0.30 * decay;
        }

        // ------------------------------------------------------------- mix

        int sample = (int)((leadValue + arpValue + bassValue) * 30000.0);
        if (sample > 32767)
            sample = 32767;
        if (sample < -32768)
            sample = -32768;

        int stored = sample;
        if (stored < 0)
            stored = stored + 65536;

        samples[frame * 2u] = (byte)(stored & 0xFF);
        samples[frame * 2u + 1u] = (byte)((stored >> 8) & 0xFF);
    }

    return samples;
}

/// A semitone offset from A above middle C, as hertz.
double ComputeFrequency(int semitones)
{
    double ratio = 1.0;
    int steps = semitones;
    while (steps > 0)
    {
        ratio = ratio * 1.05946309435929530;
        steps--;
    }
    while (steps < 0)
    {
        ratio = ratio / 1.05946309435929530;
        steps++;
    }
    return 440.0 * ratio;
}

/// A pulse wave of a given duty cycle, from an accumulated phase in cycles.
///
/// The phase is allowed to grow without bound and only its fraction is used,
/// which costs nothing here and keeps the caller from having to wrap it.
double ComputePulseWave(double cycles, double duty)
{
    double phase = cycles - (double)(long)cycles;
    return phase < duty ? 1.0 : -1.0;
}

// =================================================================== window

nint HandleWindowMessage(HWND window, uint message, nuint wParam, nint lParam)
{
    if (message == WmDestroy)
    {
        PostQuitMessage(0);
        return 0;
    }

    return DefWindowProcW(window, message, wParam, lParam);
}

/// The constant block, packed the way HLSL expects it: a 4x4 matrix and two
/// float4s, 96 bytes.
byte[] PackFrameConstants(Matrix transform, double lightX, double lightY, double lightZ,
                      double red, double green, double blue, double flat)
{
    byte[] bytes = new byte[96u];
    for (nuint i = 0u; i < 16u; i++)
        WriteFloat(bytes, i * 4u, (double)transform.M[i]);

    WriteFloat(bytes, 64u, lightX);
    WriteFloat(bytes, 68u, lightY);
    WriteFloat(bytes, 72u, lightZ);
    WriteFloat(bytes, 76u, 0.0);

    WriteFloat(bytes, 80u, red);
    WriteFloat(bytes, 84u, green);
    WriteFloat(bytes, 88u, blue);
    WriteFloat(bytes, 92u, flat);
    return bytes;
}

int Main()
{
    long limit = 0;
    bool quiet = false;
    bool shot = false;
    String songPath = "";

    for (nuint i = 0u; i < Env.ArgumentCount(); i++)
    {
        String argument = Env.ArgumentAt(i);
        if (argument == "quiet")
            quiet = true;
        else if (argument == "shot")
            shot = true;
        else if (argument.EndsWith(".xm"))
            songPath = argument;
        else
            limit = Convert.ToLong(argument).GetValueOrDefault(limit);
    }

    // ------------------------------------------------------------ the window

    HMODULE instance = GetModuleHandleW(null);

    var windowClass = CreateWindowClass();
    windowClass.Procedure = HandleWindowMessage;
    windowClass.Instance = instance;
    windowClass.Cursor = LoadCursorW(null, CursorArrow());
    windowClass.ClassName = "StainlessCube".ToUtf16().ToPointer();

    if (RegisterClassExW(&windowClass) == 0u)
    {
        Console.WriteError("could not register the class: " + Win32.GetLastErrorMessage());
        return 1;
    }

    Rect wanted = CreateRect(0, 0, 800, 600);
    Rect outer = AdjustRectForFrame(wanted, WsOverlappedWindow, 0u);

    HWND window = CreateWindow("StainlessCube", "Stainless: a cube, a light and a shadow",
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

    var started = Graphics.CreateForWindow((void*)window, 800u, 600u);
    if (!started.Ok)
    {
        Console.WriteError("no Direct3D device");
        return 1;
    }

    var graphics = started.Value;
    Console.WriteLine("Direct3D feature level " + DescribeFeatureLevel(graphics.FeatureLevel));

    var adapters = EnumerateAdapters();
    if (adapters.Count > 0u)
        Console.WriteLine("adapter: " + GetAdapterName(adapters[0u]));

    // ----------------------------------------------------------- the shaders

    // Row-major, so the matrices above reach the GPU as they are written.
    uint flags = D3DCOMPILE_PACK_MATRIX_ROW_MAJOR | D3DCOMPILE_OPTIMIZATION_LEVEL3;

    var vertexCode = Hlsl.CompileShader(GetShaderSource(), "VertexMain", "vs_5_0", flags);
    if (!vertexCode.Ok)
    {
        Console.WriteError("vertex shader:\n" + vertexCode.Error);
        return 1;
    }

    var pixelCode = Hlsl.CompileShader(GetShaderSource(), "PixelMain", "ps_5_0", flags);
    if (!pixelCode.Ok)
    {
        Console.WriteError("pixel shader:\n" + pixelCode.Error);
        return 1;
    }

    VertexField[] fields = [
        VertexField.FromSemantic("POSITION", DXGI_FORMAT_R32G32B32_FLOAT),
        VertexField.FromSemantic("NORMAL", DXGI_FORMAT_R32G32B32_FLOAT),
        VertexField.FromSemantic("COLOR", DXGI_FORMAT_R32G32B32_FLOAT),
    ];

    var made = graphics.CreateMaterial(vertexCode.Value, pixelCode.Value, fields);
    if (!made.Ok)
    {
        Console.WriteError("could not make the material");
        return 1;
    }

    var material = made.Value;

    // ---------------------------------------------------------- the geometry

    byte[] wordVertices = BuildWordVertices("STAINLESS");
    // 36 bytes a vertex, four vertices a square.
    nuint bytesPerQuad = 144u;
    uint wordQuads = (uint)(wordVertices.Length / bytesPerQuad);

    var builtCube = graphics.CreateIndexedMesh(BuildCubeVertices(), 36u, BuildQuadIndices(6u),
                                               D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    var builtFloor = graphics.CreateIndexedMesh(BuildFloorVertices(), 36u, BuildQuadIndices(1u),
                                                D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    var builtWord = graphics.CreateIndexedMesh(wordVertices, 36u, BuildQuadIndices(wordQuads),
                                               D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);

    if (!builtCube.Ok || !builtFloor.Ok || !builtWord.Ok)
    {
        Console.WriteError("could not make the meshes");
        return 1;
    }

    var cube = builtCube.Value;
    var ground = builtFloor.Value;
    var word = builtWord.Value;
    Console.WriteLine("letters: " + Text.FromInteger((long)wordQuads) + " squares");

    var reserved = graphics.CreateConstantBuffer(96u);
    if (!reserved.Ok)
    {
        Console.WriteError("could not make the constant buffer");
        return 1;
    }

    var constants = reserved.Value;
    graphics.SetConstantBuffer(constants, 0u);

    // -------------------------------------------------------------- the music

    Mixer? mixer = null;
    Sound? music = null;

    if (!quiet)
    {
        var engine = Mixer.CreateDefault();
        if (!engine.Ok)
        {
            Console.WriteLine("no audio device; drawing in silence");
        }
        else
        {
            mixer = engine.Value;

            var tune = LoadMusic(songPath);
            var loaded = engine.Value.CreateSound(tune.Samples, tune.Rate, tune.Channels);
            if (loaded.Ok)
            {
                music = loaded.Value;
                loaded.Value.PlayLooping(0.7f);
                Console.WriteLine("music: " + tune.Source + ", " +
                                  Text.FromDouble(loaded.Value.Duration) +
                                  " seconds, looping");
            }
        }
    }

    // ------------------------------------------------------------- the scene

    // Above and to one side, so the shadow lands beside the cube rather than
    // underneath it where nothing would see it.
    double lightX = 3.0;
    double lightY = 6.0;
    double lightZ = -2.4;
    double floorHeight = -1.6;

    var projection = CreatePerspective(Math.Pi / 3.6, 800.0 / 600.0, 0.1, 100.0);
    var view = CreateLookAt(0.0, 2.4, -6.6, 0.0, -0.3, 0.0);
    var viewProjection = MultiplyMatrices(view, projection);

    // A hair above the floor, so the shadow wins the depth test against it.
    var flatten = CreateFloorShadow(lightX, lightY, lightZ, floorHeight + 0.002);

    // The bouncing overlay, in clip space. The letters are 53 font pixels
    // wide; the scale turns that into 0.9 of the screen's width, and the
    // vertical scale matches so the squares stay square.
    double letterScale = 0.62 / (double)MeasureWordWidth("STAINLESS");
    double letterScaleY = letterScale * (800.0 / 600.0);
    double wordWide = letterScale * (double)MeasureWordWidth("STAINLESS");
    double wordHigh = letterScaleY * 7.0;

    double wordX = -wordWide * 0.5;
    double wordY = 0.55;
    double driftX = 0.0065;
    double driftY = 0.0042;

    long drawn = 0;
    while (PumpMessages())
    {
        double time = (double)drawn / 60.0;
        var spin = MultiplyMatrices(CreateRotationX(time * 0.6), CreateRotationY(time * 0.9));
        var model = MultiplyMatrices(spin, CreateTranslation(0.0, 0.2, 0.0));

        graphics.Clear(0.05f, 0.06f, 0.10f, 1.0f);

        // The floor, lit by the same light as everything else.
        graphics.SetAlphaBlend(false);
        graphics.UpdateConstantBuffer(constants,
            PackFrameConstants(viewProjection, lightX, lightY, lightZ, 0.0, 0.0, 0.0, 0.0));
        graphics.DrawMesh(material, ground);

        // The shadow: the cube's own geometry, flattened onto the floor by the
        // light and drawn flat and translucent, so it darkens the floor rather
        // than replacing it.
        graphics.SetAlphaBlend(true);
        graphics.UpdateConstantBuffer(constants,
            PackFrameConstants(MultiplyMatrices(MultiplyMatrices(model, flatten), viewProjection),
                           lightX, lightY, lightZ, 0.04, 0.04, 0.08, 0.55));
        graphics.DrawMesh(material, cube);

        // The cube itself, on top of its shadow.
        graphics.SetAlphaBlend(false);
        graphics.UpdateConstantBuffer(constants,
            PackFrameConstants(MultiplyMatrices(model, viewProjection),
                           lightX, lightY, lightZ, 0.0, 0.0, 0.0, 0.0));
        graphics.DrawMesh(material, cube);

        // The overlay. Its z is zero in clip space, which is the near plane,
        // so it wins the depth test against anything in the scene without
        // needing a state change.
        wordX = wordX + driftX;
        wordY = wordY + driftY;
        if (wordX < -1.0 || wordX + wordWide > 1.0)
        {
            driftX = -driftX;
            wordX = wordX + driftX;
        }
        if (wordY > 1.0 || wordY - wordHigh < -1.0)
        {
            driftY = -driftY;
            wordY = wordY + driftY;
        }

        var letters = MultiplyMatrices(CreateScale(letterScale, letterScaleY, 1.0),
                               CreateTranslation(wordX, wordY - wordHigh, 0.0));

        // Twice: a dark copy a little down and to the right, then the bright
        // one over it. A drop shadow is two draws and makes text readable over
        // anything.
        graphics.UpdateConstantBuffer(constants,
            PackFrameConstants(
                MultiplyMatrices(CreateScale(letterScale, letterScaleY, 1.0),
                    CreateTranslation(wordX + 0.008, wordY - wordHigh - 0.008, 0.0)),
                lightX, lightY, lightZ, 0.02, 0.02, 0.04, 1.0));
        graphics.DrawMesh(material, word);

        graphics.UpdateConstantBuffer(constants,
            PackFrameConstants(letters, lightX, lightY, lightZ, 1.0, 0.86, 0.22, 1.0));
        graphics.DrawMesh(material, word);

        if (shot && drawn == 90)
            graphics.SaveFrame("cube.png");

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

    if (music != null)
        ((Sound)music).Dispose();
    if (mixer != null)
        ((Mixer)mixer).Dispose();

    graphics.Dispose();
    return 0;
}
