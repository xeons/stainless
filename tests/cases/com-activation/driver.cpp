// SPDX-License-Identifier: 0BSD
//
// The half that asks. Plain C++ with hand-written COM declarations -- the same
// ones a consumer writes from an .idl -- so what is checked is that the vtable
// the compiler emitted is the one C++ expects, slot for slot.

#include <cstdint>
#include <cstdio>
#include <cstring>

namespace {

typedef int32_t HRESULT;

const HRESULT S_OK = 0;
const HRESULT S_FALSE = 1;
const HRESULT CLASS_E_CLASSNOTAVAILABLE = static_cast<HRESULT>(0x80040111);

struct Guid {
    uint32_t data1;
    uint16_t data2;
    uint16_t data3;
    uint8_t  data4[8];
};

// No __stdcall off x86; on x86 a COM slot has it, which is what SL_COM_METHOD
// resolves to on the Stainless side and what this has to match.
#if defined(__i386__) || defined(_M_IX86)
#  define COM_CALL __stdcall
#else
#  define COM_CALL
#endif

struct IUnknown {
    virtual HRESULT COM_CALL QueryInterface(const Guid *iid, void **result) = 0;
    virtual uint32_t COM_CALL AddRef() = 0;
    virtual uint32_t COM_CALL Release() = 0;
};

struct IClassFactory : IUnknown {
    virtual HRESULT COM_CALL CreateInstance(
        IUnknown *outer, const Guid *iid, void **result) = 0;
    virtual HRESULT COM_CALL LockServer(int32_t lock) = 0;
};

struct IGreeter : IUnknown {
    virtual HRESULT COM_CALL Greet(int32_t times, int32_t *total) = 0;
    virtual HRESULT COM_CALL Total(int32_t *total) = 0;
};

struct ICounter : IUnknown {
    virtual HRESULT COM_CALL Reset() = 0;
};

const Guid IID_IUnknown =
    { 0x00000000, 0x0000, 0x0000, { 0xC0, 0, 0, 0, 0, 0, 0, 0x46 } };
const Guid IID_IClassFactory =
    { 0x00000001, 0x0000, 0x0000, { 0xC0, 0, 0, 0, 0, 0, 0, 0x46 } };

const Guid IID_IGreeter =
    { 0x9d2f5f7a, 0x1c64, 0x4a3b, { 0x8f, 0x0e, 0x7d, 0x5a, 0x2c, 0x9b, 0x4e, 0x10 } };
const Guid IID_ICounter =
    { 0xb71e0c48, 0x3a95, 0x4f2d, { 0x9c, 0x11, 0x6e, 0x8a, 0x0d, 0x3f, 0x5b, 0x27 } };
const Guid CLSID_Greeter =
    { 0x5a1c8e30, 0x2b47, 0x4d16, { 0xa9, 0xf3, 0xc0, 0x4e, 0x7b, 0x81, 0xd6, 0x29 } };

// A CLSID nothing in the program carries.
const Guid CLSID_Missing =
    { 0xdeadbeef, 0x0000, 0x0000, { 0, 0, 0, 0, 0, 0, 0, 1 } };

int failures = 0;

void Check(const char *what, bool ok)
{
    std::printf("%-34s %s\n", what, ok ? "ok" : "FAILED");
    if (!ok) failures++;
}

} // namespace

extern "C" HRESULT DllGetClassObject(const Guid *clsid, const Guid *iid, void **result);

int DriveActivation()
{
    // --- a CLSID nothing answers to ------------------------------------
    void *nothing = reinterpret_cast<void *>(static_cast<intptr_t>(-1));
    HRESULT hr = DllGetClassObject(&CLSID_Missing, &IID_IClassFactory, &nothing);
    Check("unknown clsid refused", hr == CLASS_E_CLASSNOTAVAILABLE);
    Check("unknown clsid clears result", nothing == nullptr);

    // --- the class object ----------------------------------------------
    IClassFactory *factory = nullptr;
    hr = DllGetClassObject(&CLSID_Greeter, &IID_IClassFactory,
                           reinterpret_cast<void **>(&factory));
    Check("got a class factory", hr == S_OK && factory != nullptr);
    if (factory == nullptr) return failures;

    // A factory is an IUnknown too, and asking it for something it is not
    // has to fail rather than hand back the factory.
    void *wrong = nullptr;
    Check("factory refuses IGreeter",
          factory->QueryInterface(&IID_IGreeter, &wrong) != S_OK && wrong == nullptr);

    // --- an instance -----------------------------------------------------
    IGreeter *greeter = nullptr;
    hr = factory->CreateInstance(nullptr, &IID_IGreeter,
                                 reinterpret_cast<void **>(&greeter));
    Check("created an instance", hr == S_OK && greeter != nullptr);

    // Aggregation is refused rather than half-supported.
    void *aggregated = nullptr;
    Check("aggregation refused",
          factory->CreateInstance(factory, &IID_IGreeter, &aggregated) != S_OK);

    // Asking the factory for an interface the class does not present.
    void *absent = nullptr;
    const Guid IID_Absent =
        { 0x11111111, 0x2222, 0x3333, { 4, 5, 6, 7, 8, 9, 10, 11 } };
    Check("unpresented interface refused",
          factory->CreateInstance(nullptr, &IID_Absent, &absent) != S_OK &&
          absent == nullptr);

    Check("LockServer accepted", factory->LockServer(1) == S_OK);
    factory->Release();
    if (greeter == nullptr) return failures;

    // --- using the object ------------------------------------------------
    int32_t total = -1;
    Check("Greet(3)", greeter->Greet(3, &total) == S_OK && total == 3);
    Check("Greet(4) accumulates", greeter->Greet(4, &total) == S_OK && total == 7);
    Check("Total()", greeter->Total(&total) == S_OK && total == 7);

    // --- QueryInterface --------------------------------------------------
    ICounter *counter = nullptr;
    hr = greeter->QueryInterface(&IID_ICounter, reinterpret_cast<void **>(&counter));
    Check("QueryInterface(ICounter)", hr == S_OK && counter != nullptr);
    Check("a second interface is a second address",
          static_cast<void *>(counter) != static_cast<void *>(greeter));

    IUnknown *viaGreeter = nullptr;
    IUnknown *viaCounter = nullptr;
    greeter->QueryInterface(&IID_IUnknown, reinterpret_cast<void **>(&viaGreeter));
    counter->QueryInterface(&IID_IUnknown, reinterpret_cast<void **>(&viaCounter));
    Check("IUnknown is the same pointer either way", viaGreeter == viaCounter);
    if (viaGreeter != nullptr) viaGreeter->Release();
    if (viaCounter != nullptr) viaCounter->Release();

    Check("Reset", counter->Reset() == S_OK);
    counter->Release();
    Check("Total() after Reset", greeter->Total(&total) == S_OK && total == 0);

    // --- letting go ------------------------------------------------------
    //
    // The destructor's line lands between these two, which is what says the
    // object died at this Release and not at some later tidy-up.
    std::printf("releasing\n");
    greeter->Release();
    std::printf("released\n");

    return failures;
}
