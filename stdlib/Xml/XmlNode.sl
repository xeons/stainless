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

module Standard.Xml;

import Standard.Collections;
import Standard.Reflection;
import Standard.Convert;
import Standard.Math;

// ----------------------------------------------------------------- elements

/// One element: a name, its attributes, its child elements and its text.
///
/// **Text is gathered rather than interleaved.** A node's `Text` is every
/// character run inside it joined together, which loses where each sat between
/// the children. That is the wrong model for a document with mixed content --
/// a paragraph with `<em>` inside it -- and the right one for the data XML is
/// mostly used to carry. `Children` and `Text` together are what a
/// configuration file has.
///
/// **Whitespace between elements is formatting.** In an element with child
/// elements, a run of text that is only whitespace in the source is dropped:
/// it is the indentation a person or `ToXmlTextIndented` put there. A run with
/// anything else in it is kept whole, as is a CDATA section or a character
/// reference, and an element with no children keeps all of its text.
public class XmlNode
{
    /// The tag name, without any namespace prefix being separated out -- a
    /// prefix arrives as part of the name, since nothing here resolves one.
    public String Name;

    /// The attributes, in the order they were written. Never null; an element
    /// with none has an empty list.
    public XmlAttributes Attributes;

    /// The child elements, in document order. Never null.
    public List<XmlNode> Children;

    /// Every character run inside this element, joined. Where each run sat
    /// relative to the children is not kept -- see the note above.
    public String Text;

    /// An element with that name, no attributes, no children and no text.
    public XmlNode(String name)
    {
        Name = name;
        Attributes = new XmlAttributes();
        Children = new List<XmlNode>();
        Text = "";
    }

    /// The first child of that name, or null.
    public XmlNode? FindChild(String name)
    {
        for (nuint i = 0u; i < Children.Count; i++)
        {
            var child = Children[i];
            if (child.Name == name)
                return child;
        }
        return null;
    }

    /// Every child of that name, in order.
    public List<XmlNode> FindChildren(String name)
    {
        var found = new List<XmlNode>();
        for (nuint i = 0u; i < Children.Count; i++)
        {
            var child = Children[i];
            if (child.Name == name)
                found.Add(child);
        }
        return found;
    }

    /// The text of the first child of that name, or the fallback.
    ///
    /// @param name      the child element to look for
    /// @param fallback  what to answer when there is no such child
    public String FindChildText(String name, String fallback)
    {
        var child = FindChild(name);
        if (child == null)
            return fallback;
        return child.Text;
    }

    /// Appends a child element. Nothing checks for a cycle, so do not add a
    /// node to one of its own descendants: writing the tree would not end.
    public void Add(XmlNode child) => Children.Add(child);
}
