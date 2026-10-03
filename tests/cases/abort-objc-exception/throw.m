#import <Foundation/Foundation.h>

@interface NSObject (SLRunner)
- (void)run;
@end

void SLThrow(void)
{
    @throw [NSException exceptionWithName:@"SLTest" reason:@"thrown" userInfo:nil];
}

void SLRun(id runner) { [runner run]; }
