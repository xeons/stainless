// `[DoesNotReturn]` is taken on the word of the other language, so it goes on
// an extern and nowhere else.
module Bad;

[DoesNotReturn]
void Stop()
{
}

int Main()
{
    Stop();
    return 0;
}
