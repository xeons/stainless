// SPDX-License-Identifier: 0BSD
module Photo;

import Shapes;

public class Image : Shape
{
    public int Width;
    public Image(int width)
    {
        base("a photograph");
        Width = width;
    }
}
