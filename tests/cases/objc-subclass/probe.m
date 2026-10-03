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

// Objective-C sending to classes Stainless defined. It knows them only by
// the selectors they answer and the names they were registered under, as
// any Cocoa code holding one would.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

typedef struct { double a, b, c, d; } SLWide;

// Declared here as well as in Stainless. Each image carries the protocols it
// names, and the runtime keeps one of each name.
@protocol Shape <NSObject>
- (double)area;
@property (readonly) long sides;
@optional
- (void)grow:(double)by;
@end

@interface NSObject (SLSquare)
+ (id)square;
- (long)scaled:(long)by;
- (SLWide)spreadFlipped:(BOOL)flipped;
- (BOOL)isLargerThan:(double)other;
- (NSString *)named:(NSString *)name;
@end

double SLAreaOf(id<Shape> shape) { return [shape area]; }

long SLSidesOf(id<Shape> shape) { return shape.sides; }

long SLScale(id square, long by) { return [square scaled:by]; }

BOOL SLConforms(id shape) { return [shape conformsToProtocol:@protocol(Shape)]; }

BOOL SLAnswersGrow(id shape) { return [shape respondsToSelector:@selector(grow:)]; }

BOOL SLIsLarger(id square, double other) { return [square isLargerThan:other]; }

double SLSpreadFirst(id square, BOOL flipped) { return [square spreadFlipped:flipped].a; }

double SLSpreadSum(id square, BOOL flipped)
{
    SLWide wide = [square spreadFlipped:flipped];
    return wide.a * 1000 + wide.b * 100 + wide.c * 10 + wide.d;
}

const char *SLDescribe(id anything) { return [[anything description] UTF8String]; }

const char *SLNamed(id square, const char *name)
{
    return [[square named:[NSString stringWithUTF8String:name]] UTF8String];
}

// The class method, sent to a class found by the name it was registered
// under, and a message to what it makes.
long SLMadeByName(const char *name)
{
    Class found = NSClassFromString([NSString stringWithUTF8String:name]);
    id made = [found square];
    return [made scaled:1] + (long)[(id<Shape>)made area];
}

const char *SLSuperclassOf(const char *name)
{
    Class found = NSClassFromString([NSString stringWithUTF8String:name]);
    return class_getName(class_getSuperclass(found));
}
