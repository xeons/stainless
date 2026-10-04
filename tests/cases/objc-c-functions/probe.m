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

// C functions and a C variable handing Objective-C objects to Stainless. The
// class counts its instances alive, so a leak or a release too many shows.

#import <Foundation/Foundation.h>

static int s_alive = 0;

@interface SLCounted : NSObject
@property (nonatomic) long value;
@end

@implementation SLCounted
- (instancetype)init
{
    self = [super init];
    if (self != nil) s_alive++;
    return self;
}
- (void)dealloc { s_alive--; }
@end

int SLAlive(void) { return s_alive; }

SLCounted *SLMakeAutoreleased(long value)
{
    SLCounted *made = [SLCounted new];
    made.value = value;
    return made;
}

SLCounted *SLMakeRetained(long value) NS_RETURNS_RETAINED
{
    SLCounted *made = [SLCounted new];
    made.value = value;
    return made;
}

SLCounted *SLMaybe(BOOL give) { return give ? SLMakeAutoreleased(7) : nil; }

SLCounted *SLShared;

__attribute__((constructor)) static void SLMakeShared(void)
{
    SLShared = SLMakeRetained(42);
}
