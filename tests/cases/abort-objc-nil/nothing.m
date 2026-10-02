// A class method that answers nil, which the Stainless side declares as
// never doing so.
#import <Foundation/Foundation.h>

@interface SLNothing : NSObject
+ (id)nothing;
@end

@implementation SLNothing
+ (id)nothing { return nil; }
@end
