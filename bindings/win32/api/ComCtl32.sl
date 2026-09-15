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

// `comctl32.dll`: the controls Windows did not ship in 1985.
//
// The tree, the list, the tabs, the toolbar, the status bar, the progress bar
// and the slider all live here rather than in `user32`, and all of them are
// driven the same way: a window class you create like any other, messages you
// send it, and `WM_NOTIFY` coming back with a structure whose first field says
// what happened.
//
// **`WM_NOTIFY`, not `WM_COMMAND`.** The older controls report by packing a
// code into `WPARAM`; these post a pointer to a structure that begins with an
// `NMHDR`, and each control extends it with a longer one for the notifications
// that carry more. So a parent reads the header, decides from `Code` which
// longer structure it really has, and casts. That is the whole convention and
// it is why the structures below come in families.
//
// **Two versions of this library exist and a program gets the old one by
// default.** `comctl32` version 6 -- the themed controls -- is reached only
// through a side-by-side manifest naming it; without one, Windows loads version
// 5 and the controls look like Windows 2000. `InitCommonControlsEx` must be
// called either way, to register the window classes a program asks for.
module Win32.ComCtl32;

#if WINDOWS

import Win32.Handles;
import Win32.User32;

// ================================================================= the tags
//
// `commctrl.h` declares these rather than `windef.h`, so they are here rather
// than in `Win32.Handles`, on the same terms: a struct nothing defines, and a
// pointer to it, so that an image list cannot be passed where a tree item
// belongs.

public struct HIMAGELIST__;
public struct HTREEITEM__;

/// A list of same-sized pictures, indexed by number. What a toolbar, a tree and
/// a list get their icons from.
public using HIMAGELIST = HIMAGELIST__*;

/// One node of a tree. Not an index: a tree is a linked structure and this is
/// the only way to name a place in it.
public using HTREEITEM = HTREEITEM__*;

// ============================================================ initialization

public struct InitCommonControlsInfo {
    public uint Size;
    public uint Classes;
}

public extern "C" {
    /// Registers the window classes named in the mask. Must be called before
    /// any of these controls is created, and answers false if the library
    /// could not be loaded at all.
    int InitCommonControlsEx(InitCommonControlsInfo* info);
}

public const uint IccListViewClasses = 0x00000001u;
public const uint IccTreeViewClasses = 0x00000002u;
public const uint IccBarClasses      = 0x00000004u;  // toolbar, status, track, tooltip
public const uint IccTabClasses      = 0x00000008u;
public const uint IccUpDownClass     = 0x00000010u;
public const uint IccProgressClass   = 0x00000020u;
public const uint IccHotKeyClass     = 0x00000040u;
public const uint IccAnimateClass    = 0x00000080u;
public const uint IccWinLogoClasses  = 0x000000FFu;
public const uint IccDateClasses     = 0x00000100u;
public const uint IccComboEx         = 0x00000200u;
public const uint IccStandardClasses = 0x00004000u;
public const uint IccLinkClass       = 0x00008000u;

// ================================================================= WM_NOTIFY

/// The header every `WM_NOTIFY` carries, and the whole of what most of them
/// are. `Code` is read as a *signed* number, because every one of these
/// constants is negative -- Windows numbers notification codes downwards from
/// zero so that they cannot collide with anything a program invents.
public struct NotifyHeader {
    public HWND  From;
    public nuint Id;
    public int   Code;
}

/// The codes every control can send.
public const int NmClick       = -2;
public const int NmDoubleClick = -3;
public const int NmReturn      = -4;
public const int NmRightClick  = -5;
public const int NmSetFocus    = -7;
public const int NmKillFocus   = -8;
public const int NmCustomDraw  = -12;
public const int NmReleasedCapture = -16;

// ================================================================ image list

public extern "C" {
    HIMAGELIST ImageList_Create(int width, int height, uint flags,
                                int initial, int grow);
    int        ImageList_Destroy(HIMAGELIST list);
    int        ImageList_Add(HIMAGELIST list, HBITMAP image, HBITMAP mask);
    int        ImageList_AddMasked(HIMAGELIST list, HBITMAP image, uint mask);
    int        ImageList_AddIcon(HIMAGELIST list, HICON icon);
    int        ImageList_ReplaceIcon(HIMAGELIST list, int index, HICON icon);
    int        ImageList_Remove(HIMAGELIST list, int index);
    int        ImageList_GetImageCount(HIMAGELIST list);
    int        ImageList_Draw(HIMAGELIST list, int index, HDC dc,
                              int x, int y, uint style);

    /// Builds a whole list from one wide bitmap, cut into `width`-wide frames.
    ///
    /// This is the shape a toolbar's icons have had since Windows 95: one
    /// strip in the binary's resources, sliced on load. `name` is a resource
    /// name -- `MAKEINTRESOURCE` for an id -- unless `flags` includes
    /// `LrLoadFromFile`, in which case it is a path and `instance` is ignored.
    ///
    /// `mask` is the colour to treat as transparent. The convention is magenta,
    /// which is why toolbar bitmaps have been magenta for thirty years;
    /// `CLR_NONE` means the image has no transparency at all.
    HIMAGELIST ImageList_LoadImageW(HINSTANCE instance, char16* name, int width,
                                    int grow, uint mask, uint kind, uint flags);
}

/// `CLR_NONE`: no colour is transparent. `CLR_DEFAULT` takes the bitmap's own.
public const uint ClrNone    = 0xFFFFFFFFu;
public const uint ClrDefault = 0xFF000000u;

public const uint IlcMask   = 0x0001u;
public const uint IlcColor4 = 0x0004u;
public const uint IlcColor8 = 0x0008u;
public const uint IlcColor16 = 0x0010u;
public const uint IlcColor24 = 0x0018u;
public const uint IlcColor32 = 0x0020u;

public const uint IldNormal      = 0x0000u;
public const uint IldTransparent = 0x0001u;

// =================================================================== button
//
// **A picture on an ordinary `BUTTON` is a version 6 feature.** `BS_BITMAP` has
// been there since Windows 95 and draws the picture *instead of* the caption,
// which is not what anyone wants; `BCM_SETIMAGELIST` draws both and lays them
// out, and arrived with the themed common controls. That is one more reason the
// manifest is not optional.

/// `BCM_FIRST`, the base every one of these messages is an offset from.
public const uint BcmFirst = 0x1600u;

public const uint BcmSetImageList  = 0x1602u;  // BCM_FIRST + 0x0002
public const uint BcmGetImageList  = 0x1603u;
public const uint BcmSetTextMargin = 0x1604u;

/// `BUTTON_IMAGELIST`: the picture a button draws, where it sits, and how much
/// room is left around it.
///
/// The margin is what the spacing between picture and caption is made of --
/// there is no separate field for it, so a gap on the caption's side of the
/// picture is a margin on that side.
public struct ButtonImageList {
    public HIMAGELIST Images;
    public Rect       Margin;
    public uint       Align;
}

public const uint ButtonImageListAlignLeft   = 0u;
public const uint ButtonImageListAlignRight  = 1u;
public const uint ButtonImageListAlignTop    = 2u;
public const uint ButtonImageListAlignBottom = 3u;
public const uint ButtonImageListAlignCenter = 4u;

// =================================================================== toolbar

/// `TBBUTTON`: one button in a toolbar.
public struct ToolBarButton {
    public int   Bitmap;
    public int   Command;
    public byte  State;
    public byte  Style;
    public byte  Reserved0;
    public byte  Reserved1;
    public byte  Reserved2;
    public byte  Reserved3;
    public byte  Reserved4;
    public byte  Reserved5;
    public nuint Data;
    public nuint Text;
}

public const uint ToolBarMessageFirst = 0x0400u;   // WM_USER

public const uint TbAddBitmap       = 0x0413u;
public const uint TbAddButtonsW     = 0x0444u;
public const uint TbInsertButtonW   = 0x0443u;
public const uint TbDeleteButton    = 0x0416u;
public const uint TbButtonCount     = 0x0418u;
public const uint TbSetImageList    = 0x0430u;
public const uint TbAutoSize        = 0x0421u;
public const uint TbSetButtonSize   = 0x041Fu;
public const uint TbGetButtonSize   = 0x043Au;
public const uint TbSetExtendedStyle = 0x0454u;
public const uint TbButtonStructSize = 0x041Eu;
public const uint TbEnableButton    = 0x0401u;
public const uint TbCheckButton     = 0x0402u;
public const uint TbIsButtonChecked = 0x040Au;
public const uint TbSetMaxTextRows  = 0x043Cu;
public const uint TbGetItemRect     = 0x041Du;

/// Toolbar button styles.
public const byte BtnsButton    = 0u;
public const byte BtnsSeparator = 1u;
public const byte BtnsCheck     = 2u;
public const byte BtnsGroup     = 4u;
public const byte BtnsDropDown  = 8u;
public const byte BtnsAutoSize  = 16u;
public const byte BtnsShowText  = 64u;

/// Toolbar button states.
public const byte TbStateChecked  = 0x01u;
public const byte TbStateEnabled  = 0x04u;
public const byte TbStateHidden   = 0x08u;

/// Toolbar window styles.
public const uint TbStyleToolTips  = 0x0100u;
public const uint TbStyleWrapable  = 0x0200u;
public const uint TbStyleFlat      = 0x0800u;
public const uint TbStyleList      = 0x1000u;
public const uint TbStyleTransparent = 0x8000u;
public const uint CcsNoDivider     = 0x00000040u;
public const uint CcsNoResize      = 0x00000004u;
public const uint CcsNoParentAlign = 0x00000008u;
public const uint CcsTop           = 0x00000001u;
public const uint CcsBottom        = 0x00000003u;

public const uint TbExtendedDrawDdArrows = 0x00000001u;

// ================================================================ status bar

public const uint SbSetText     = 0x040Bu;   // SB_SETTEXTW
public const uint SbSetTextW    = 0x040Bu;
public const uint SbGetTextW    = 0x040Du;
public const uint SbSetParts    = 0x0404u;
public const uint SbGetParts    = 0x0406u;
public const uint SbSetMinHeight = 0x0408u;
public const uint SbSimple      = 0x0409u;

public const uint SbarsSizeGrip = 0x0100u;

// ============================================================== progress bar

public const uint PbmSetRange   = 0x0401u;
public const uint PbmSetPos     = 0x0402u;
public const uint PbmDeltaPos   = 0x0403u;
public const uint PbmSetStep    = 0x0404u;
public const uint PbmStepIt     = 0x0405u;
public const uint PbmSetRange32 = 0x0406u;
public const uint PbmGetPos     = 0x0408u;
public const uint PbmSetMarquee = 0x040Au;
public const uint PbmSetState   = 0x0410u;

public const uint PbsSmooth   = 0x01u;
public const uint PbsVertical = 0x04u;
public const uint PbsMarquee  = 0x08u;

public const uint PbstNormal = 0x0001u;
public const uint PbstError  = 0x0002u;
public const uint PbstPaused = 0x0003u;

// ================================================================= track bar

public const uint TbmGetPos      = 0x0400u;
public const uint TbmSetPos      = 0x0405u;
public const uint TbmSetRange    = 0x0406u;
public const uint TbmSetRangeMin = 0x0407u;
public const uint TbmSetRangeMax = 0x0408u;
public const uint TbmSetTicFreq  = 0x0414u;
public const uint TbmSetPageSize = 0x0415u;
public const uint TbmSetLineSize = 0x0417u;

public const uint TbsAutoTicks = 0x0001u;
public const uint TbsVertical  = 0x0002u;
public const uint TbsHorizontal = 0x0000u;
public const uint TbsNoTicks   = 0x0010u;
public const uint TbsBoth      = 0x0008u;
public const uint TbsTop       = 0x0004u;

// =============================================================== tab control

/// `TCITEMW`.
public struct TabItem {
    public uint    Mask;
    public uint    State;
    public uint    StateMask;
    public char16* Text;
    public int     TextLength;
    public int     Image;
    public nuint   Param;
}

/// **The wide variants are a long way from the ANSI ones.** `TCM_INSERTITEMW`
/// is `TCM_FIRST + 62` and `TCM_INSERTITEMA` is `TCM_FIRST + 7`; sending the
/// second with a UTF-16 pointer does not fail, it reads the text as ANSI and
/// stops at the first character's zero high byte. So a list shows "A" where it
/// was given "Apples", and a tab is not inserted at all.
public const uint TcmInsertItemW = 0x133Eu;   // TCM_FIRST + 62
public const uint TcmDeleteItem  = 0x1308u;
public const uint TcmDeleteAllItems = 0x1309u;
public const uint TcmGetItemCount = 0x1304u;
public const uint TcmGetCurSel   = 0x130Bu;
public const uint TcmSetCurSel   = 0x130Cu;
public const uint TcmAdjustRect  = 0x1328u;
public const uint TcmSetItemW    = 0x133Du;   // TCM_FIRST + 61
public const uint TcmSetImageList = 0x1303u;

public const uint TcifText  = 0x0001u;
public const uint TcifImage = 0x0002u;
public const uint TcifParam = 0x0008u;

public const int TcnSelChange   = -551;
public const int TcnSelChanging = -552;

// ================================================================= tree view

/// `TVITEMW`.
public struct TreeItem {
    public uint    Mask;
    public HTREEITEM Item;
    public uint    State;
    public uint    StateMask;
    public char16* Text;
    public int     TextLength;
    public int     Image;
    public int     SelectedImage;
    public int     Children;
    public nuint   Param;
}

/// `TVINSERTSTRUCTW`, which is a parent, a sibling and an item.
public struct TreeInsert {
    public HTREEITEM Parent;
    public HTREEITEM InsertAfter;
    public TreeItem  Item;
}

/// `NMTREEVIEWW`: what a tree reports when something happened to an item.
public struct NotifyTreeView {
    public NotifyHeader Header;
    public uint         Action;
    public TreeItem     Old;
    public TreeItem     New;
    public Point        At;
}

public const uint TvmInsertItemW  = 0x1132u;
public const uint TvmDeleteItem   = 0x1101u;
public const uint TvmExpand       = 0x1102u;
public const uint TvmGetItemW     = 0x113Eu;
public const uint TvmSetItemW     = 0x113Fu;
public const uint TvmGetNextItem  = 0x110Au;
public const uint TvmSelectItem   = 0x110Bu;
public const uint TvmGetCount     = 0x1105u;
public const uint TvmSetImageList = 0x1109u;
public const uint TvmEnsureVisible = 0x1114u;

public const uint TvifText          = 0x0001u;
public const uint TvifImage         = 0x0002u;
public const uint TvifParam         = 0x0004u;
public const uint TvifState         = 0x0008u;
public const uint TvifSelectedImage = 0x0020u;
public const uint TvifChildren      = 0x0040u;
public const uint TvifHandle        = 0x0010u;

public const uint TvgnRoot       = 0x0000u;
public const uint TvgnNext       = 0x0001u;
public const uint TvgnPrevious   = 0x0002u;
public const uint TvgnParent     = 0x0003u;
public const uint TvgnChild      = 0x0004u;
public const uint TvgnCaret      = 0x0009u;

public const uint TveCollapse = 0x0001u;
public const uint TveExpand   = 0x0002u;
public const uint TveToggle   = 0x0003u;

public const uint TvsHasButtons    = 0x0001u;
public const uint TvsHasLines      = 0x0002u;
public const uint TvsLinesAtRoot   = 0x0004u;
public const uint TvsEditLabels    = 0x0008u;
public const uint TvsShowSelAlways = 0x0020u;
public const uint TvsFullRowSelect = 0x1000u;

public const int TvnSelChangedW = -451;
public const int TvnItemExpandedW = -456;

/// The root of a tree, as `TVI_ROOT` spells it: not a handle at all but a
/// sentinel that happens to be shaped like one.
///
/// **These are negative numbers, and that is the whole of why they are written
/// this way.** `commctrl.h` says `((HTREEITEM)(ULONG_PTR)-0x10000)`, so on a
/// 64-bit machine `TVI_ROOT` is `0xFFFFFFFFFFFF0000` -- the sign extends
/// through the whole pointer. Writing the literal `0xFFFF0000u` instead gives
/// `0x00000000FFFF0000`, which is a different value, is not any node, and is
/// not the root either: the tree rejects every insert under it and answers
/// zero, which looks exactly like a control that quietly does nothing.
///
/// That is what these used to say, and it is why the Win32 tree never held an
/// item. `-0x10000` as a `nint` is the version that is right on both widths.
public HTREEITEM TreeRoot()  { return (HTREEITEM)(void*)(nuint)(nint)(-0x10000); }
public HTREEITEM TreeFirst() { return (HTREEITEM)(void*)(nuint)(nint)(-0xFFFF); }
public HTREEITEM TreeLast()  { return (HTREEITEM)(void*)(nuint)(nint)(-0xFFFE); }
public HTREEITEM TreeSort()  { return (HTREEITEM)(void*)(nuint)(nint)(-0xFFFD); }

// ================================================================= list view

/// `LVITEMW`.
public struct ListItem {
    public uint    Mask;
    public int     Item;
    public int     SubItem;
    public uint    State;
    public uint    StateMask;
    public char16* Text;
    public int     TextLength;
    public int     Image;
    public nuint   Param;
    public int     Indent;
    public int     GroupId;
    public uint    Columns;
    public uint*   ColumnFormat;
}

/// `LVCOLUMNW`.
public struct ListColumn {
    public uint    Mask;
    public int     Format;
    public int     Width;
    public char16* Text;
    public int     TextLength;
    public int     SubItem;
    public int     Image;
    public int     Order;
}

/// `NMLISTVIEW`.
public struct NotifyListView {
    public NotifyHeader Header;
    public int          Item;
    public int          SubItem;
    public uint         NewState;
    public uint         OldState;
    public uint         Changed;
    public Point        At;
    public nuint        Param;
}

public const uint LvmInsertItemW   = 0x104Du;   // LVM_FIRST + 77
public const uint LvmDeleteItem    = 0x1008u;
public const uint LvmDeleteAllItems = 0x1009u;
public const uint LvmSetItemW      = 0x104Cu;   // LVM_FIRST + 76
public const uint LvmGetItemW      = 0x104Bu;   // LVM_FIRST + 75
public const uint LvmGetItemCount  = 0x1004u;
public const uint LvmInsertColumnW = 0x1061u;
public const uint LvmDeleteColumn  = 0x101Cu;
public const uint LvmSetColumnWidth = 0x101Eu;
public const uint LvmGetNextItem   = 0x100Cu;
public const uint LvmSetItemState  = 0x102Bu;
public const uint LvmSetImageList  = 0x1003u;
public const uint LvmSetExtendedStyle = 0x1036u;
public const uint LvmEnsureVisible = 0x1013u;

public const uint LvifText    = 0x0001u;
public const uint LvifImage   = 0x0002u;
public const uint LvifParam   = 0x0004u;
public const uint LvifState   = 0x0008u;

public const uint LvcfFormat  = 0x0001u;
public const uint LvcfWidth   = 0x0002u;
public const uint LvcfText    = 0x0004u;
public const uint LvcfSubItem = 0x0008u;

public const int LvcfmtLeft   = 0x0000;
public const int LvcfmtRight  = 0x0001;
public const int LvcfmtCenter = 0x0002;

public const uint LvisSelected = 0x0002u;
public const uint LvisFocused  = 0x0001u;

public const uint LvniAll      = 0x0000u;
public const uint LvniSelected = 0x0002u;

public const uint LvsIcon      = 0x0000u;
public const uint LvsReport    = 0x0001u;
public const uint LvsSmallIcon = 0x0002u;
public const uint LvsList      = 0x0003u;
public const uint LvsSingleSel = 0x0004u;
public const uint LvsShowSelAlways = 0x0008u;
public const uint LvsNoSortHeader = 0x8000u;

public const uint LvsExFullRowSelect = 0x00000020u;
public const uint LvsExGridLines     = 0x00000001u;
public const uint LvsExCheckBoxes    = 0x00000004u;
public const uint LvsExDoubleBuffer  = 0x00010000u;

public const int LvnItemChanged = -101;
public const int LvnColumnClick = -108;

// =================================================================== up-down

public const uint UdmSetRange32 = 0x046Fu;
public const uint UdmGetPos32   = 0x0472u;
public const uint UdmSetPos32   = 0x0471u;
public const uint UdmSetBuddy   = 0x0469u;

public const uint UdsWrap        = 0x0001u;
public const uint UdsSetBuddyInt = 0x0002u;
public const uint UdsAlignRight  = 0x0004u;
public const uint UdsAutoBuddy   = 0x0010u;
public const uint UdsArrowKeys   = 0x0020u;

public const int UdnDeltaPos = -722;

// ================================================================== header

/// `HDITEMW`.
public struct HeaderItem {
    public uint    Mask;
    public int     Width;
    public char16* Text;
    public HBITMAP Bitmap;
    public int     TextLength;
    public int     Format;
    public nuint   Param;
    public int     Image;
    public int     Order;
    public uint    Type;
    public void*   FilterData;
    public uint    State;
}

public const uint HdmInsertItemW = 0x120Au;   // HDM_FIRST + 10
public const uint HdmDeleteItem  = 0x1202u;
public const uint HdmGetItemW    = 0x120Bu;   // HDM_FIRST + 11
public const uint HdmSetItemW    = 0x120Cu;   // HDM_FIRST + 12
public const uint HdmGetItemCount = 0x1200u;
public const uint HdmLayout      = 0x1205u;

public const uint HdiWidth  = 0x0001u;
public const uint HdiText   = 0x0002u;
public const uint HdiFormat = 0x0004u;

public const int HdfLeft   = 0x0000;
public const int HdfRight  = 0x0001;
public const int HdfCenter = 0x0002;
public const int HdfString = 0x4000;

public const uint HdsHorizontal = 0x0000u;
public const uint HdsButtons    = 0x0002u;

public const int HdnItemChangedW = -321;

// ============================================== a list box with tick boxes
//
// Windows has no such control. A list view in report mode with
// `LVS_EX_CHECKBOXES` is the one every program uses, so that is what this is --
// which is why the constants it needs are the list view's.

/// The state image, which is where a list view keeps a tick: one-based, so 1 is
/// unticked and 2 is ticked, and 0 means no state image at all.
public const uint LvisStateImageMask = 0xF000u;

public uint CheckedState(bool ticked) {
    return ((uint)(ticked ? 2 : 1)) << 12;
}

#endif
