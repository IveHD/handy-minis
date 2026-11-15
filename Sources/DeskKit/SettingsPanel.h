#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DeskKitShortcut) {
    DeskKitShortcutQueue = 1,
    DeskKitShortcutScreenshot = 2,
};

typedef NS_ENUM(NSInteger, DeskKitTheme) {
    DeskKitThemeSystem,
    DeskKitThemeLight,
    DeskKitThemeDark,
};

typedef NS_ENUM(NSInteger, DeskKitPreference) {
    DeskKitPreferenceLaunchAtLogin,
    DeskKitPreferenceAnalytics,
    DeskKitPreferenceTiling,
};

@class SettingsPanel;

@protocol SettingsPanelDelegate <NSObject>
- (NSString *)shortcutTitleForAction:(DeskKitShortcut)action;
- (BOOL)toolIsEnabledForAction:(DeskKitShortcut)action;
- (void)setToolEnabled:(BOOL)enabled forAction:(DeskKitShortcut)action;
- (BOOL)shortcutIsUnavailableForAction:(DeskKitShortcut)action;
- (void)clearShortcutForAction:(DeskKitShortcut)action;
- (BOOL)recordShortcutForAction:(DeskKitShortcut)action keyCode:(unsigned short)keyCode modifierFlags:(NSEventModifierFlags)flags;
- (BOOL)isPreferenceEnabled:(DeskKitPreference)preference;
- (void)togglePreference:(DeskKitPreference)preference;
- (void)settingsPanelDidClose:(SettingsPanel *)panel;
@end

@interface SettingsPanel : NSObject
@property (nonatomic, weak) id<SettingsPanelDelegate> delegate;
+ (void)applySavedTheme;
- (void)show;
- (void)refreshTools;
- (BOOL)handleRegisteredShortcut:(DeskKitShortcut)action;
@end

NS_ASSUME_NONNULL_END
