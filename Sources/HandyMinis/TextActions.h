#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, HandyMinisTextAction) {
    HandyMinisTextActionUnwrap,
    HandyMinisTextActionTrimSpaces,
    HandyMinisTextActionSingleLine,
};

NSString *HandyMinisTransformText(NSString *text, HandyMinisTextAction action);

NS_ASSUME_NONNULL_END
