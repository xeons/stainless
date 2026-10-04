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

// A class written in Objective-C for the Stainless side to send to. It
// counts the instances alive, so the case can say every object was freed
// once: a leak leaves the count above zero, and a release too many crashes.

#import <Foundation/Foundation.h>

typedef struct { double a, b, c, d; } SLWide;

static int s_alive = 0;

@interface SLTracked : NSObject
@property (nonatomic) long value;
+ (int)alive;
+ (instancetype)trackedWithValue:(long)value;
- (instancetype)initWithValue:(long)value;
- (SLWide)spread;
- (BOOL)isPositive;
- (BOOL)isGreaterThan:(long)other flag:(BOOL)flag;
- (SLTracked *)copyDoubled;
- (BOOL)makeTwin:(SLTracked **)twin;
- (SLTracked *)maybe:(BOOL)give;
- (nullable instancetype)initIfPositive:(long)value;
@end

@implementation SLTracked
{
    BOOL _counted;
}

+ (int)alive { return s_alive; }

+ (instancetype)trackedWithValue:(long)value
{
    return [[self alloc] initWithValue:value];
}

- (instancetype)initWithValue:(long)value
{
    self = [super init];
    if (self != nil) {
        _value = value;
        _counted = YES;
        s_alive++;
    }
    return self;
}

- (void)dealloc
{
    // An object its init refused was never counted.
    if (_counted) s_alive--;
}

- (SLWide)spread
{
    SLWide wide = { _value + 0.5, _value + 1.5, _value + 2.5, _value + 3.5 };
    return wide;
}

- (BOOL)isPositive { return _value > 0; }

- (BOOL)isGreaterThan:(long)other flag:(BOOL)flag
{
    return flag ? _value > other : _value <= other;
}

- (SLTracked *)copyDoubled { return [[SLTracked alloc] initWithValue:_value * 2]; }

- (BOOL)makeTwin:(SLTracked **)twin
{
    *twin = [SLTracked trackedWithValue:_value + 100];
    return YES;
}

- (nullable instancetype)initIfPositive:(long)value
{
    if (value <= 0) return nil;
    return [self initWithValue:value];
}

- (SLTracked *)maybe:(BOOL)give
{
    return give ? [SLTracked trackedWithValue:_value] : nil;
}

@end
