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

// The numbers DWARF is written in, and names for the ones worth printing.
//
// **The names are here so that this reader can be checked against
// `llvm-dwarfdump`.** A tag printed as `0x2e` can only be compared against
// another number by a person counting; printed as `DW_TAG_subprogram` it can be
// diffed against the tool's own output, which is how every claim about this
// reader was settled. They cost a few hundred bytes of string and they are the
// difference between a reader that is believed and one that is verified.
//
// Only the constants this engine actually names are given names. An unknown tag
// prints as its number rather than being refused -- DWARF is extensible, vendors
// add their own, and a debugger that stops at one it has never seen is a
// debugger that stops on somebody else's compiler.
module Debugger;

import Standard.Collections;
import Standard.Text;

// ------------------------------------------------------------------- tags

public const uint TagArrayType        = 0x01u;
public const uint TagClassType        = 0x02u;
public const uint TagEnumerationType  = 0x04u;
public const uint TagFormalParameter  = 0x05u;
public const uint TagLexicalBlock     = 0x0Bu;
public const uint TagMember           = 0x0Du;
public const uint TagPointerType      = 0x0Fu;
public const uint TagReferenceType    = 0x10u;
public const uint TagCompileUnit      = 0x11u;
public const uint TagStructureType    = 0x13u;
public const uint TagSubroutineType   = 0x15u;
public const uint TagTypedef          = 0x16u;
public const uint TagUnionType        = 0x17u;
public const uint TagInheritance      = 0x1Cu;
public const uint TagSubrangeType     = 0x21u;
public const uint TagBaseType         = 0x24u;
public const uint TagConstType        = 0x26u;
public const uint TagEnumerator       = 0x28u;
public const uint TagSubprogram       = 0x2Eu;
public const uint TagVariable         = 0x34u;
public const uint TagVolatileType     = 0x35u;

// ------------------------------------------------------------- attributes

public const uint AtLocation        = 0x02u;
public const uint AtName            = 0x03u;
public const uint AtByteSize        = 0x0Bu;
public const uint AtStmtList        = 0x10u;
public const uint AtLowPc           = 0x11u;
public const uint AtHighPc          = 0x12u;
public const uint AtLanguage        = 0x13u;
public const uint AtCompDir         = 0x1Bu;
public const uint AtConstValue      = 0x1Cu;
public const uint AtUpperBound      = 0x2Fu;
public const uint AtProducer        = 0x25u;
public const uint AtAbstractOrigin  = 0x31u;
public const uint AtCount           = 0x37u;
public const uint AtDataMemberLoc   = 0x38u;
public const uint AtDeclFile        = 0x3Au;
public const uint AtDeclLine        = 0x3Bu;
public const uint AtDeclaration     = 0x3Cu;
public const uint AtEncoding        = 0x3Eu;
public const uint AtExternal        = 0x3Fu;
public const uint AtFrameBase       = 0x40u;
public const uint AtSpecification   = 0x47u;
public const uint AtType            = 0x49u;
public const uint AtRanges          = 0x55u;
public const uint AtLinkageName     = 0x6Eu;
public const uint AtStrOffsetsBase  = 0x72u;
public const uint AtAddrBase        = 0x73u;
public const uint AtRnglistsBase    = 0x74u;
public const uint AtLoclistsBase    = 0x8Cu;

// ------------------------------------------------------------------ forms

public const uint FormAddr          = 0x01u;
public const uint FormBlock2        = 0x03u;
public const uint FormBlock4        = 0x04u;
public const uint FormData2         = 0x05u;
public const uint FormData4         = 0x06u;
public const uint FormData8         = 0x07u;
public const uint FormString        = 0x08u;
public const uint FormBlock         = 0x09u;
public const uint FormBlock1        = 0x0Au;
public const uint FormData1         = 0x0Bu;
public const uint FormFlag          = 0x0Cu;
public const uint FormSdata         = 0x0Du;
public const uint FormStrp          = 0x0Eu;
public const uint FormUdata         = 0x0Fu;
public const uint FormRefAddr       = 0x10u;
public const uint FormRef1          = 0x11u;
public const uint FormRef2          = 0x12u;
public const uint FormRef4          = 0x13u;
public const uint FormRef8          = 0x14u;
public const uint FormRefUdata      = 0x15u;
public const uint FormIndirect      = 0x16u;
public const uint FormSecOffset     = 0x17u;
public const uint FormExprloc       = 0x18u;
public const uint FormFlagPresent   = 0x19u;
public const uint FormStrx          = 0x1Au;
public const uint FormAddrx         = 0x1Bu;
public const uint FormRefSup4       = 0x1Cu;
public const uint FormStrpSup       = 0x1Du;
public const uint FormData16        = 0x1Eu;
public const uint FormLineStrp      = 0x1Fu;
public const uint FormRefSig8       = 0x20u;
public const uint FormImplicitConst = 0x21u;
public const uint FormLoclistx      = 0x22u;
public const uint FormRnglistx      = 0x23u;
public const uint FormRefSup8       = 0x24u;
public const uint FormStrx1         = 0x25u;
public const uint FormStrx2         = 0x26u;
public const uint FormStrx3         = 0x27u;
public const uint FormStrx4         = 0x28u;
public const uint FormAddrx1        = 0x29u;
public const uint FormAddrx2        = 0x2Au;
public const uint FormAddrx3        = 0x2Bu;
public const uint FormAddrx4        = 0x2Cu;

// ------------------------------------------------------------------ names

/// What a tag is called, or its number in hexadecimal when this reader has no
/// name for it.
public String TagName(uint tag)
{
    switch (tag)
    {
        case TagArrayType: return "DW_TAG_array_type";
        case TagClassType: return "DW_TAG_class_type";
        case TagEnumerationType: return "DW_TAG_enumeration_type";
        case TagFormalParameter: return "DW_TAG_formal_parameter";
        case TagLexicalBlock: return "DW_TAG_lexical_block";
        case TagMember: return "DW_TAG_member";
        case TagPointerType: return "DW_TAG_pointer_type";
        case TagReferenceType: return "DW_TAG_reference_type";
        case TagCompileUnit: return "DW_TAG_compile_unit";
        case TagStructureType: return "DW_TAG_structure_type";
        case TagSubroutineType: return "DW_TAG_subroutine_type";
        case TagTypedef: return "DW_TAG_typedef";
        case TagUnionType: return "DW_TAG_union_type";
        case TagInheritance: return "DW_TAG_inheritance";
        case TagSubrangeType: return "DW_TAG_subrange_type";
        case TagBaseType: return "DW_TAG_base_type";
        case TagConstType: return "DW_TAG_const_type";
        case TagEnumerator: return "DW_TAG_enumerator";
        case TagSubprogram: return "DW_TAG_subprogram";
        case TagVariable: return "DW_TAG_variable";
        case TagVolatileType: return "DW_TAG_volatile_type";
        default: return "DW_TAG_?(0x" + FormatHexadecimal((ulong)tag) + ")";
    }
}

public String AttributeName(uint at)
{
    switch (at)
    {
        case AtLocation: return "DW_AT_location";
        case AtName: return "DW_AT_name";
        case AtByteSize: return "DW_AT_byte_size";
        case AtStmtList: return "DW_AT_stmt_list";
        case AtLowPc: return "DW_AT_low_pc";
        case AtHighPc: return "DW_AT_high_pc";
        case AtLanguage: return "DW_AT_language";
        case AtCompDir: return "DW_AT_comp_dir";
        case AtConstValue: return "DW_AT_const_value";
        case AtUpperBound: return "DW_AT_upper_bound";
        case AtProducer: return "DW_AT_producer";
        case AtAbstractOrigin: return "DW_AT_abstract_origin";
        case AtCount: return "DW_AT_count";
        case AtDataMemberLoc: return "DW_AT_data_member_location";
        case AtDeclFile: return "DW_AT_decl_file";
        case AtDeclLine: return "DW_AT_decl_line";
        case AtDeclaration: return "DW_AT_declaration";
        case AtEncoding: return "DW_AT_encoding";
        case AtExternal: return "DW_AT_external";
        case AtFrameBase: return "DW_AT_frame_base";
        case AtSpecification: return "DW_AT_specification";
        case AtType: return "DW_AT_type";
        case AtRanges: return "DW_AT_ranges";
        case AtLinkageName: return "DW_AT_linkage_name";
        case AtStrOffsetsBase: return "DW_AT_str_offsets_base";
        case AtAddrBase: return "DW_AT_addr_base";
        case AtRnglistsBase: return "DW_AT_rnglists_base";
        case AtLoclistsBase: return "DW_AT_loclists_base";
        default: return "DW_AT_?(0x" + FormatHexadecimal((ulong)at) + ")";
    }
}

/// Lower-case hexadecimal with no padding, which is how DWARF numbers are
/// written everywhere a person reads them.
public String FormatHexadecimal(ulong value)
{
    if (value == 0u)
        return "0";

    byte[] digits = new byte[16];
    nuint count = 0u;
    while (value != 0u && count < 16u)
    {
        nuint nibble = (nuint)(value & 0xFu);
        digits[count] = nibble < 10u
                      ? (byte)((nuint)48 + nibble)
                      : (byte)((nuint)97 + nibble - 10u);
        count++;
        value = value >> 4;
    }

    var made = new StringBuilder();
    for (nuint i = count; i > 0u; i--)
        made.AppendByte(digits[i - 1u]);
    return made.ToText();
}
