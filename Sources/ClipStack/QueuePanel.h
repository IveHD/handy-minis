#import <Cocoa/Cocoa.h>
#import "ClipboardStore.h"

NS_ASSUME_NONNULL_BEGIN

@class QueuePanel;

@protocol QueuePanelDelegate <NSObject>
- (void)queuePanel:(QueuePanel *)panel didChooseItem:(ClipItem *)item paste:(BOOL)paste;
- (void)queuePanel:(QueuePanel *)panel didDeleteItem:(ClipItem *)item;
- (void)queuePanelDidRequestAccessibility:(QueuePanel *)panel;
- (NSString *)queuePanelShortcutTitle:(QueuePanel *)panel;
@end

@interface QueuePanel : NSObject
@property (nonatomic, weak) id<QueuePanelDelegate> delegate;
@property (nonatomic, readonly) BOOL isVisible;
- (instancetype)initWithStore:(ClipboardStore *)store;
- (void)show;
- (void)hide;
- (void)setShortcutTitle:(NSString *)title;
/// Dismiss the panel without giving up active-app status, so the caller can hand focus back.
- (void)orderOutKeepingActive;
@end

NS_ASSUME_NONNULL_END
