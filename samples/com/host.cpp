// SPDX-License-Identifier: 0BSD
//
// A C++ application that loads the Stainless COM server and uses it.
//
// It does what COM's own activation does, in the order COM does it: find the
// module, ask it for a class object, ask that for an instance, and hold the
// instance through an interface pointer. The only step skipped is the registry
// lookup that turns a CLSID into a path -- so this needs no admin rights and
// no regsvr32, and every line after LoadLibrary is ordinary COM.
//
// Build and run it with build.cmd (Windows) or build.sh (elsewhere).

#include "greeter.h"

#include <cstdio>

#ifdef _WIN32
#  include <windows.h>
   typedef HMODULE Module;
   static Module LoadServer(const char *path)   { return LoadLibraryA(path); }
   static void  *Entry(Module m, const char *n) { return (void *)GetProcAddress(m, n); }
#else
#  include <dlfcn.h>
   typedef void *Module;
   static Module LoadServer(const char *path)   { return dlopen(path, RTLD_NOW); }
   static void  *Entry(Module m, const char *n) { return dlsym(m, n); }
#endif

static int Failed(const char *what, HRESULT hr)
{
    std::printf("[host]      %s failed, hr = 0x%08x\n", what, (unsigned)hr);
    return 1;
}

int main(int argc, char **argv)
{
    // The server has its own stdout buffer -- it is a separate module with its
    // own C runtime state -- and it flushes each line. Matching that here is
    // what makes the interleaving below mean something: every line appears in
    // the order the two of them actually reached it.
    std::setvbuf(stdout, nullptr, _IONBF, 0);

    const char *path = argc > 1 ? argv[1] :
#ifdef _WIN32
        "build\\greeter.dll";
#else
        "./build/libgreeter.so";
#endif

#ifdef _WIN32
    // A real apartment, because this is a real COM object. Free-threaded: the
    // server does no marshalling and says so.
    HRESULT init = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (FAILED(init)) return Failed("CoInitializeEx", init);
#endif

    std::printf("[host]      loading %s\n", path);
    Module server = LoadServer(path);
    if (server == nullptr) {
        std::printf("[host]      could not load the server\n");
        return 1;
    }

    DllGetClassObjectFn getClassObject =
        (DllGetClassObjectFn)Entry(server, "DllGetClassObject");
    DllCanUnloadNowFn canUnloadNow =
        (DllCanUnloadNowFn)Entry(server, "DllCanUnloadNow");

    if (getClassObject == nullptr) {
        std::printf("[host]      the module exports no DllGetClassObject\n");
        return 1;
    }

    // --- activation ------------------------------------------------------
    //
    // Exactly what CoCreateInstance does internally, with the registry lookup
    // replaced by the path above.
    IClassFactory *factory = nullptr;
    HRESULT hr = getClassObject(CLSID_Greeter, IID_IClassFactory, (void **)&factory);
    if (FAILED(hr)) return Failed("DllGetClassObject", hr);
    std::printf("[host]      got the class factory\n");

    IGreeter *greeter = nullptr;
    hr = factory->CreateInstance(nullptr, IID_IGreeter, (void **)&greeter);
    factory->Release();
    if (FAILED(hr)) return Failed("CreateInstance", hr);
    std::printf("[host]      created a Greeter, factory released\n");

    // --- using it --------------------------------------------------------
    int32_t total = 0;

    hr = greeter->Greet(3, &total);
    if (FAILED(hr)) return Failed("Greet", hr);
    std::printf("[host]      Greet(3)  -> %d\n", total);

    hr = greeter->Greet(4, &total);
    if (FAILED(hr)) return Failed("Greet", hr);
    std::printf("[host]      Greet(4)  -> %d\n", total);

    hr = greeter->Total(&total);
    if (FAILED(hr)) return Failed("Total", hr);
    std::printf("[host]      Total()   -> %d\n", total);

    // --- QueryInterface --------------------------------------------------
    //
    // A second interface on the one object. The pointer differs from the
    // IGreeter one -- each interface has its own tear-off, so each has its own
    // address -- while IUnknown must come back identical through either, which
    // is how COM says "the same object".
    ICounter *counter = nullptr;
    hr = greeter->QueryInterface(IID_ICounter, (void **)&counter);
    if (FAILED(hr)) return Failed("QueryInterface(ICounter)", hr);
    std::printf("[host]      QueryInterface(ICounter) ok, %s pointer\n",
                (void *)counter == (void *)greeter ? "the same" : "a different");

    IUnknown *fromGreeter = nullptr;
    IUnknown *fromCounter = nullptr;
    greeter->QueryInterface(IID_IUnknown, (void **)&fromGreeter);
    counter->QueryInterface(IID_IUnknown, (void **)&fromCounter);
    std::printf("[host]      IUnknown identity holds: %s\n",
                fromGreeter == fromCounter ? "yes" : "no");
    if (fromGreeter != nullptr) fromGreeter->Release();
    if (fromCounter != nullptr) fromCounter->Release();

    hr = counter->Reset();
    if (FAILED(hr)) return Failed("Reset", hr);
    counter->Release();

    hr = greeter->Total(&total);
    if (FAILED(hr)) return Failed("Total", hr);
    std::printf("[host]      Total() after Reset -> %d\n", total);

    // --- letting go ------------------------------------------------------
    //
    // The last Release runs the Stainless destructor, from C++, through a
    // vtable slot the compiler emitted. Its line arrives before the next one
    // here, which is what says the object really died at this call.
    std::printf("[host]      releasing the Greeter\n");
    greeter->Release();
    std::printf("[host]      released\n");

    if (canUnloadNow != nullptr)
        std::printf("[host]      DllCanUnloadNow -> %s\n",
                    canUnloadNow() == S_OK ? "S_OK" : "S_FALSE (declines)");

#ifdef _WIN32
    CoUninitialize();
#endif
    return 0;
}
