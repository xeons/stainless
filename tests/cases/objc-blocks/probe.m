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

// Objective-C on the other side of each block: one it keeps and calls
// later, one it makes for Stainless to call, results of each kind, and a
// block built on its own stack handed to a class Stainless defined.

#import <Foundation/Foundation.h>

typedef struct { double a, b, c, d; } SLWide;

@interface NSObject (SLKeeper)
- (void)keepFor:(long (^)(long))transform;
@end

static long (^s_kept)(long);

@interface SLBlocks : NSObject
@end

@implementation SLBlocks

+ (void)keep:(long (^)(long))transform { s_kept = transform; }

+ (long)fire:(long)value { return s_kept(value); }

+ (void)drop { s_kept = nil; }

+ (long (^)(long))adderFor:(long)amount
{
    return ^long(long value) { return value + amount; };
}

+ (BOOL)ask:(BOOL (^)(NSString *))test about:(NSString *)text { return test(text); }

+ (NSString *)name:(NSString *(^)(long))name with:(long)value { return name(value); }

+ (double)spread:(SLWide (^)(double))spread with:(double)value
{
    SLWide wide = spread(value);
    return wide.a + wide.b + wide.c + wide.d;
}

long SLCallSure(long (^transform)(long), long value) { return transform(value); }

long SLCallMaybe(long (^transform)(long), long value) { return transform ? transform(value) : -1; }

// The block lives on this frame's stack; the keeper has to copy it.
+ (long)handTo:(id)keeper
{
    long offset = 1000;
    [keeper keepFor:^long(long value) { return value + offset; }];
    return offset;
}

@end
