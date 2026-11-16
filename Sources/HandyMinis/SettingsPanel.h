#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, HandyMinisShortcut) {
    HandyMinisShortcutQueue = 1,
    HandyMinisShortcutScreenshot = 2,
};

typedef NS_ENUM(NSInteger, HandyMinisTheme) {
    HandyMinisThemeSystem,
    HandyMinisThemeLight,
    HandyMinisThemeDark,
};

typedef NS_ENUM(NSInteger, HandyMinisPreference) {
    HandyMinisPreferenceLaunchAtLogin,
    HandyMinisPreferenceAnalytics,
    HandyMinisPreferenceTiling,
};

@class SettingsPanel;
@class HMPanelStyle;

@protocol SettingsPanelDelegate <NSObject>
- (NSString *)shortcutTitleForAction:(HandyMinisShortcut)action;
- (BOOL)toolIsEnabledForAction:(HandyMinisShortcut)action;
- (void)setToolEnabled:(BOOL)enabled forAction:(HandyMinisShortcut)action;
- (BOOL)shortcutIsUnavailableForAction:(HandyMinisShortcut)action;
- (void)clearShortcutForAction:(HandyMinisShortcut)action;
- (BOOL)recordShortcutForAction:(HandyMinisShortcut)action keyCode:(unsigned short)keyCode modifierFlags:(NSEventModifierFlags)flags;
- (BOOL)isPreferenceEnabled:(HandyMinisPreference)preference;
- (void)togglePreference:(HandyMinisPreference)preference;
- (void)settingsPanelDidClose:(SettingsPanel *)panel;
@end

@interface SettingsPanel : NSObject
- (instancetype)initWithPanelStyle:(HMPanelStyle *)style;
@property (nonatomic, weak) id<SettingsPanelDelegate> delegate;
+ (void)applySavedTheme;
- (void)show;
- (void)refreshTools;
- (BOOL)handleRegisteredShortcut:(HandyMinisShortcut)action;
@end

NS_ASSUME_NONNULL_END
