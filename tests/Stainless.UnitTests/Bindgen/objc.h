// The Objective-C and Core Foundation shapes the bindings generator has to
// read, one of each, with nothing included. Dumped with
//   clang -x objective-c -fobjc-arc -target arm64-apple-macosx15.0
//     -fsyntax-only -Xclang -ast-dump=json objc.h > objc.json
typedef _Bool BOOL;
typedef unsigned long CFTypeID;
typedef const void *CFTypeRef;
typedef const struct __attribute__((objc_bridge(NSString))) __CFString *CFStringRef;
typedef struct __attribute__((objc_bridge_mutable(NSMutableString))) __CFString *CFMutableStringRef;
typedef struct CGPath *CGPathRef;
typedef struct OpaqueQueue *QueueRef;
typedef struct Pair { CFStringRef name; CFTypeRef value; } Pair;
typedef void (*Applier)(CFStringRef name, void *context);

CFTypeID CFStringGetTypeID(void);
CFTypeID CGPathGetTypeID(void);
CFStringRef CFStringCreateCopy(CFTypeRef allocator, CFStringRef text);
CFStringRef CFStringGetName(CFStringRef text);
CFStringRef MakeName(void) __attribute__((cf_returns_retained));
CFStringRef CopiedNot(void) __attribute__((cf_returns_not_retained));
CFTypeRef CFRetain(CFTypeRef cf);
void CFRelease(CFTypeRef cf);
void CGPathRelease(CGPathRef path);
void TakeOwnership(__attribute__((cf_consumed)) CFTypeRef cf);
QueueRef QueueCreate(void);
extern const CFStringRef _Nonnull kNameKey;
extern const CFStringRef kLooseKey;

#pragma clang assume_nonnull begin

@class NSString;
@class NSError;

@protocol NSObject
- (BOOL)isEqual:(id)object;
@property (readonly) unsigned long hash;
@end

__attribute__((objc_root_class))
@interface NSObject <NSObject>
+ (instancetype)alloc;
- (instancetype)init;
+ (NSString *)description;
@end

@interface NSError : NSObject
@end

@protocol Copying
- (id)copyWithZone:(void *_Nullable)zone;
+ (BOOL)supportsCopying;
@optional
- (void)optionalThing;
@property (readonly) BOOL optionalFlag;
@required
- (void)requiredThing;
@end

@interface NSString : NSObject <Copying>
@property (readonly) unsigned long length;
@property (class, readonly, copy) NSString *empty;
@property (nullable, copy) NSString *title;
@property (getter=isOpen) BOOL open;
- (nullable instancetype)initWithCoder:(id)coder;
- (NSString *)stringByAppendingString:(NSString *)other;
- (BOOL)writeToFile:(NSString *)path error:(NSError **)error;
- (void)enumerateLines:(void (^)(NSString *line, BOOL *stop))block;
- (NSString *)stringWithFormat:(NSString *)format, ...;
- (CFStringRef)cfString;
- (id<Copying>)copier;
- (NSString *)madeThing __attribute__((ns_returns_retained));
- (void)gone __attribute__((unavailable));
- (null_unspecified NSString *)loose;
- (unsigned long)length;
@end

@interface NSArray<__covariant ObjectType> : NSObject
- (ObjectType)objectAtIndex:(unsigned long)index;
- (NSArray<ObjectType> *)arrayByAddingObject:(ObjectType)object;
@end

@interface NSString (Drawing) <NSObject>
- (void)draw;
+ (NSString *)description;
@end

typedef NSString *Mode;
extern Mode const DefaultMode;
NSString *NSStringFromThing(int value);
NSString *NSMadeString(void) __attribute__((ns_returns_retained));

#pragma clang assume_nonnull end
