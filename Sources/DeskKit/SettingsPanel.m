#import "SettingsPanel.h"
#import <Carbon/Carbon.h>

static NSString *const ThemeKey = @"AppearanceTheme";

@interface SettingsPanel () <NSWindowDelegate>
@property NSWindow *window;
@property NSPopUpButton *themePicker;
@property NSDictionary<NSNumber *, NSButton *> *shortcutButtons;
@property NSArray<NSButton *> *toolButtons;
@property NSArray<NSButton *> *preferenceButtons;
@property NSTextField *statusLabel;
@property id keyMonitor;
@property DeskKitShortcut recordingAction;
@end

@implementation SettingsPanel

+ (void)applySavedTheme {
    switch ([NSUserDefaults.standardUserDefaults integerForKey:ThemeKey]) {
        case DeskKitThemeLight: NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua]; break;
        case DeskKitThemeDark: NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]; break;
        default: NSApp.appearance = nil; break;
    }
}

- (instancetype)init {
    if ((self = [super init])) {
        _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, 350)
                                               styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                 backing:NSBackingStoreBuffered defer:NO];
        _window.title = @"设置";
        _window.delegate = self;
        _window.releasedWhenClosed = NO;
        [self buildContent];
        __weak SettingsPanel *weakSelf = self;
        _keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
            SettingsPanel *panel = weakSelf;
            if (!panel.recordingAction || !panel.window.isKeyWindow) return event;
            return [panel handleRecordingKey:event];
        }];
    }
    return self;
}

- (void)dealloc {
    if (_keyMonitor) [NSEvent removeMonitor:_keyMonitor];
}

- (void)addRowWithTitle:(NSString *)title control:(NSView *)control toStack:(NSStackView *)stack {
    NSTextField *label = [NSTextField labelWithString:title];
    NSView *spacer = [NSView new];
    NSStackView *row = [NSStackView stackViewWithViews:@[label, spacer, control]];
    [stack addArrangedSubview:row];
    [row.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    [control.widthAnchor constraintEqualToConstant:154].active = YES;
}

- (void)buildContent {
    NSView *content = self.window.contentView;
    NSStackView *stack = [NSStackView new];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:stack];

    self.themePicker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.themePicker addItemsWithTitles:@[@"跟随系统", @"浅色", @"深色"]];
    self.themePicker.target = self;
    self.themePicker.action = @selector(changeTheme:);
    [self addRowWithTitle:@"外观" control:self.themePicker toStack:stack];

    NSTextField *toolsLabel = [NSTextField labelWithString:@"工具"];
    toolsLabel.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
    [stack addArrangedSubview:toolsLabel];

    NSArray<NSNumber *> *actions = @[@(DeskKitShortcutQueue), @(DeskKitShortcutScreenshot)];
    NSArray<NSString *> *titles = @[@"剪贴板历史", @"框选截图"];
    NSArray<NSString *> *shortcutLabels = @[@"打开复制队列", @"框选截图"];
    NSMutableDictionary<NSNumber *, NSButton *> *shortcuts = [NSMutableDictionary dictionary];
    NSMutableArray<NSButton *> *toolButtons = [NSMutableArray array];
    [actions enumerateObjectsUsingBlock:^(NSNumber *action, NSUInteger index, BOOL *stop) {
        NSButton *toggle = [NSButton checkboxWithTitle:titles[index] target:self action:@selector(toolClicked:)];
        toggle.tag = action.integerValue;
        [toolButtons addObject:toggle];

        NSButton *shortcut = [NSButton buttonWithTitle:@"" target:self action:@selector(recordClicked:)];
        shortcut.tag = action.integerValue;
        shortcut.toolTip = shortcutLabels[index];
        [shortcut setAccessibilityLabel:[shortcutLabels[index] stringByAppendingString:@"快捷键"]];
        shortcuts[action] = shortcut;
        NSView *spacer = [NSView new];
        NSStackView *row = [NSStackView stackViewWithViews:@[toggle, spacer, shortcut]];
        [stack addArrangedSubview:row];
        [row.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
        [shortcut.widthAnchor constraintEqualToConstant:154].active = YES;
    }];
    self.toolButtons = toolButtons;
    self.shortcutButtons = shortcuts;

    NSButton *tiling = [NSButton checkboxWithTitle:@"拖拽整理窗口" target:self action:@selector(preferenceClicked:)];
    tiling.tag = DeskKitPreferenceTiling;
    [stack addArrangedSubview:tiling];

    self.statusLabel = [NSTextField labelWithString:@""];
    self.statusLabel.font = [NSFont systemFontOfSize:12];
    [stack addArrangedSubview:self.statusLabel];
    [self.statusLabel.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;

    NSBox *separator = [NSBox new];
    separator.boxType = NSBoxSeparator;
    [stack addArrangedSubview:separator];
    [separator.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;

    NSMutableArray<NSButton *> *preferences = [NSMutableArray arrayWithObject:tiling];
    NSArray<NSString *> *preferenceTitles = @[@"登录时启动", @"发送匿名使用统计"];
    [preferenceTitles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger index, BOOL *stop) {
        if (index == DeskKitPreferenceAnalytics && ![[NSBundle.mainBundle objectForInfoDictionaryKey:@"AptabaseAppKey"] length]) return;
        NSButton *button = [NSButton checkboxWithTitle:title target:self action:@selector(preferenceClicked:)];
        button.tag = index;
        [stack addArrangedSubview:button];
        [preferences addObject:button];
    }];
    self.preferenceButtons = preferences;

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-24],
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:22],
    ]];
}

- (void)changeTheme:(NSPopUpButton *)sender {
    [NSUserDefaults.standardUserDefaults setInteger:sender.indexOfSelectedItem forKey:ThemeKey];
    [SettingsPanel applySavedTheme];
}

- (void)toolClicked:(NSButton *)sender {
    [self endRecordingWithError:nil];
    [self.delegate setToolEnabled:sender.state == NSControlStateValueOn forAction:sender.tag];
}

- (void)refreshTools {
    for (NSButton *button in self.toolButtons) {
        button.state = [self.delegate toolIsEnabledForAction:button.tag] ? NSControlStateValueOn : NSControlStateValueOff;
    }
    [self refreshShortcuts];
}

- (void)preferenceClicked:(NSButton *)sender {
    [self.delegate togglePreference:sender.tag];
    [self refreshPreferences];
}

- (void)refreshPreferences {
    for (NSButton *button in self.preferenceButtons) {
        button.state = [self.delegate isPreferenceEnabled:button.tag] ? NSControlStateValueOn : NSControlStateValueOff;
    }
}

- (void)show {
    [self endRecordingWithError:nil];
    [self refreshPreferences];
    [self refreshTools];
    NSInteger theme = [NSUserDefaults.standardUserDefaults integerForKey:ThemeKey];
    [self.themePicker selectItemAtIndex:theme >= DeskKitThemeSystem && theme <= DeskKitThemeDark ? theme : DeskKitThemeSystem];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [NSApp activateIgnoringOtherApps:YES];
#pragma clang diagnostic pop
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
}

- (void)endRecordingWithError:(NSString *)error {
    self.recordingAction = 0;
    [self refreshShortcuts];
    self.statusLabel.textColor = error ? NSColor.systemRedColor : NSColor.secondaryLabelColor;
    self.statusLabel.stringValue = error ?: @"点击按钮修改快捷键。";
}

- (void)refreshShortcuts {
    for (NSNumber *key in self.shortcutButtons) {
        DeskKitShortcut action = key.integerValue;
        NSString *title = [self.delegate shortcutTitleForAction:action];
        if (action == self.recordingAction) title = @"请按下快捷键";
        else if ([self.delegate shortcutIsUnavailableForAction:action]) title = [title stringByAppendingString:@"（不可用）"];
        self.shortcutButtons[key].title = title;
    }
}

- (void)recordClicked:(NSButton *)sender {
    self.recordingAction = sender.tag;
    self.statusLabel.textColor = NSColor.secondaryLabelColor;
    self.statusLabel.stringValue = @"按含 ⌘ 或 ⌃ 的组合键，Esc 取消，Delete 清除。";
    [self refreshShortcuts];
}

- (BOOL)handleRegisteredShortcut:(DeskKitShortcut)action {
    if (!self.recordingAction || !self.window.isKeyWindow) return NO;
    [self endRecordingWithError:action == self.recordingAction ? nil : @"这个快捷键已被占用。"];
    return YES;
}

- (NSEvent *)handleRecordingKey:(NSEvent *)event {
    if (event.keyCode == kVK_Escape) {
        [self endRecordingWithError:nil];
        return nil;
    }
    NSEventModifierFlags flags = event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagControl);
    if (event.keyCode == kVK_Delete && !flags) {
        [self.delegate clearShortcutForAction:self.recordingAction];
        [self endRecordingWithError:nil];
        return nil;
    }
    if (!(flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl))) {
        self.statusLabel.stringValue = @"需要包含 ⌘ 或 ⌃。";
        return nil;
    }
    BOOL saved = [self.delegate recordShortcutForAction:self.recordingAction keyCode:event.keyCode modifierFlags:flags];
    [self endRecordingWithError:saved ? nil : @"这个快捷键已被占用。"];
    return nil;
}

- (void)windowDidResignKey:(NSNotification *)notification {
    if (self.recordingAction) [self endRecordingWithError:nil];
}

- (void)windowWillClose:(NSNotification *)notification {
    [self.delegate settingsPanelDidClose:self];
}

@end
