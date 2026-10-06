#include <stdexcept>

extern "C" int SLCppHalve(int number)
{
    if (number % 2 != 0)
        throw std::runtime_error("odd");
    return number / 2;
}

extern "C" void SLCppCheck(int number)
{
    if (number < 0)
        throw 42;
}
