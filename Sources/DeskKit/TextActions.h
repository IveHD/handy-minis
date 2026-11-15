#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DeskKitTextAction) {
    DeskKitTextActionUnwrap,
    DeskKitTextActionTrimSpaces,
    DeskKitTextActionSingleLine,
};

NSString *DeskKitTransformText(NSString *text, DeskKitTextAction action);

NS_ASSUME_NONNULL_END
