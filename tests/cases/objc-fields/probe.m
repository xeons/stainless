// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

// A superclass with ivars Stainless cannot see, so the runtime has to slide
// the Stainless classes' ivars past them, and Objective-C making objects of
// the Stainless classes through the inits they answer.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

@interface SLBase : NSObject {
    long _a;
    long _b;
    long _base;
}
- (instancetype)initWithBase:(long)value;
- (long)baseValue;
@end

@implementation SLBase

- (instancetype)initWithBase:(long)value
{
    self = [super init];
    if (self != nil) {
        _a = -1;
        _b = -2;
        _base = value;
    }
    return self;
}

- (long)baseValue { return _base + _a + _b + 3; }

@end

@interface NSObject (SLCounter)
- (instancetype)initWithCount:(long)count;
- (instancetype)initWithExtra:(long)extra;
- (long)count;
- (long)extra;
- (long)noteLength;
@end

static Class Named(const char *name)
{
    return NSClassFromString([NSString stringWithUTF8String:name]);
}

long SLCountAfterInit(const char *name) { return [[[Named(name) alloc] init] count]; }

long SLBaseAfterInit(const char *name) { return [[[Named(name) alloc] init] baseValue]; }

long SLNoteLengthAfterInit(void)
{
    return [[[Named("ObjCFields.Counter") alloc] init] noteLength];
}

long SLCountWithCount(long count)
{
    return [[[Named("ObjCFields.Counter") alloc] initWithCount:count] count];
}

long SLBaseWithCount(long count)
{
    return [[[Named("ObjCFields.Counter") alloc] initWithCount:count] baseValue];
}

long SLExtraWithExtra(long extra)
{
    return [[[Named("ObjCFields.Wider") alloc] initWithExtra:extra] extra];
}

long SLIvarOffset(const char *name)
{
    return (long)ivar_getOffset(class_getInstanceVariable(Named(name), "_sl"));
}

long SLInstanceSize(const char *name) { return (long)class_getInstanceSize(Named(name)); }

long SLBaseSize(void) { return (long)class_getInstanceSize([SLBase class]); }
