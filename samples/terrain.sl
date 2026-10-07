// SPDX-License-Identifier: 0BSD
//
// `terrain`: a landscape shaded with SIMD vectors, written out as an image
// with a preview in the console.
//
//   stainless run samples/terrain.sl
//   stainless run samples/terrain.sl -- valley.ppm
//
// Every pixel is a handful of vector operations: the surface normal is the
// cross product of two slopes, the light is a dot product with the sun, the
// colour is a blend between bands, water shines where a mask says it is, and
// the distance fades into the sky. Each is a few instructions over four lanes
// at once -- SSE on x86, NEON on ARM -- from the one source.
//
// The image is a PPM, which every image viewer opens and which is short
// enough to write by hand: a line of text, then three bytes a pixel.
module Terrain;

import Standard.Console;
import Standard.File;
import Standard.IO;
import Standard.Math;
import Standard.Text;

const int Width = 192;
const int Height = 108;

/// How steep the land looks: heights are 0 to 1, and a pixel is one unit.
const float Relief = 40.0f;

/// Where the sea is. Land below it is drawn as water, flat and shining.
const float WaterLevel = 0.44f;

/// The light, coming from the upper left and fairly high, already of length one.
vfloat3 SunDirection() => vfloat3.Normalize(new vfloat3(-0.6f, -0.5f, 0.6f));

/// Where the eye is: across the sea from the sun, where its reflection is.
vfloat3 ViewDirection() => vfloat3.Normalize(new vfloat3(0.6f, 0.5f, 0.6f));

/// RGBA colours, as the vectors that carry them; alpha is always one.
vfloat4 Rgb(float red, float green, float blue) => new vfloat4(red, green, blue, 1);

/// A value from 0 to 1 for a point of the integer grid, the same every time:
/// a hash of the two coordinates.
float LatticeValue(int x, int y)
{
    uint mixed = (uint)x * 374761393u + (uint)y * 668265263u;
    mixed = (mixed ^ (mixed >> 13)) * 1274126177u;
    mixed = mixed ^ (mixed >> 16);
    return (float)(mixed & 0xFFFFu) / 65535.0f;
}

/// Value noise: the four grid values around a point, blended smoothly.
///
/// The four corners are one vector, so the blend across is one `Lerp` of
/// two halves of it -- the near corners against the far ones -- and the blend
/// down is a second.
float SmoothNoise(float x, float y)
{
    int left = (int)Floor(x);
    int top = (int)Floor(y);
    float across = x - (float)left;
    float down = y - (float)top;

    // Smoothstep, so the slope is zero at each grid point and no seam shows.
    across = across * across * (3 - 2 * across);
    down = down * down * (3 - 2 * down);

    vfloat4 corners = new vfloat4(LatticeValue(left, top), LatticeValue(left + 1, top),
                                  LatticeValue(left, top + 1), LatticeValue(left + 1, top + 1));
    vfloat2 rows = vfloat2.Lerp(corners.xz, corners.yw, across);
    return rows.x + (rows.y - rows.x) * down;
}

/// The height of the land at a point, from 0 to 1: noise at five scales, each
/// half as tall and twice as fine as the last, which is what makes hills
/// with smaller hills on them.
float HeightAt(float x, float y)
{
    float height = 0;
    float amplitude = 0.5f;
    float scale = 1.0f / 40.0f;
    float total = 0;
    for (int octave = 0; octave < 5; octave++)
    {
        height = height + amplitude * SmoothNoise(x * scale + (float)(octave * 17), y * scale);
        total = total + amplitude;
        amplitude = amplitude * 0.5f;
        scale = scale * 2;
    }
    return height / total;
}

/// The height of the waves on the sea at a point: two scales of noise.
float WaveAt(float x, float y)
    => SmoothNoise(x * 0.3f, y * 0.3f) + 0.5f * SmoothNoise(x * 0.7f + 37, y * 0.7f);

/// A height from the map, the edge repeated past the edge.
float SampleHeight(float[] heights, int x, int y)
{
    int column = x < 0 ? 0 : x >= Width ? Width - 1 : x;
    int row = y < 0 ? 0 : y >= Height ? Height - 1 : y;
    return heights[(nuint)(row * Width + column)];
}

/// The surface normal at a pixel: the cross product of the slope across and
/// the slope down, each measured to the neighbours either side.
vfloat3 NormalAt(float[] heights, int x, int y)
{
    float across = SampleHeight(heights, x + 1, y) - SampleHeight(heights, x - 1, y);
    float down = SampleHeight(heights, x, y + 1) - SampleHeight(heights, x, y - 1);
    vfloat3 east = new vfloat3(2, 0, across * Relief);
    vfloat3 south = new vfloat3(0, 2, down * Relief);
    return vfloat3.Normalize(vfloat3.Cross(east, south));
}

/// The ground's own colour at a height, blended between bands so that no
/// edge between them shows.
vfloat4 GroundColour(float height)
{
    vfloat4 sand = Rgb(0.76f, 0.70f, 0.50f);
    vfloat4 grass = Rgb(0.25f, 0.55f, 0.20f);
    vfloat4 forest = Rgb(0.12f, 0.35f, 0.14f);
    vfloat4 rock = Rgb(0.45f, 0.42f, 0.40f);
    vfloat4 snow = Rgb(0.95f, 0.96f, 1.00f);

    float beach = WaterLevel + 0.03f;
    if (height < beach)
        return vfloat4.Lerp(sand, grass, Fraction(height, WaterLevel, beach));
    if (height < 0.58f)
        return vfloat4.Lerp(grass, forest, Fraction(height, beach, 0.58f));
    if (height < 0.68f)
        return vfloat4.Lerp(forest, rock, Fraction(height, 0.58f, 0.68f));
    return vfloat4.Lerp(rock, snow, Fraction(height, 0.68f, 0.76f));
}

/// Where a value lies between two others, as 0 to 1.
float Fraction(float value, float from, float to)
{
    float t = (value - from) / (to - from);
    return t < 0 ? 0 : t > 1 ? 1 : t;
}

/// The colour of one pixel, lit, glinting where it is water, and faded with
/// distance. The top of the image is the far edge.
vfloat4 ShadePixel(float[] heights, int x, int y)
{
    float height = SampleHeight(heights, x, y);
    bool wet = height < WaterLevel;

    // The sea is flat but for waves, whose slopes tilt its normal a little,
    // and its colour deepens with the land under it.
    float fx = (float)x;
    float fy = (float)y;
    vfloat3 ripple = new vfloat3(-0.5f * (WaveAt(fx + 1, fy) - WaveAt(fx - 1, fy)),
                                 -0.5f * (WaveAt(fx, fy + 1) - WaveAt(fx, fy - 1)), 1);
    vfloat3 normal = wet ? vfloat3.Normalize(ripple) : NormalAt(heights, x, y);
    vfloat4 surface = wet
        ? vfloat4.Lerp(Rgb(0.05f, 0.18f, 0.35f), Rgb(0.15f, 0.45f, 0.60f),
                       Fraction(height, WaterLevel - 0.15f, WaterLevel))
        : GroundColour(height);

    // Lambert: how directly the sun falls on the surface, never below zero,
    // plus the light the sky gives everything.
    vfloat3 sun = SunDirection();
    float diffuse = vfloat3.Max(new vfloat3(vfloat3.Dot(normal, sun)), vfloat3.Zero).x;
    float light = 0.35f + 0.85f * diffuse;
    vfloat4 lit = surface * new vfloat4(light, light, light, 1);

    // The sun's reflection on the water: the light mirrored about the normal,
    // seen from the eye, sharpened by repeated squaring into sparkles.
    vfloat3 mirrored = normal * (2 * vfloat3.Dot(normal, sun)) - sun;
    float glint = vfloat3.Max(new vfloat3(vfloat3.Dot(mirrored, ViewDirection())), vfloat3.Zero).x;
    for (int i = 0; i < 9; i++)
        glint = glint * glint;
    glint = glint * 0.6f;

    // One mask for all four lanes, from the same comparison done lane by
    // lane: where it holds, the glint is added; elsewhere the colour stands.
    vint4 water = vfloat4.LessThan(new vfloat4(height), new vfloat4(WaterLevel));
    lit = vfloat4.Select(water, lit + new vfloat4(glint, glint, glint, 0), lit);

    // Haze: the farther, the more of the sky's colour.
    float distance = 1.0f - (float)y / (float)(Height - 1);
    vfloat4 sky = Rgb(0.70f, 0.80f, 0.92f);
    return vfloat4.Lerp(lit, sky, distance * distance * 0.65f);
}

/// A colour as three bytes. The cast converts every lane at once, saturating,
/// so a lane past one is 255 rather than wrapping.
void StorePixel(byte[] image, nuint at, vfloat4 colour)
{
    vint4 bytes = (vint4)(vfloat4.Clamp(colour, 0, 1) * 255.0f + 0.5f);
    image[at] = (byte)bytes.x;
    image[at + 1u] = (byte)bytes.y;
    image[at + 2u] = (byte)bytes.z;
}

/// The image as a PPM: its header, then the pixels row by row.
byte[] EncodePpm(vfloat4[] colours)
{
    String header = "P6\n" + Text.FromInteger(Width) + " " + Text.FromInteger(Height) + "\n255\n";
    nuint start = header.ByteLength();
    byte[] file = new byte[start + (nuint)(Width * Height * 3)];
    for (nuint i = 0u; i < start; i++)
        file[i] = header.GetByteAt(i);
    for (nuint i = 0u; i < colours.Length; i++)
        StorePixel(file, start + i * 3u, colours[i]);
    return file;
}

/// The image in characters: each one the average of a block of pixels, as
/// light as that block is bright.
void PrintPreview(vfloat4[] colours, int columns, int rows)
{
    String ramp = " .:-=+*#%@";
    vfloat4 luminance = new vfloat4(0.2126f, 0.7152f, 0.0722f, 0);
    int blockWidth = Width / columns;
    int blockHeight = Height / rows;

    for (int row = 0; row < rows; row++)
    {
        var line = new StringBuilder();
        for (int column = 0; column < columns; column++)
        {
            vfloat4 sum = vfloat4.Zero;
            for (int y = 0; y < blockHeight; y++)
                for (int x = 0; x < blockWidth; x++)
                    sum = sum + colours[(nuint)((row * blockHeight + y) * Width + column * blockWidth + x)];

            float bright = vfloat4.Dot(sum / (float)(blockWidth * blockHeight), luminance);
            int step = (int)(bright * (float)(ramp.ByteLength() - 1u) + 0.5f);
            line.AppendByte(ramp.GetByteAt((nuint)(step < 0 ? 0 : step)));
        }
        Console.WriteLine(line.ToText());
    }
}

int Main(String[] args)
{
    String path = args.Length > 0u ? args[0u] : "terrain.ppm";

    float[] heights = new float[(nuint)(Width * Height)];
    for (int y = 0; y < Height; y++)
        for (int x = 0; x < Width; x++)
            heights[(nuint)(y * Width + x)] = HeightAt((float)x, (float)y);

    vfloat4[] colours = new vfloat4[(nuint)(Width * Height)];
    vfloat4 total = vfloat4.Zero;
    for (int y = 0; y < Height; y++)
    {
        for (int x = 0; x < Width; x++)
        {
            vfloat4 colour = ShadePixel(heights, x, y);
            colours[(nuint)(y * Width + x)] = colour;
            total = total + colour;
        }
    }

    PrintPreview(colours, 64, 18);

    if (File.WriteAllBytes(path, EncodePpm(colours)) != IOError.None)
    {
        Console.WriteLine("could not write " + path);
        return 1;
    }

    vfloat4 average = total / (float)(Width * Height);
    Console.WriteLine($"wrote {path}, {Width} by {Height}; the average colour is {average:F3}");
    return 0;
}
