// What a VaList refuses.
module ErrVaList;

int Plain(int count)
{
    VaList args = VaList.Start();                   // SLI0070: nothing to read
    return count;
}

int Reads(int count, ...)
{
    VaList args = VaList.Start(count);              // SLI0070: Start takes nothing
    VaList list = VaList.Start();
    float f = list.Next<float>();                   // SLI0070: promoted to double
    byte b = list.Next<byte>();                     // SLI0070: promoted to int
    String s = list.Next<String>();                 // SLI0070: no reference reaches '...'
    int fine = list.Next<int>();
    double also = list.Next<double>();
    int* pointer = list.Next<int*>();
    return fine;
}

int Main() => Plain(0) + Reads(1, 2);
