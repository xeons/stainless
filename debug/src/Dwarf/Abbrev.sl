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

// `.debug_abbrev`: the shape of every kind of entry a unit uses.
//
// **This is why `.debug_info` cannot be read on its own.** An entry in
// `.debug_info` is an abbreviation code and then a run of values with nothing
// between them -- no tag, no attribute numbers, no lengths. What each value
// means and how many bytes it takes comes from here, in another section
// entirely. Read the wrong abbreviation and the rest of the unit is noise that
// still parses.
//
// **A skip rule for every form, including the ones nothing reads.** That is the
// one discipline that makes this survive an LLVM upgrade: the day a new release
// starts emitting `DW_FORM_strx3` on some attribute this engine ignores, a
// reader that only knows the forms it cares about walks off the end of that
// entry and every entry after it in the unit. `SkipForm` knows all forty-odd,
// and the ones that are never seen are the important half.
module Debugger;

import Standard.Collections;
import Standard.Text;

/// One attribute of one abbreviation: what it is, how it is written, and -- for
/// `DW_FORM_implicit_const` alone -- what it is, since that form stores its
/// value here rather than in `.debug_info`.
public class AbbrevAttribute
{
    public uint At;
    public uint Form;
    public long Implicit;

    public AbbrevAttribute(uint at, uint form, long implicit)
    {
        At = at;
        Form = form;
        Implicit = implicit;
    }
}

/// One abbreviation: a tag, whether entries of this kind have children, and the
/// attributes they carry in order.
public class Abbrev
{
    public ulong Code;
    public uint Tag;
    public bool HasChildren;
    public List<AbbrevAttribute> Attributes;

    public Abbrev(ulong code, uint tag, bool children)
    {
        Code = code;
        Tag = tag;
        HasChildren = children;
        Attributes = new List<AbbrevAttribute>();
    }
}

/// Every abbreviation a unit can use, looked up by code.
///
/// Codes are assigned from one and are usually dense, so this is an array
/// indexed by code with a list beside it for the sparse case -- a table read
/// once and then hit once per entry is worth not making a dictionary of.
public class AbbrevTable
{
    List<Abbrev> _byCode;

    public AbbrevTable() => _byCode = new List<Abbrev>();

    public nuint Count => _byCode.Count;

    public Abbrev? Find(ulong code)
    {
        for (nuint i = 0u; i < _byCode.Count; i++)
        {
            if (_byCode[i].Code == code)
                return _byCode[i];
        }
        return null;
    }

    public void Add(Abbrev one) => _byCode.Add(one);

    /// Reads the table that starts at `at` in `.debug_abbrev`.
    ///
    /// Each unit names its own starting offset, and several units routinely
    /// share one table, so this is read per unit and not per section.
    public static AbbrevTable Read(byte[] section, nuint at)
    {
        var made = new AbbrevTable();
        if (at >= section.Length)
            return made;

        var reader = new Cursor(section, at);
        while (!reader.AtEnd && !reader.Overran)
        {
            ulong code = reader.Leb();
            if (code == 0u)
                break;                      // the table ends with a zero code

            uint tag = (uint)reader.Leb();
            bool children = reader.U8() != 0;
            var one = new Abbrev(code, tag, children);

            // Attribute/form pairs until a pair of zeros.
            while (!reader.Overran)
            {
                uint at2 = (uint)reader.Leb();
                uint form = (uint)reader.Leb();

                // The value of an implicit constant lives here, not in
                // `.debug_info`, which is the whole point of the form: an
                // attribute that is the same on every entry costs nothing per
                // entry.
                long implicit = 0;
                if (form == FormImplicitConst)
                    implicit = reader.SLeb();

                if (at2 == 0u && form == 0u)
                    break;
                one.Attributes.Add(new AbbrevAttribute(at2, form, implicit));
            }

            made.Add(one);
        }
        return made;
    }
}

/// Every form this engine has a name for.
///
/// Exists for one test: that nothing can be *named* without being *skippable*.
/// Adding a constant to `Constants.sl` and forgetting the case in `SkipForm`
/// is the exact mistake that loses a unit silently, and it is the kind of
/// mistake a list cannot make on its own -- so the list is checked against the
/// function rather than trusted alongside it.
public uint[] KnownForms()
{
    return [FormAddr, FormBlock2, FormBlock4, FormData2, FormData4, FormData8,
            FormString, FormBlock, FormBlock1, FormData1, FormFlag, FormSdata,
            FormStrp, FormUdata, FormRefAddr, FormRef1, FormRef2, FormRef4,
            FormRef8, FormRefUdata, FormIndirect, FormSecOffset, FormExprloc,
            FormFlagPresent, FormStrx, FormAddrx, FormRefSup4, FormStrpSup,
            FormData16, FormLineStrp, FormRefSig8, FormImplicitConst,
            FormLoclistx, FormRnglistx, FormRefSup8, FormStrx1, FormStrx2,
            FormStrx3, FormStrx4, FormAddrx1, FormAddrx2, FormAddrx3,
            FormAddrx4];
}

/// How many bytes a form occupies, moving the cursor past it.
///
/// **Every form, not only the ones read.** A reader that meets an unknown form
/// has no way to find the next attribute, so it loses the entry, and because an
/// entry carries no length it loses every entry after it in the unit as well --
/// while still producing entries that look plausible. That failure is silent,
/// which is why this function is exhaustive and why the ones nothing here reads
/// are worth as much as the ones it does.
///
/// Answers false for a form it genuinely does not know, so a caller can stop
/// rather than guess. That is the only honest thing to do: the alternative is
/// to skip nothing and carry on reading rubbish.
public bool SkipForm(Cursor reader, uint form, nuint addressSize, nuint offsetSize)
{
    // Fixed widths.
    if (form == FormFlagPresent || form == FormImplicitConst)
        return true;                                  // no bytes at all

    if (form == FormData1 || form == FormRef1 || form == FormFlag
        || form == FormStrx1 || form == FormAddrx1 || form == FormBlock1)
    {
        // The block forms carry a length and then that many bytes; the others
        // are one byte and done.
        if (form == FormBlock1)
        {
            nuint size = (nuint)reader.U8();
            reader.Skip(size);
            return true;
        }
        reader.Skip(1u);
        return true;
    }

    if (form == FormData2 || form == FormRef2 || form == FormStrx2
        || form == FormAddrx2)
    {
        reader.Skip(2u);
        return true;
    }

    if (form == FormStrx3 || form == FormAddrx3)
    {
        reader.Skip(3u);
        return true;
    }

    if (form == FormData4 || form == FormRef4 || form == FormStrx4
        || form == FormAddrx4 || form == FormRefSup4)
    {
        reader.Skip(4u);
        return true;
    }

    if (form == FormData8 || form == FormRef8 || form == FormRefSig8
        || form == FormRefSup8)
    {
        reader.Skip(8u);
        return true;
    }

    if (form == FormData16)
    {
        reader.Skip(16u);
        return true;
    }

    // Widths that follow the unit.
    if (form == FormAddr)
    {
        reader.Skip(addressSize);
        return true;
    }

    if (form == FormStrp || form == FormLineStrp || form == FormSecOffset
        || form == FormRefAddr || form == FormStrpSup)
    {
        reader.Skip(offsetSize);
        return true;
    }

    // Variable lengths.
    if (form == FormSdata)
    {
        reader.SLeb();
        return true;
    }

    if (form == FormUdata || form == FormRefUdata || form == FormStrx
        || form == FormAddrx || form == FormLoclistx || form == FormRnglistx)
    {
        reader.Leb();
        return true;
    }

    if (form == FormString)
    {
        reader.CString();
        return true;
    }

    if (form == FormBlock2)
    {
        nuint size = (nuint)reader.U16();
        reader.Skip(size);
        return true;
    }

    if (form == FormBlock4)
    {
        nuint size = (nuint)reader.U32();
        reader.Skip(size);
        return true;
    }

    if (form == FormBlock || form == FormExprloc)
    {
        nuint size = (nuint)reader.Leb();
        reader.Skip(size);
        return true;
    }

    // **`DW_FORM_indirect` names its real form in the data**, which is the one
    // case where the abbreviation does not settle the shape. Rare, and the
    // reason this is a loop-free recursion of exactly one step.
    if (form == FormIndirect)
    {
        uint real = (uint)reader.Leb();
        if (real == FormIndirect)
            return false;                 // an indirect indirect is nonsense
        return SkipForm(reader, real, addressSize, offsetSize);
    }

    return false;
}
