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

    // ------------------------------------------------------------ debugging

    /// The breakpoint disc, and its outline.
    ///
    /// **Red, and the same red in both themes.** A breakpoint is a mark on the
    /// program rather than a piece of syntax, and the one thing a person looks
    /// for while scrolling; a dark theme that made it politer would make it
    /// harder to find, which is the opposite of what it is for.
    public Color BreakpointFill;
    public Color BreakpointEdge;

    /// A breakpoint the last build found no code for, drawn hollow. The colour
    /// is the same -- what says it did not bind is that it is not filled in.
    public Color BreakpointHollow;

    /// The line the program is stopped on, and the arrow in the margin beside
    /// it.
    public Color CurrentStatement;
    public Color CurrentStatementArrow;

    /// The line a selected stack frame is on, when it is not the top one.
    /// Paler, because that frame is not where the program will resume.
    public Color CalledFrom;

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

        theme.BreakpointFill   = Color.FromRgb(197,  34,  31);
        theme.BreakpointEdge   = Color.FromRgb(150,  20,  18);
        theme.BreakpointHollow = Color.FromRgb(197,  34,  31);

        theme.CurrentStatement      = Color.FromRgb(255, 241, 170);
        theme.CurrentStatementArrow = Color.FromRgb(216, 170,  16);
        theme.CalledFrom            = Color.FromRgb(230, 230, 190);
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

        theme.BreakpointFill   = Color.FromRgb(224,  60,  56);
        theme.BreakpointEdge   = Color.FromRgb(140,  24,  22);
        theme.BreakpointHollow = Color.FromRgb(224,  60,  56);

        theme.CurrentStatement      = Color.FromRgb( 74,  66,  28);
        theme.CurrentStatementArrow = Color.FromRgb(232, 194,  70);
        theme.CalledFrom            = Color.FromRgb( 54,  52,  36);
        return theme;
    }

    /// What a token of this kind is drawn in.
    ///
    /// A table, and written as one: which kinds share a colour is the whole
    /// content of this method, and stacked labels say it where a run of `if`s
    /// hid it inside the order they happened to be in.
    public Color ColorFor(TokenKind kind)
    {
        switch (kind)
        {
            case TokenKind.Comment:
            case TokenKind.BlockComment:
                return Comment;

            case TokenKind.DocComment:
                return DocComment;

            case TokenKind.Keyword:
            case TokenKind.ContextualKeyword:
                return Keyword;

            case TokenKind.TypeName:
            case TokenKind.Attribute:
                return TypeName;

            case TokenKind.Number:
                return Number;

            case TokenKind.Text:
            case TokenKind.Character:
                return Literal;

            case TokenKind.Directive:
                return Directive;

            case TokenKind.Operator:
            case TokenKind.Bracket:
                return Operator;

            default:
                return Text;
        }
    }
}
