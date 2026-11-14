#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class SettingsPanel;

@protocol SettingsPanelDelegate <NSObject>
- (NSString *)settingsPanelShortcutTitle:(SettingsPanel *)panel;
- (BOOL)settingsPanel:(SettingsPanel *)panel recordShortcutWithKeyCode:(unsigned short)keyCode modifierFlags:(NSEventModifierFlags)flags;
- (void)settingsPanelDidClose:(SettingsPanel *)panel;
@end

@interface SettingsPanel : NSObject
@property (nonatomic, weak) id<SettingsPanelDelegate> delegate;
- (void)show;
@end

NS_ASSUME_NONNULL_END
