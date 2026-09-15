// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

// What each kind of token is drawn in.
//
// **One object, not a set of constants**, so that a second theme is a second
// object rather than an edit. The editor holds one and asks it per token.
module Ide.Editor;

import Forms.Drawing;
import Ide.Lang;

/// The colours a code editor draws with.
public class Theme
{
    public Color Background;
    public Color Text;
    public Color Comment;
    public Color DocComment;
    public Color Keyword;
    public Color TypeName;
    public Color Number;
    public Color Literal;
    public Color Directive;
    public Color Operator;

    /// The gutter, and the numbers down it.
    public Color GutterBack;
    public Color GutterText;
    /// The number of the line the caret is on, which is brighter than the rest.
    public Color GutterCurrent;

    /// Behind the line the caret is on.
    public Color CurrentLine;
    /// Behind selected text.
    public Color Selection;
    public Color SelectionText;
    /// The rule down the right-hand side.
    public Color Margin;

    /// The light theme, which is the one a first run gets.
    ///
    /// **Not chosen for looks alone.** A reader scanning code is looking for
    /// structure, so the things that carry it -- keywords, types -- are the
    /// saturated colours, and the things that do not -- operators, brackets --
    /// stay close to the body text. Comments are the one deliberate exception:
    /// green and low-contrast, so that prose beside code reads as an aside
    /// rather than competing with it.
    public static Theme Light()
    {
        var theme = new Theme();
        theme.Background    = Color.FromRgb(255, 255, 255);
        theme.Text          = Color.FromRgb( 24,  24,  28);
        theme.Comment       = Color.FromRgb( 34, 134,  58);
        theme.DocComment    = Color.FromRgb( 22, 110,  92);
        theme.Keyword       = Color.FromRgb(170,  13, 145);
        theme.TypeName      = Color.FromRgb( 35,  91, 166);
        theme.Number        = Color.FromRgb(  9, 134,  88);
        theme.Literal       = Color.FromRgb(163,  21,  21);
        theme.Directive     = Color.FromRgb(128,  92,  20);
        theme.Operator      = Color.FromRgb( 70,  70,  78);

        theme.GutterBack    = Color.FromRgb(246, 246, 248);
        theme.GutterText    = Color.FromRgb(150, 150, 158);
        theme.GutterCurrent = Color.FromRgb( 60,  60,  68);

        theme.CurrentLine   = Color.FromRgb(245, 245, 250);
        theme.Selection     = Color.FromRgb(181, 213, 255);
        theme.SelectionText = Color.FromRgb( 24,  24,  28);
        theme.Margin        = Color.FromRgb(232, 232, 238);
        return theme;
    }

    /// The dark theme.
    public static Theme Dark()
    {
        var theme = new Theme();
        theme.Background    = Color.FromRgb( 30,  30,  34);
        theme.Text          = Color.FromRgb(220, 220, 226);
        theme.Comment       = Color.FromRgb(106, 153,  85);
        theme.DocComment    = Color.FromRgb(106, 168, 150);
        theme.Keyword       = Color.FromRgb(197, 134, 192);
        theme.TypeName      = Color.FromRgb( 78, 201, 176);
        theme.Number        = Color.FromRgb(181, 206, 168);
        theme.Literal       = Color.FromRgb(206, 145, 120);
        theme.Directive     = Color.FromRgb(204, 167,  86);
        theme.Operator      = Color.FromRgb(190, 190, 198);

        theme.GutterBack    = Color.FromRgb( 30,  30,  34);
        theme.GutterText    = Color.FromRgb(110, 110, 120);
        theme.GutterCurrent = Color.FromRgb(200, 200, 210);

        theme.CurrentLine   = Color.FromRgb( 40,  40,  46);
        theme.Selection     = Color.FromRgb( 38,  79, 120);
        theme.SelectionText = Color.FromRgb(235, 235, 240);
        theme.Margin        = Color.FromRgb( 52,  52,  58);
        return theme;
    }

    /// What a token of this kind is drawn in.
    public Color ColorFor(TokenKind kind)
    {
        if (kind == TokenKind.Comment)
            return Comment;
        if (kind == TokenKind.BlockComment)
            return Comment;
        if (kind == TokenKind.DocComment)
            return DocComment;
        if (kind == TokenKind.Keyword)
            return Keyword;
        if (kind == TokenKind.ContextualKeyword)
            return Keyword;
        if (kind == TokenKind.TypeName)
            return TypeName;
        if (kind == TokenKind.Number)
            return Number;
        if (kind == TokenKind.Text)
            return Literal;
        if (kind == TokenKind.Character)
            return Literal;
        if (kind == TokenKind.Directive)
            return Directive;
        if (kind == TokenKind.Attribute)
            return TypeName;
        if (kind == TokenKind.Operator)
            return Operator;
        if (kind == TokenKind.Bracket)
            return Operator;
        return Text;
    }
}
