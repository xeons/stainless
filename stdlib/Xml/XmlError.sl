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

// ------------------------------------------------------------------- errors

/// Why a document could not be read.
public enum XmlError
{
    /// Nothing went wrong.
    None,

    /// A character that cannot appear here.
    Unexpected,

    /// A `<` with no `>`.
    UnclosedTag,

    /// A quoted attribute value with no closing quote.
    UnclosedText,

    /// An end tag naming a different element than the start tag it closes.
    MismatchedEnd,

    /// The document stopped inside something.
    UnexpectedEnd,

    /// A tag or attribute name that is not one.
    BadName,

    /// An `&` that is not an entity this reads. The five XML entities and
    /// numeric character references are what it reads; a DTD's own are not,
    /// and nor is a reference to a character XML does not allow.
    BadEntity,

    /// Nothing but whitespace and comments -- no root element.
    NoRoot,

    /// A second root element. XML allows exactly one.
    TrailingContent,

    /// Nesting past `MaxDepth`.
    TooDeep,

    /// One element naming an attribute twice.
    DuplicateAttribute,

    /// A type with no field metadata to map onto.
    NotReflected,
}
