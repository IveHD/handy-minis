#import <Foundation/Foundation.h>

@interface WindowTiling : NSObject
- (void)start;
- (void)stop;
- (NSArray<NSString *> *)layoutNames;
- (void)saveLayoutNamed:(NSString *)name completion:(void (^)(NSUInteger count))completion;
- (void)restoreLayoutNamed:(NSString *)name completion:(void (^)(NSUInteger restored, NSUInteger total))completion;
- (void)deleteLayoutNamed:(NSString *)name;
@end
