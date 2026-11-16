#import "SettingsPanel.h"
#import "Theme.h"
#import <Carbon/Carbon.h>

static NSString *const ThemeKey = @"AppearanceTheme";

@interface SettingsRootView : HMSurfaceView
@property (copy) void (^appearanceChanged)(void);
@end
@implementation SettingsRootView
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    if (self.appearanceChanged) self.appearanceChanged();
}
@end

@interface SettingsPanel () <NSWindowDelegate>
@property NSWindow *window;
@property NSPopUpButton *themePicker;
@property HMPanelStyle *panelStyle;
@property NSPopUpButton *palettePicker;
@property NSColorWell *colorWell;
@property NSSlider *transparencySlider;
@property NSTextField *transparencyLabel;
@property NSButton *blurToggle;
@property NSDictionary<NSNumber *, NSButton *> *shortcutButtons;
@property NSArray<NSButton *> *toolButtons;
@property NSArray<NSButton *> *preferenceButtons;
@property NSTextField *statusLabel;
@property id keyMonitor;
@property HandyMinisShortcut recordingAction;
@end

@implementation SettingsPanel

+ (void)applySavedTheme {
    [self applyTheme:[NSUserDefaults.standardUserDefaults integerForKey:ThemeKey]];
}

+ (void)applyTheme:(HandyMinisTheme)theme {
    switch (theme) {
        case HandyMinisThemeLight: NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua]; break;
        case HandyMinisThemeDark: NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]; break;
        default: NSApp.appearance = nil; break;
    }
    // Hidden panels can retain their previous effective appearance until shown.
    // Refresh them as well; nil restores the system's live appearance updates.
    for (NSWindow *window in NSApp.windows) window.appearance = NSApp.appearance;
}

- (instancetype)init {
    return [self initWithPanelStyle:HMPanelStyle.sharedStyle];
}

- (instancetype)initWithPanelStyle:(HMPanelStyle *)style {
    if ((self = [super init])) {
        _panelStyle = style;
        _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, 500)
                                               styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                 backing:NSBackingStoreBuffered defer:NO];
        _window.title = @"HandyMinis 设置";
        _window.delegate = self;
        _window.releasedWhenClosed = NO;
        [self buildContent];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(panelStyleChanged:)
            name:HMPanelStyleDidChangeNotification object:style];
        [self refreshPanelStyle];
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
    [NSNotificationCenter.defaultCenter removeObserver:self];
    if (_keyMonitor) [NSEvent removeMonitor:_keyMonitor];
}

- (void)addRowWithTitle:(NSString *)title control:(NSView *)control toStack:(NSStackView *)stack {
    NSTextField *label = [NSTextField labelWithString:title];
    NSView *spacer = [NSView new];
    NSStackView *row = [NSStackView stackViewWithViews:@[label, spacer, control]];
    [stack addArrangedSubview:row];
    [row.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    [control.widthAnchor constraintEqualToConstant:220].active = YES;
}

- (void)buildContent {
    SettingsRootView *content = [[SettingsRootView alloc] initWithFrame:self.window.contentView.bounds];
    content.fillColor = HMTheme.canvas;
    content.strokeColor = nil;
    content.radius = 0;
    self.window.contentView = content;
    __weak SettingsPanel *weakSelf = self;
    content.appearanceChanged = ^{ [weakSelf refreshPanelStyle]; };
    HMSurfaceView *card = [HMSurfaceView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:card];
    NSStackView *stack = [NSStackView new];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];

    self.themePicker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.themePicker.bordered = NO;
    [self.themePicker addItemsWithTitles:@[@"跟随系统", @"浅色", @"深色"]];
    self.themePicker.target = self;
    self.themePicker.action = @selector(changeTheme:);
    [self addRowWithTitle:@"外观" control:self.themePicker toStack:stack];

    self.palettePicker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.palettePicker.bordered = NO;
    [self.palettePicker addItemsWithTitles:@[@"系统默认", @"雾蓝", @"薄荷", @"暖沙", @"自定义"]];
    self.palettePicker.target = self;
    self.palettePicker.action = @selector(changePanelPalette:);
    [self.palettePicker setAccessibilityLabel:@"面板配色"];
    self.colorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 40, 24)];
    self.colorWell.colorWellStyle = NSColorWellStyleMinimal;
    self.colorWell.target = self;
    self.colorWell.action = @selector(changePanelColor:);
    self.colorWell.toolTip = @"自定义当前浅色或深色模式的面板颜色";
    [self.colorWell setAccessibilityLabel:@"自定义面板颜色"];
    NSStackView *palette = [NSStackView stackViewWithViews:@[self.palettePicker, self.colorWell]];
    palette.spacing = 8;
    palette.distribution = NSStackViewDistributionFill;
    [self.palettePicker setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.colorWell.widthAnchor constraintEqualToConstant:40].active = YES;
    [self.colorWell.heightAnchor constraintEqualToConstant:24].active = YES;
    [self addRowWithTitle:@"面板颜色" control:palette toStack:stack];

    self.transparencySlider = [NSSlider sliderWithValue:0 minValue:0 maxValue:80 target:self action:@selector(changePanelTransparency:)];
    self.transparencySlider.continuous = YES;
    [self.transparencySlider setAccessibilityLabel:@"面板透明度"];
    self.transparencySlider.toolTip = @"0% 为不透明；只调整背景，文字保持清晰";
    self.transparencyLabel = [NSTextField labelWithString:@"0%"];
    self.transparencyLabel.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    self.transparencyLabel.alignment = NSTextAlignmentRight;
    [self.transparencyLabel.widthAnchor constraintEqualToConstant:40].active = YES;
    NSStackView *transparency = [NSStackView stackViewWithViews:@[self.transparencySlider, self.transparencyLabel]];
    transparency.spacing = 8;
    [self addRowWithTitle:@"面板透明度" control:transparency toStack:stack];

    self.blurToggle = [NSButton checkboxWithTitle:@"背景模糊" target:self action:@selector(changePanelBlur:)];
    self.blurToggle.toolTip = @"透明背景下柔化后面的内容；遵循系统的减少透明度设置";
    NSButton *reset = [NSButton buttonWithTitle:@"恢复面板默认外观" target:self action:@selector(resetPanelStyle:)];
    reset.bezelStyle = NSBezelStyleRecessed;
    reset.showsBorderOnlyWhileMouseInside = YES;
    NSStackView *appearanceActions = [NSStackView stackViewWithViews:@[self.blurToggle, [NSView new], reset]];
    [stack addArrangedSubview:appearanceActions];
    [appearanceActions.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    NSTextField *hint = [NSTextField labelWithString:@"实时生效并保存，浅色与深色可分别设置自定义颜色。"];
    hint.font = [NSFont systemFontOfSize:11];
    hint.textColor = NSColor.secondaryLabelColor;
    [stack addArrangedSubview:hint];
    [stack setCustomSpacing:24 afterView:hint];


    NSTextField *toolsLabel = [NSTextField labelWithString:@"工具"];
    toolsLabel.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
    [stack addArrangedSubview:toolsLabel];

    NSArray<NSNumber *> *actions = @[@(HandyMinisShortcutQueue), @(HandyMinisShortcutScreenshot)];
    NSArray<NSString *> *titles = @[@"剪贴板", @"框选截图"];
    NSArray<NSString *> *shortcutLabels = @[@"打开剪贴板", @"框选截图"];
    NSMutableDictionary<NSNumber *, NSButton *> *shortcuts = [NSMutableDictionary dictionary];
    NSMutableArray<NSButton *> *toolButtons = [NSMutableArray array];
    [actions enumerateObjectsUsingBlock:^(NSNumber *action, NSUInteger index, BOOL *stop) {
        NSButton *toggle = [NSButton checkboxWithTitle:titles[index] target:self action:@selector(toolClicked:)];
        toggle.tag = action.integerValue;
        [toolButtons addObject:toggle];

        NSButton *shortcut = [NSButton buttonWithTitle:@"" target:self action:@selector(recordClicked:)];
        shortcut.bezelStyle = NSBezelStyleRecessed;
        shortcut.showsBorderOnlyWhileMouseInside = YES;
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
    tiling.tag = HandyMinisPreferenceTiling;
    [stack addArrangedSubview:tiling];

    self.statusLabel = [NSTextField labelWithString:@""];
    self.statusLabel.font = [NSFont systemFontOfSize:12];
    [stack addArrangedSubview:self.statusLabel];
    [self.statusLabel.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;

    [stack setCustomSpacing:24 afterView:self.statusLabel];

    NSMutableArray<NSButton *> *preferences = [NSMutableArray arrayWithObject:tiling];
    NSArray<NSString *> *preferenceTitles = @[@"登录时启动", @"发送匿名使用统计"];
    [preferenceTitles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger index, BOOL *stop) {
        if (index == HandyMinisPreferenceAnalytics && ![[NSBundle.mainBundle objectForInfoDictionaryKey:@"AptabaseAppKey"] length]) return;
        NSButton *button = [NSButton checkboxWithTitle:title target:self action:@selector(preferenceClicked:)];
        button.tag = index;
        [stack addArrangedSubview:button];
        [preferences addObject:button];
    }];
    self.preferenceButtons = preferences;

    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [card.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [card.topAnchor constraintEqualToAnchor:content.topAnchor constant:20],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18],
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:18],
        [card.bottomAnchor constraintEqualToAnchor:stack.bottomAnchor constant:18],
    ]];
    [content layoutSubtreeIfNeeded];
    [self.window setContentSize:NSMakeSize(500, ceil(card.fittingSize.height) + 40)];
}

- (void)changeTheme:(NSPopUpButton *)sender {
    [NSUserDefaults.standardUserDefaults setInteger:sender.indexOfSelectedItem forKey:ThemeKey];
    [SettingsPanel applySavedTheme];
    [self refreshPanelStyle];
}

- (void)panelStyleChanged:(NSNotification *)note { [self refreshPanelStyle]; }

- (void)refreshPanelStyle {
    [self.palettePicker selectItemAtIndex:self.panelStyle.palette];
    self.colorWell.color = [self.panelStyle colorForAppearance:self.window.effectiveAppearance];
    self.transparencySlider.doubleValue = self.panelStyle.transparency;
    self.transparencyLabel.stringValue = [NSString stringWithFormat:@"%.0f%%", self.panelStyle.transparency];
    self.blurToggle.state = self.panelStyle.blur ? NSControlStateValueOn : NSControlStateValueOff;
    self.blurToggle.enabled = self.panelStyle.transparency > 0;
}

- (void)changePanelPalette:(NSPopUpButton *)sender { self.panelStyle.palette = sender.indexOfSelectedItem; }
- (void)changePanelColor:(NSColorWell *)sender {
    [self.panelStyle setCustomColor:sender.color forAppearance:self.window.effectiveAppearance];
}
- (void)changePanelTransparency:(NSSlider *)sender { self.panelStyle.transparency = sender.doubleValue; }
- (void)changePanelBlur:(NSButton *)sender { self.panelStyle.blur = sender.state == NSControlStateValueOn; }
- (void)resetPanelStyle:(id)sender { [self.panelStyle reset]; }

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
    [self refreshPanelStyle];
    [self endRecordingWithError:nil];
    [self refreshPreferences];
    [self refreshTools];
    NSInteger theme = [NSUserDefaults.standardUserDefaults integerForKey:ThemeKey];
    [self.themePicker selectItemAtIndex:theme >= HandyMinisThemeSystem && theme <= HandyMinisThemeDark ? theme : HandyMinisThemeSystem];
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
        HandyMinisShortcut action = key.integerValue;
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

- (BOOL)handleRegisteredShortcut:(HandyMinisShortcut)action {
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
