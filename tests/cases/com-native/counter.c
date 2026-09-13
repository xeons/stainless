/*
 * The C half: a COM vtable declared the way a COM header declares one.
 *
 * Nothing here includes stainless.h. That is the point -- this is what a
 * program written against the binary contract looks like, and if the compiler
 * and this file disagreed about the convention nothing would say so at link
 * time. On x86 a __stdcall callee removes the arguments, so a mismatch loses
 * the stack rather than a value.
 */
#include <stdint.h>
#include <stdio.h>

#if defined(__i386__) || defined(_M_IX86)
#  if defined(_MSC_VER) || defined(__clang__)
#    define COM_METHOD __stdcall
#  else
#    define COM_METHOD __attribute__((stdcall))
#  endif
#else
#  define COM_METHOD
#endif

typedef struct Guid {
    uint32_t data1;
    uint16_t data2;
    uint16_t data3;
    uint8_t  data4[8];
} Guid;

typedef struct ICounter ICounter;

typedef struct ICounterVtbl {
    int32_t  (COM_METHOD *QueryInterface)(ICounter *self, const Guid *iid, void **out);
    uint32_t (COM_METHOD *AddRef)(ICounter *self);
    uint32_t (COM_METHOD *Release)(ICounter *self);
    int32_t  (COM_METHOD *Add)(ICounter *self, int32_t by);
    int32_t  (COM_METHOD *Value)(ICounter *self);
} ICounterVtbl;

struct ICounter { const ICounterVtbl *lpVtbl; };

/* 58ba1f7c-2e04-4a16-9c8d-31e07f6ab254, as the [Guid] on ICounter. */
static const Guid IID_ICounter = {
    0x58ba1f7c, 0x2e04, 0x4a16,
    { 0x9c, 0x8d, 0x31, 0xe0, 0x7f, 0x6a, 0xb2, 0x54 }
};

static const Guid IID_IUnknown = {
    0x00000000, 0x0000, 0x0000,
    { 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 }
};

static int guid_equals(const Guid *a, const Guid *b)
{
    const uint8_t *l = (const uint8_t *)a, *r = (const uint8_t *)b;
    int i;
    for (i = 0; i < 16; i++) if (l[i] != r[i]) return 0;
    return 1;
}

/* ------------------------------------- C calling a Stainless com class --- */

/*
 * Everything a COM caller does: take a reference, call through the table, ask
 * the object what it is, and let go.
 *
 * The count AddRef returns is the object's own, so it says the compiler's ARC
 * and this call are moving the same number.
 */
int count_through(void *pointer)
{
    ICounter *it = (ICounter *)pointer;
    void *asked = NULL;
    uint32_t held, left;
    int32_t value;

    held = it->lpVtbl->AddRef(it);
    it->lpVtbl->Add(it, 10);
    it->lpVtbl->Add(it, 5);
    value = it->lpVtbl->Value(it);

    if (it->lpVtbl->QueryInterface(it, &IID_ICounter, &asked) == 0 && asked != NULL)
        ((ICounter *)asked)->lpVtbl->Release((ICounter *)asked);
    else
        printf("c: QueryInterface for ICounter failed\n");

    left = it->lpVtbl->Release(it);

    printf("c: held %u, then %u\n", (unsigned)held, (unsigned)left);
    return (int)value;
}

/* ------------------------------------- Stainless calling a C com class --- */

typedef struct NativeCounter {
    const ICounterVtbl *lpVtbl;
    uint32_t            strong;
    int32_t             total;
} NativeCounter;

static NativeCounter the_counter;

static int32_t COM_METHOD native_query(ICounter *self, const Guid *iid, void **out)
{
    if (out == NULL) return (int32_t)0x80004003;   /* E_POINTER */
    *out = NULL;
    if (iid == NULL) return (int32_t)0x80004003;

    if (!guid_equals(iid, &IID_ICounter) && !guid_equals(iid, &IID_IUnknown))
        return (int32_t)0x80004002;                /* E_NOINTERFACE */

    *out = self;
    ((NativeCounter *)self)->strong++;
    return 0;
}

static uint32_t COM_METHOD native_add_ref(ICounter *self)
{
    return ++((NativeCounter *)self)->strong;
}

static uint32_t COM_METHOD native_release(ICounter *self)
{
    NativeCounter *me = (NativeCounter *)self;
    uint32_t left = --me->strong;
    if (left == 0) printf("c: native counter released\n");
    return left;
}

static int32_t COM_METHOD native_add(ICounter *self, int32_t by)
{
    NativeCounter *me = (NativeCounter *)self;
    me->total += by;
    return me->total;
}

static int32_t COM_METHOD native_value(ICounter *self)
{
    return ((NativeCounter *)self)->total;
}

static const ICounterVtbl native_vtable = {
    native_query, native_add_ref, native_release, native_add, native_value
};

/* An owned reference, which is what a COM factory hands back. */
void *native_counter(void)
{
    the_counter.lpVtbl = &native_vtable;
    the_counter.strong = 1;
    the_counter.total = 0;
    return &the_counter;
}

int native_live(void) { return (int)the_counter.strong; }
