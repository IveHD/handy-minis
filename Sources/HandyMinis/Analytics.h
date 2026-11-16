#import <Foundation/Foundation.h>
@interface Analytics : NSObject
+ (void)startRUM;
+ (void)stopRUM;
+ (void)reportLaunchToRUM;
+ (void)reportFeature:(NSString *)event;
+ (void)track:(NSString *)event;
@end

void HandyMinisReportScreenshotUsage(const char *event);
