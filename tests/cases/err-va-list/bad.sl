// What a VaList refuses.
module ErrVaList;

int Plain(int count)
{
    VaList args = VaList.Start();                   // SL0935: nothing to read
    return count;
}

int Reads(int count, ...)
{
    VaList args = VaList.Start(count);              // SL0935: Start takes nothing
    VaList list = VaList.Start();
    float f = list.Next<float>();                   // SL0935: promoted to double
    byte b = list.Next<byte>();                     // SL0935: promoted to int
    String s = list.Next<String>();                 // SL0935: no reference reaches '...'
    int fine = list.Next<int>();
    double also = list.Next<double>();
    int* pointer = list.Next<int*>();
    return fine;
}

int Main() => Plain(0) + Reads(1, 2);
