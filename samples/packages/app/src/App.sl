// SPDX-License-Identifier: 0BSD
module App;

import Standard.Console;

// The project file next to this one says where `shapes` comes from and which
// versions will do. Nothing here says anything about it: an import names a
// module, and where that module's code came from is the build's business.
import Shapes;

int Main()
{
    var canvas = new Canvas(100, 50);

    canvas.DrawShape(MakeSquare(10));
    canvas.DrawShape(MakeSquare(20));
    canvas.DrawShape(MakeSquare(400));       // too big for the canvas, and not drawn

    var extent = canvas.Extent;

    Console.WriteLine($"canvas {extent.Width}x{extent.Height}, area {extent.Area}");
    Console.WriteLine($"drawn {canvas.Drawn} of 3");

    return canvas.Drawn == 2 ? 0 : 1;
}
