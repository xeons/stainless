// SPDX-License-Identifier: 0BSD
//
// A 'where' clause with no type parameter to constrain. The parser refuses it,
// so it has a case of its own rather than masking the binder's.
module Bad;

public interface INamed
{
    String Name();
}

int NotGeneric(int v) where T : INamed => v;                     // SLG0009

public class Holder where T : INamed { }                         // SLG0009

int Main() => 0;
