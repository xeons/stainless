#import <Foundation/Foundation.h>

@interface SLThrower : NSObject
@property (nonatomic) BOOL wasReset;
@end

@implementation SLThrower

- (long)countOf:(long)count
{
    if (count < 0)
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"negative" userInfo:nil];
    return count;
}

- (void)reset
{
    if (self.wasReset)
        @throw [NSException exceptionWithName:@"SLTest" reason:@"already reset" userInfo:nil];
    self.wasReset = YES;
}

+ (NSObject *)made
{
    return [[NSObject alloc] init];
}

@end

int SLHalve(int number)
{
    if (number % 2 != 0)
        @throw [NSException exceptionWithName:@"SLOdd"
                                       reason:[NSString stringWithFormat:@"%d is odd", number]
                                     userInfo:nil];
    return number / 2;
}
