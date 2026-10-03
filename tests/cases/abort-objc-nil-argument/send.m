#import <Foundation/Foundation.h>

@interface NSObject (SLGreeter)
- (long)greet:(id)other;
@end

long SLGreetNil(id greeter) { return [greeter greet:nil]; }
