// The System V AMD64 struct classifier, against the shapes it exists for.
//
// A value of sixteen bytes or less is cut into eightbytes and each is passed in
// an integer register or an SSE one, decided by what lies in it -- so
// `{ double; int; }` uses one of each while `{ float; int; }` uses one integer
// register, and nothing about either follows from their sizes.
//
// Two things are checked here, and they are different things.
//
// The output checks that the halves of a call agree: every struct below is
// built, passed by value, taken apart on the other side and added up. If the
// pieces were split or reassembled wrongly the numbers come out wrong, whatever
// ABI is in force.
//
// ir.txt checks that they agree with *C*, which running the program cannot
// show. Every signature in it was read out of clang built for
// x86_64-pc-linux-gnu, and being one register out is a program that links and
// then reads an argument nobody passed.
//
// It runs on Windows because classification and register assignment are
// different jobs. This decides how a struct is broken up; LLVM's own lowering
// decides which registers the pieces land in, so the two halves stay in step
// with each other on any host.
module SysVAbi;

import Standard.Console;
import Standard.Text;

public struct I3 { public sbyte A; public sbyte B; public sbyte C; }
public struct I5 { public int A; public sbyte B; }
public struct I9 { public long A; public sbyte B; }
public struct I12 { public int A; public int B; public int C; }
public struct I16 { public long A; public long B; }
public struct I17 { public long A; public long B; public sbyte C; }
public struct F2 { public float A; public float B; }
public struct F3 { public float A; public float B; public float C; }
public struct D2 { public double A; public double B; }
public struct D3 { public double A; public double B; public double C; }
public struct M1 { public double A; public int B; }
public struct M2 { public int A; public double B; }
public struct M3 { public float A; public int B; }
public struct M7 { public sbyte A; public double B; }
public struct M8 { public float A; public long B; }
public struct A3 { public int[3] A; }
public struct A5 { public sbyte[17] A; }

// Taking one apart: every field read back out of what arrived.
double TakeI3(I3 v) { return (double)v.A + (double)v.B + (double)v.C; }
double TakeI5(I5 v) { return (double)v.A + (double)v.B; }
double TakeI9(I9 v) { return (double)v.A + (double)v.B; }
double TakeI12(I12 v) { return (double)v.A + (double)v.B + (double)v.C; }
double TakeI16(I16 v) { return (double)v.A + (double)v.B; }
double TakeI17(I17 v) { return (double)v.A + (double)v.B + (double)v.C; }
double TakeF2(F2 v) { return (double)v.A + (double)v.B; }
double TakeF3(F3 v) { return (double)v.A + (double)v.B + (double)v.C; }
double TakeD2(D2 v) { return (double)v.A + (double)v.B; }
double TakeD3(D3 v) { return (double)v.A + (double)v.B + (double)v.C; }
double TakeM1(M1 v) { return (double)v.A + (double)v.B; }
double TakeM2(M2 v) { return (double)v.A + (double)v.B; }
double TakeM3(M3 v) { return (double)v.A + (double)v.B; }
double TakeM7(M7 v) { return (double)v.A + (double)v.B; }
double TakeM8(M8 v) { return (double)v.A + (double)v.B; }
double TakeA3(A3 v) { return (double)v.A[0] + (double)v.A[1] + (double)v.A[2]; }
double TakeA5(A5 v) { return (double)v.A[0] + (double)v.A[16]; }

// And building one, so the return side is exercised too.
I3 GiveI3() {
    I3 v;
    v.A = 1;
    v.B = 2;
    v.C = 3;
    return v;
}
I5 GiveI5() {
    I5 v;
    v.A = 11;
    v.B = 4;
    return v;
}
I9 GiveI9() {
    I9 v;
    v.A = 12;
    v.B = 5;
    return v;
}
I12 GiveI12() {
    I12 v;
    v.A = 13;
    v.B = 14;
    v.C = 15;
    return v;
}
I16 GiveI16() {
    I16 v;
    v.A = 16;
    v.B = 17;
    return v;
}
I17 GiveI17() {
    I17 v;
    v.A = 18;
    v.B = 19;
    v.C = 6;
    return v;
}
F2 GiveF2() {
    F2 v;
    v.A = (float)1.5;
    v.B = (float)2.5;
    return v;
}
F3 GiveF3() {
    F3 v;
    v.A = (float)3.5;
    v.B = (float)4.5;
    v.C = (float)5.5;
    return v;
}
D2 GiveD2() {
    D2 v;
    v.A = 6.5;
    v.B = 7.5;
    return v;
}
D3 GiveD3() {
    D3 v;
    v.A = 8.5;
    v.B = 9.5;
    v.C = 10.5;
    return v;
}
M1 GiveM1() {
    M1 v;
    v.A = 11.5;
    v.B = 20;
    return v;
}
M2 GiveM2() {
    M2 v;
    v.A = 21;
    v.B = 12.5;
    return v;
}
M3 GiveM3() {
    M3 v;
    v.A = (float)13.5;
    v.B = 22;
    return v;
}
M7 GiveM7() {
    M7 v;
    v.A = 7;
    v.B = 14.5;
    return v;
}
M8 GiveM8() {
    M8 v;
    v.A = (float)15.5;
    v.B = 23;
    return v;
}
A3 GiveA3() {
    A3 v;
    v.A[0] = 24; v.A[1] = 25; v.A[2] = 26;
    return v;
}
A5 GiveA5() {
    A5 v;
    v.A[0] = 8; v.A[16] = 9;
    return v;
}

public void Main() {
    var line = new StringBuilder();
    line.Clear();
    line.Append("I3  ");
    line.AppendDouble(TakeI3(GiveI3()));
    Console.WriteLine(line.ToText());
    line.Clear();
    line.Append("I5  ");
    line.AppendDouble(TakeI5(GiveI5()));
    Console.WriteLine(line.ToText());
    line.Clear();
    line.Append("I9  ");
    line.AppendDouble(TakeI9(GiveI9()));
    Console.WriteLine(line.ToText());
    line.Clear();
    line.Append("I12 ");
    line.AppendDouble(TakeI12(GiveI12()));
    Console.WriteLine(line.ToText());
    line.Clear();
    line.Append("I16 ");
    line.AppendDouble(TakeI16(GiveI16()));
    Console.WriteLine(line.ToText());
    line.Clear();
    line.Append("I17 ");
    line.AppendDouble(TakeI17(GiveI17()));
    Console.WriteLine(line.ToText());
    line.Clear();
    line.Append("F2  ");
    line.AppendDouble(TakeF2(GiveF2()));
    Console.WriteLine(line.ToText());
    line.Clear();
    line.Append("F3  ");
    line.AppendDouble(TakeF3(GiveF3()));
    Console.WriteLine(line.ToText());
    line.Clear();
    line.Append("D2  ");
    line.AppendDouble(TakeD2(GiveD2()));
    Console.WriteLine(line.ToText());
    line.Clear();
    line.Append("D3  ");
    line.AppendDouble(TakeD3(GiveD3()));
    Console.WriteLine(line.ToText());
    line.Clear();
    line.Append("M1  ");
    line.AppendDouble(TakeM1(GiveM1()));
    Console.WriteLine(line.ToText());
    line.Clear();
    line.Append("M2  ");
    line.AppendDouble(TakeM2(GiveM2()));
    Console.WriteLine(line.ToText());
    line.Clear();
    line.Append("M3  ");
    line.AppendDouble(TakeM3(GiveM3()));
    Console.WriteLine(line.ToText());
    line.Clear();
    line.Append("M7  ");
    line.AppendDouble(TakeM7(GiveM7()));
    Console.WriteLine(line.ToText());
    line.Clear();
    line.Append("M8  ");
    line.AppendDouble(TakeM8(GiveM8()));
    Console.WriteLine(line.ToText());
    line.Clear();
    line.Append("A3  ");
    line.AppendDouble(TakeA3(GiveA3()));
    Console.WriteLine(line.ToText());
    line.Clear();
    line.Append("A5  ");
    line.AppendDouble(TakeA5(GiveA5()));
    Console.WriteLine(line.ToText());
}
