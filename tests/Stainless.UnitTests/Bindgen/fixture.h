// The shapes the bindings generator has to read, one of each. Dumped with
//   clang -x objective-c -target arm64-apple-macosx13.0 -fsyntax-only
//     -Xclang -ast-dump=json fixture.h > fixture.json
typedef long Index;
typedef struct Range { Index location; Index length; } Range;
typedef struct { double x; double y; } Point;
typedef const struct __Opaque *OpaqueRef;
typedef union Word { int whole; short halves[2]; } Word;
struct Flags { unsigned int ready : 1; unsigned int kind : 3; };
struct __attribute__((packed)) Wire { char tag; int value; };
struct Holder { int count; union { int asInt; float asFloat; }; struct { int a; int b; } pair; char name[16]; };
typedef enum Compare : long { kCompareLess = -1, kCompareSame = 0, kCompareMore = 1 } Compare;
typedef enum __attribute__((flag_enum)) Options : unsigned int { kOptionNone = 0, kOptionFast = 1, kOptionSafe = 2 } Options;
enum { kNotFound = -1 };
typedef void (*Callback)(void *info, Index value);
typedef void (^Handler)(Index value);
extern const OpaqueRef kDefaultOpaque;
extern Index RangeEnd(Range range, const char *label, ...);
static inline Index Twice(Index value) { return value * 2; }
extern void Perform(void (^block)(void));
