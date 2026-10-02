// A class that adopts a protocol and answers none of its optional members.
#import <Foundation/Foundation.h>

@protocol SLListener <NSObject>
@optional
- (void)heard:(long)value;
@end

@interface SLQuiet : NSObject <SLListener>
@end
@implementation SLQuiet
@end
