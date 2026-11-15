#import <Foundation/Foundation.h>
@interface Analytics : NSObject
+ (void)track:(NSString *)event;
@end
