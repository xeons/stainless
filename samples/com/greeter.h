/* SPDX-License-Identifier: 0BSD
 *
 * The C++ side's view of the Stainless COM server.
 *
 * Nothing generated this. It is what a COM consumer writes by hand, or what
 * MIDL would write from an .idl: the same vtable layout, the same IIDs, the
 * same CLSID. That it matches is the point of the sample -- a `com interface`
 * is a vtable and a `[Guid]` is sixteen bytes, on both sides.
 *
 * On Windows this builds on the real <unknwn.h>, so IGreeter below is a
 * genuine IUnknown to the COM runtime. Elsewhere there is no COM runtime, and
 * the handful of declarations under #else are enough -- which is the claim
 * that COM is a calling convention rather than a Windows service, made
 * checkable.
 */

#ifndef GREETER_H
#define GREETER_H

#include <cstdint>

#ifdef _WIN32

#include <unknwn.h>

#else /* not Windows: the little of COM that a caller needs */

#include <cstring>

typedef int32_t HRESULT;
typedef uint32_t ULONG;

#define S_OK           ((HRESULT)0)
#define S_FALSE        ((HRESULT)1)
#define E_NOINTERFACE  ((HRESULT)0x80004002)
#define E_POINTER      ((HRESULT)0x80004003)
#define CLASS_E_CLASSNOTAVAILABLE ((HRESULT)0x80040111)
#define SUCCEEDED(hr)  ((HRESULT)(hr) >= 0)
#define FAILED(hr)     ((HRESULT)(hr) < 0)

struct GUID {
    uint32_t Data1;
    uint16_t Data2;
    uint16_t Data3;
    uint8_t  Data4[8];
};

typedef const GUID &REFIID;
typedef const GUID &REFCLSID;

inline bool operator==(const GUID &a, const GUID &b) {
    return std::memcmp(&a, &b, sizeof(GUID)) == 0;
}

/* No __stdcall off x86, exactly as SL_COM_METHOD resolves it. */
#define STDMETHODCALLTYPE

struct IUnknown {
    virtual HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) = 0;
    virtual ULONG   STDMETHODCALLTYPE AddRef() = 0;
    virtual ULONG   STDMETHODCALLTYPE Release() = 0;
};

struct IClassFactory : IUnknown {
    virtual HRESULT STDMETHODCALLTYPE CreateInstance(
        IUnknown *outer, REFIID riid, void **ppv) = 0;
    virtual HRESULT STDMETHODCALLTYPE LockServer(int32_t lock) = 0;
};

static const GUID IID_IUnknown =
    { 0x00000000, 0x0000, 0x0000, { 0xC0, 0, 0, 0, 0, 0, 0, 0x46 } };
static const GUID IID_IClassFactory =
    { 0x00000001, 0x0000, 0x0000, { 0xC0, 0, 0, 0, 0, 0, 0, 0x46 } };

#endif /* _WIN32 */

/* ------------------------------------------------- the server's own types */

/* 9d2f5f7a-1c64-4a3b-8f0e-7d5a2c9b4e10 -- [Guid] on `com interface IGreeter` */
static const GUID IID_IGreeter = {
    0x9d2f5f7a, 0x1c64, 0x4a3b,
    { 0x8f, 0x0e, 0x7d, 0x5a, 0x2c, 0x9b, 0x4e, 0x10 }
};

/* b71e0c48-3a95-4f2d-9c11-6e8a0d3f5b27 -- [Guid] on `com interface ICounter` */
static const GUID IID_ICounter = {
    0xb71e0c48, 0x3a95, 0x4f2d,
    { 0x9c, 0x11, 0x6e, 0x8a, 0x0d, 0x3f, 0x5b, 0x27 }
};

/* 5a1c8e30-2b47-4d16-a9f3-c04e7b81d629 -- [Guid] on `com class Greeter`.
   A CLSID and not an IID: it names the class, which is what activation asks
   for when it holds no object yet. */
static const GUID CLSID_Greeter = {
    0x5a1c8e30, 0x2b47, 0x4d16,
    { 0xa9, 0xf3, 0xc0, 0x4e, 0x7b, 0x81, 0xd6, 0x29 }
};

/*
 * Slots 3 and 4. IUnknown's three come first because every COM vtable begins
 * with them, which is also why Stainless writes `com interface IGreeter` with
 * two methods and gets a five-slot table.
 */
struct IGreeter : IUnknown {
    virtual HRESULT STDMETHODCALLTYPE Greet(int32_t times, int32_t *total) = 0;
    virtual HRESULT STDMETHODCALLTYPE Total(int32_t *total) = 0;
};

struct ICounter : IUnknown {
    virtual HRESULT STDMETHODCALLTYPE Reset() = 0;
};

/* The one export that matters. COM's own loader calls this; here the host
   calls it directly, which is the same thing without the registry. */
typedef HRESULT (*DllGetClassObjectFn)(REFCLSID rclsid, REFIID riid, void **ppv);
typedef HRESULT (*DllCanUnloadNowFn)(void);

#endif /* GREETER_H */
