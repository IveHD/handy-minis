#import "AppController.h"
#import "Analytics.h"
#import <Sparkle/Sparkle.h>
#import "AccessibilityTrust.h"
#import "ClipboardStore.h"
#import "QueuePanel.h"
#import "SettingsPanel.h"
#import "ScreenshotBridge.h"
#import "WindowTiling.h"
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>
#import <ServiceManagement/ServiceManagement.h>

static OSStatus HotkeyHandler(EventHandlerCallRef next, EventRef event, void *userData);
static const OSType DeskKitHotkeySignature = 'CQUE';
static NSString *const WindowTilingDisabledKey = @"WindowTilingDisabled";
enum {
    QueueMenuTag = 10, ScreenshotMenuTag, ClearHistoryMenuTag, HistoryCountMenuTag, HistorySeparatorMenuTag,
};

typedef struct {
    __unsafe_unretained NSString *disabledKey;
    __unsafe_unretained NSString *codeKey;
    __unsafe_unretained NSString *modifiersKey;
    UInt32 defaultCode;
    UInt32 defaultModifiers;
} ToolConfiguration;

typedef struct {
    UInt32 code;
    UInt32 modifiers;
    EventHotKeyRef reference;
} ToolShortcut;

static const ToolConfiguration Tools[] = {
    [DeskKitShortcutQueue] = {@"CopyQueueDisabled", @"CopyQueueHotKeyCode", @"CopyQueueHotKeyModifiers", kVK_ANSI_C, cmdKey | shiftKey},
    [DeskKitShortcutScreenshot] = {@"ScreenshotDisabled", @"ScreenshotHotKeyCode", @"ScreenshotHotKeyModifiers", kVK_ANSI_A, controlKey | cmdKey},
};

static void PostCommandVToPid(pid_t pid) {
    if (pid <= 0) return;
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    if (source) CGEventSourceSetLocalEventsSuppressionInterval(source, 0);
    CGEventRef commandDown = CGEventCreateKeyboardEvent(source, (CGKeyCode)kVK_Command, true);
    CGEventRef down = CGEventCreateKeyboardEvent(source, (CGKeyCode)kVK_ANSI_V, true);
    CGEventRef up = CGEventCreateKeyboardEvent(source, (CGKeyCode)kVK_ANSI_V, false);
    CGEventRef commandUp = CGEventCreateKeyboardEvent(source, (CGKeyCode)kVK_Command, false);
    if (commandDown && down && up && commandUp) {
        CGEventSetFlags(down, kCGEventFlagMaskCommand);
        CGEventSetFlags(up, kCGEventFlagMaskCommand);
        CGEventPostToPid(pid, commandDown);
        CGEventPostToPid(pid, down);
        CGEventPostToPid(pid, up);
        CGEventPostToPid(pid, commandUp);
    }
    if (commandDown) CFRelease(commandDown);
    if (down) CFRelease(down);
    if (up) CFRelease(up);
    if (commandUp) CFRelease(commandUp);
    if (source) CFRelease(source);
}

static BOOL AXTitleIs(AXUIElementRef element, CFStringRef expected) {
    CFTypeRef title = NULL;
    if (AXUIElementCopyAttributeValue(element, kAXTitleAttribute, &title) != kAXErrorSuccess || !title) return NO;
    BOOL match = CFGetTypeID(title) == CFStringGetTypeID() && CFStringCompare((CFStringRef)title, expected, 0) == kCFCompareEqualTo;
    CFRelease(title);
    return match;
}

static BOOL AXEnabled(AXUIElementRef element) {
    CFTypeRef enabled = NULL;
    if (AXUIElementCopyAttributeValue(element, kAXEnabledAttribute, &enabled) != kAXErrorSuccess || !enabled) return YES;
    BOOL value = CFGetTypeID(enabled) != CFBooleanGetTypeID() || CFBooleanGetValue((CFBooleanRef)enabled);
    CFRelease(enabled);
    return value;
}

// Plain Paste is Command-V. Command is implicit in the menu-item modifier mask.
static BOOL IsPlainPasteItem(AXUIElementRef item) {
    CFTypeRef cmd = NULL;
    if (AXUIElementCopyAttributeValue(item, kAXMenuItemCmdCharAttribute, &cmd) == kAXErrorSuccess && cmd) {
        BOOL isV = NO;
        if (CFGetTypeID(cmd) == CFStringGetTypeID() && CFStringGetLength((CFStringRef)cmd) > 0) {
            UniChar ch = CFStringGetCharacterAtIndex((CFStringRef)cmd, 0);
            isV = ch == 'V' || ch == 'v';
        }
        CFRelease(cmd);
        if (isV) {
            int mods = 0;
            CFTypeRef modsValue = NULL;
            if (AXUIElementCopyAttributeValue(item, kAXMenuItemCmdModifiersAttribute, &modsValue) == kAXErrorSuccess && modsValue) {
                if (CFGetTypeID(modsValue) == CFNumberGetTypeID()) {
                    CFNumberGetValue((CFNumberRef)modsValue, kCFNumberIntType, &mods);
                }
                CFRelease(modsValue);
            }
            return mods == kAXMenuItemModifierNone;
        }
    }
    return AXTitleIs(item, CFSTR("粘贴")) || AXTitleIs(item, CFSTR("貼上")) || AXTitleIs(item, CFSTR("Paste"));
}

typedef BOOL (^PasteCheck)(void);

static BOOL PressPasteInElement(AXUIElementRef element, int depth, PasteCheck isCurrent, PasteCheck canPress) {
    if (!element || depth > 5 || !isCurrent()) return NO;
    AXUIElementSetMessagingTimeout(element, 0.2);
    CFTypeRef role = NULL;
    if (AXUIElementCopyAttributeValue(element, kAXRoleAttribute, &role) != kAXErrorSuccess || !role) return NO;
    BOOL isItem = CFEqual(role, kAXMenuItemRole);
    BOOL descend = CFEqual(role, kAXMenuBarRole) || CFEqual(role, kAXMenuBarItemRole) || CFEqual(role, kAXMenuRole);
    CFRelease(role);
    if (isItem && IsPlainPasteItem(element) && AXEnabled(element) && canPress()) {
        if (AXUIElementPerformAction(element, kAXPressAction) == kAXErrorSuccess) return YES;
    }
    if (!descend) return NO;
    CFArrayRef children = NULL;
    if (AXUIElementCopyAttributeValue(element, kAXChildrenAttribute, (CFTypeRef *)&children) != kAXErrorSuccess || !children) return NO;
    BOOL pressed = NO;
    CFIndex count = CFArrayGetCount(children);
    for (CFIndex i = 0; i < count && !pressed && isCurrent(); i++) {
        pressed = PressPasteInElement((AXUIElementRef)CFArrayGetValueAtIndex(children, i), depth + 1, isCurrent, canPress);
    }
    CFRelease(children);
    return pressed;
}

static BOOL PressPasteMenu(pid_t pid, PasteCheck isCurrent, PasteCheck canPress) {
    if (pid <= 0 || !isCurrent() || !DeskKitAccessibilityTrusted()) return NO;
    AXUIElementRef app = AXUIElementCreateApplication(pid);
    if (!app) return NO;
    AXUIElementSetMessagingTimeout(app, 0.25);
    AXUIElementRef menuBar = NULL;
    AXError err = AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute, (CFTypeRef *)&menuBar);
    if (err != kAXErrorSuccess || !menuBar) {
        CFRelease(app);
        return NO;
    }
    AXUIElementSetMessagingTimeout(menuBar, 0.25);
    CFArrayRef top = NULL;
    BOOL pressed = NO;
    if (AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute, (CFTypeRef *)&top) == kAXErrorSuccess && top) {
        CFIndex count = CFArrayGetCount(top);
        for (CFIndex i = 0; i < count && !pressed && isCurrent(); i++) {
            AXUIElementRef item = (AXUIElementRef)CFArrayGetValueAtIndex(top, i);
            if (AXTitleIs(item, CFSTR("编辑")) || AXTitleIs(item, CFSTR("編輯")) || AXTitleIs(item, CFSTR("Edit"))) {
                pressed = PressPasteInElement(item, 0, isCurrent, canPress);
            }
        }
        if (!pressed) {
            for (CFIndex i = 0; i < count && !pressed && isCurrent(); i++) {
                pressed = PressPasteInElement((AXUIElementRef)CFArrayGetValueAtIndex(top, i), 0, isCurrent, canPress);
            }
        }
        CFRelease(top);
    }
    CFRelease(menuBar);
    CFRelease(app);
    return pressed;
}

static void OpenAccessibilitySettings(void) {
    NSArray<NSString *> *candidates = @[
        @"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        @"x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
    ];
    for (NSString *raw in candidates) {
        NSURL *url = [NSURL URLWithString:raw];
        if (url && [NSWorkspace.sharedWorkspace openURL:url]) return;
    }
}

@interface AppController () <QueuePanelDelegate, SettingsPanelDelegate, NSMenuDelegate> {
    ToolShortcut _shortcuts[sizeof(Tools) / sizeof(Tools[0])];
}
@property SPUStandardUpdaterController *updaterController;
@property ClipboardStore *store;
@property QueuePanel *panel;
@property SettingsPanel *settings;
@property WindowTiling *windowTiling;
@property NSMenu *layoutMenu;
@property BOOL layoutOperationPending;
@property NSStatusItem *statusItem;
@property NSTimer *timer;
@property NSInteger lastChangeCount;
@property NSRunningApplication *previousApp;
@property (atomic) NSUInteger pasteGeneration;
@property (nonatomic, strong) dispatch_queue_t pasteQueue;
@property EventHandlerRef hotkeyHandler;
@end

@implementation AppController

+ (instancetype)shared {
    static AppController *controller;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        controller = [AppController new];
    });
    return controller;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    if ([self handOffToExistingInstance]) exit(0);

    [SettingsPanel applySavedTheme];
    self.pasteQueue = dispatch_queue_create("local.handong.DeskKit.paste", DISPATCH_QUEUE_SERIAL);
    self.store = [ClipboardStore new];
    [self.store load];
    self.panel = [[QueuePanel alloc] initWithStore:self.store];
    self.panel.delegate = self;
    self.settings = [SettingsPanel new];
    self.settings.delegate = self;
    self.lastChangeCount = NSPasteboard.generalPasteboard.changeCount;
    if ([self toolIsEnabledForAction:DeskKitShortcutQueue]) {
        [self.store ingestPasteboard:NSPasteboard.generalPasteboard];
        [self startMonitoring];
    }
    if ([NSBundle.mainBundle objectForInfoDictionaryKey:@"SUFeedURL"]) {
        self.updaterController = [[SPUStandardUpdaterController alloc] initWithStartingUpdater:YES updaterDelegate:nil userDriverDelegate:nil];
    }
    [Analytics track:@"app_started"];
    self.windowTiling = [WindowTiling new];
    if ([self isPreferenceEnabled:DeskKitPreferenceTiling]) [self.windowTiling start];
    [self loadShortcuts];
    [self registerHotkeys];
    [self installStatusItem];

    [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                        selector:@selector(showPanel)
                                                            name:@"local.handong.ClipStack.show"
                                                          object:nil];
    fprintf(stdout, "DeskKit 已启动。快捷键 %s。自动粘贴: %s。历史目录: %s\n",
            [self shortcutTitle].UTF8String,
            DeskKitAccessibilityTrusted() ? "可用" : "不可用",
            self.store.supportDirectoryPath.UTF8String);
    fflush(stdout);

    if ([NSProcessInfo.processInfo.arguments containsObject:@"--show"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self showPanel];
        });
    }
}

- (BOOL)handOffToExistingInstance {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"local.handong.ClipStack";
    for (NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleID]) {
        if (app.processIdentifier != getpid()) {
            [[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"local.handong.ClipStack.show"
                                                                           object:nil
                                                                         userInfo:nil
                                                               deliverImmediately:YES];
            return YES;
        }
    }
    return NO;
}

#pragma mark - Menu

- (void)installStatusItem {
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    NSImage *image = [NSImage imageNamed:@"StatusIconTemplate"];
    image.accessibilityDescription = @"DeskKit";
    image.template = YES;
    self.statusItem.button.image = image;
    self.statusItem.menu = [self buildMenu];
}

- (NSMenu *)buildMenu {
    NSMenu *menu = [NSMenu new];
    menu.delegate = self;
    NSMenuItem *queue = [menu addItemWithTitle:@"打开剪贴板" action:@selector(showPanel) keyEquivalent:@""];
    queue.target = self;
    queue.tag = QueueMenuTag;
    NSMenuItem *screenshot = [menu addItemWithTitle:@"框选截图" action:@selector(startScreenshot) keyEquivalent:@""];
    screenshot.target = self;
    screenshot.tag = ScreenshotMenuTag;
    NSMenuItem *layouts = [menu addItemWithTitle:@"窗口布局" action:nil keyEquivalent:@""];
    self.layoutMenu = [NSMenu new];
    self.layoutMenu.delegate = self;
    self.layoutMenu.autoenablesItems = NO;
    layouts.submenu = self.layoutMenu;
    [self menuNeedsUpdate:self.layoutMenu];
    [menu addItemWithTitle:@"设置…" action:@selector(showSettings:) keyEquivalent:@""].target = self;
    if (self.updaterController) {
        [menu addItemWithTitle:@"检查更新…" action:@selector(checkForUpdates:) keyEquivalent:@""].target = self.updaterController;
    }
    NSMenuItem *access = [[NSMenuItem alloc] initWithTitle:@"授权辅助功能…" action:@selector(openAccessibility:) keyEquivalent:@""];
    access.target = self;
    access.tag = 4;
    access.hidden = YES;
    [menu addItem:access];
    NSMenuItem *count = [[NSMenuItem alloc] initWithTitle:@"已保存 0 条" action:nil keyEquivalent:@""];
    count.enabled = NO;
    count.tag = HistoryCountMenuTag;
    [menu addItem:count];
    NSMenuItem *historySeparator = [NSMenuItem separatorItem];
    historySeparator.tag = HistorySeparatorMenuTag;
    [menu addItem:historySeparator];
    NSMenuItem *clear = [menu addItemWithTitle:@"清空历史…" action:@selector(confirmClear:) keyEquivalent:@""];
    clear.target = self;
    clear.tag = ClearHistoryMenuTag;
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"退出" action:@selector(terminate:) keyEquivalent:@""].target = NSApp;
    return menu;
}

- (void)toggleAnalytics:(id)sender {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:![defaults boolForKey:@"AnalyticsDisabled"] forKey:@"AnalyticsDisabled"];
}

- (void)openAccessibility:(id)sender {
    OpenAccessibilitySettings();
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    if (menu != self.layoutMenu) return;
    [menu removeAllItems];
    NSMenuItem *save = [menu addItemWithTitle:@"保存当前布局…" action:@selector(saveWindowLayout:) keyEquivalent:@""];
    save.target = self;
    save.enabled = !self.layoutOperationPending;
    NSArray<NSString *> *names = [self.windowTiling layoutNames];
    if (!names.count) return;
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenu *remove = [NSMenu new];
    for (NSString *name in names) {
        NSMenuItem *restore = [menu addItemWithTitle:name action:@selector(restoreWindowLayout:) keyEquivalent:@""];
        restore.target = self;
        restore.enabled = !self.layoutOperationPending;
        NSMenuItem *delete = [remove addItemWithTitle:name action:@selector(deleteWindowLayout:) keyEquivalent:@""];
        delete.target = self;
        delete.enabled = !self.layoutOperationPending;
    }
    NSMenuItem *delete = [menu addItemWithTitle:@"删除布局" action:nil keyEquivalent:@""];
    delete.submenu = remove;
    remove.autoenablesItems = NO;
}

- (void)menuWillOpen:(NSMenu *)menu {
    if (menu == self.layoutMenu) return;
    [self rememberFrontApp];
    NSArray<NSNumber *> *actions = @[@(DeskKitShortcutQueue), @(DeskKitShortcutScreenshot)];
    for (NSNumber *value in actions) {
        DeskKitShortcut action = value.integerValue;
        BOOL queue = action == DeskKitShortcutQueue;
        NSMenuItem *item = [menu itemWithTag:queue ? QueueMenuTag : ScreenshotMenuTag];
        item.hidden = ![self toolIsEnabledForAction:action];
        NSString *title = queue ? @"打开剪贴板" : @"框选截图";
        if (_shortcuts[action].reference) {
            title = [NSString stringWithFormat:@"%@  %@", title, [self shortcutTitleForAction:action]];
        }
        item.title = title;
    }
    BOOL queueEnabled = [self toolIsEnabledForAction:DeskKitShortcutQueue];
    [menu itemWithTag:ClearHistoryMenuTag].hidden = !queueEnabled;
    [menu itemWithTag:HistorySeparatorMenuTag].hidden = !queueEnabled;
    NSMenuItem *count = [menu itemWithTag:HistoryCountMenuTag];
    count.hidden = !queueEnabled;
    count.title = [NSString stringWithFormat:@"已保存 %lu 条", (unsigned long)self.store.items.count];
    [menu itemWithTag:4].hidden = DeskKitAccessibilityTrusted();
}

- (void)showToolMessage:(NSString *)title detail:(NSString *)detail {
    NSAlert *alert = [NSAlert new];
    alert.messageText = title;
    alert.informativeText = detail;
    [NSApp activate];
    [alert runModal];
}

- (void)saveWindowLayout:(id)sender {
    if (self.layoutOperationPending || DeskKitScreenshotIsActive()) return;
    if (!DeskKitAccessibilityTrusted()) { DeskKitPromptAccessibility(); return; }

    NSAlert *alert = [NSAlert new];
    alert.messageText = @"保存当前窗口布局";
    alert.informativeText = @"记录当前桌面上可移动窗口的位置和大小。";
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
    field.placeholderString = @"布局名称";
    alert.accessoryView = field;
    [alert addButtonWithTitle:@"保存"];
    [alert addButtonWithTitle:@"取消"];
    alert.window.initialFirstResponder = field;
    [NSApp activate];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSString *name = [field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!name.length) return;
    if ([[self.windowTiling layoutNames] containsObject:name]) {
        NSAlert *replace = [NSAlert new];
        replace.messageText = [NSString stringWithFormat:@"替换布局「%@」？", name];
        [replace addButtonWithTitle:@"替换"];
        [replace addButtonWithTitle:@"取消"];
        if ([replace runModal] != NSAlertFirstButtonReturn) return;
    }
    self.layoutOperationPending = YES;
    [self.windowTiling saveLayoutNamed:name completion:^(NSUInteger count) {
        self.layoutOperationPending = NO;
        if (!count) [self showToolMessage:@"未保存窗口布局" detail:@"当前桌面上没有找到可移动和调整大小的窗口。"];
    }];
}

- (void)restoreWindowLayout:(NSMenuItem *)sender {
    if (self.layoutOperationPending || DeskKitScreenshotIsActive()) return;
    if (!DeskKitAccessibilityTrusted()) { DeskKitPromptAccessibility(); return; }

    self.layoutOperationPending = YES;
    [self.windowTiling restoreLayoutNamed:sender.title completion:^(NSUInteger restored, NSUInteger total) {
        self.layoutOperationPending = NO;
        if (restored == total) return;
        NSString *detail = [NSString stringWithFormat:@"已恢复 %lu/%lu 个窗口。请在当前桌面打开对应窗口后重试。",
            (unsigned long)restored, (unsigned long)total];
        [self showToolMessage:@"部分窗口无法恢复" detail:detail];
    }];
}

- (void)deleteWindowLayout:(NSMenuItem *)sender {
    if (self.layoutOperationPending) return;
    NSAlert *alert = [NSAlert new];
    alert.messageText = [NSString stringWithFormat:@"删除布局「%@」？", sender.title];
    [alert addButtonWithTitle:@"删除"];
    [alert addButtonWithTitle:@"取消"];
    [NSApp activate];
    if ([alert runModal] == NSAlertFirstButtonReturn) [self.windowTiling deleteLayoutNamed:sender.title];
}

- (BOOL)isPreferenceEnabled:(DeskKitPreference)preference {
    switch (preference) {
        case DeskKitPreferenceLaunchAtLogin: return SMAppService.mainAppService.status == SMAppServiceStatusEnabled;
        case DeskKitPreferenceTiling: return ![NSUserDefaults.standardUserDefaults boolForKey:WindowTilingDisabledKey];
        case DeskKitPreferenceAnalytics: return ![NSUserDefaults.standardUserDefaults boolForKey:@"AnalyticsDisabled"];
    }
    return NO;
}

- (void)togglePreference:(DeskKitPreference)preference {
    switch (preference) {
        case DeskKitPreferenceLaunchAtLogin: [self toggleLaunchAtLogin:nil]; break;
        case DeskKitPreferenceAnalytics: [self toggleAnalytics:nil]; break;
        case DeskKitPreferenceTiling: {
            BOOL enabled = ![self isPreferenceEnabled:preference];
            [NSUserDefaults.standardUserDefaults setBool:!enabled forKey:WindowTilingDisabledKey];
            if (enabled) {
                [self.windowTiling start];
                if (!DeskKitAccessibilityTrusted()) OpenAccessibilitySettings();
            } else {
                [self.windowTiling stop];
            }
            break;
        }
    }
}

- (void)confirmClear:(id)sender {
    if (![self toolIsEnabledForAction:DeskKitShortcutQueue]) return;
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"清空全部复制历史？";
    alert.informativeText = @"系统剪切板里当前的内容会保留。";
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"清空"];
    [alert addButtonWithTitle:@"取消"];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [self.store clear];
    }
}

- (void)toggleLaunchAtLogin:(id)sender {
    SMAppService *service = SMAppService.mainAppService;
    NSError *error = nil;
    BOOL ok = service.status == SMAppServiceStatusEnabled
        ? [service unregisterAndReturnError:&error]
        : [service registerAndReturnError:&error];
    if (!ok && error) {
        [NSApp activateIgnoringOtherApps:YES];
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"无法更改登录时启动";
        alert.informativeText = error.localizedDescription;
        [alert runModal];
    }
}

#pragma mark - Hotkey and pasteboard

static NSString *HotkeyKeyName(UInt32 keyCode) {
    switch (keyCode) {
        case kVK_ANSI_A: return @"A"; case kVK_ANSI_B: return @"B"; case kVK_ANSI_C: return @"C";
        case kVK_ANSI_D: return @"D"; case kVK_ANSI_E: return @"E"; case kVK_ANSI_F: return @"F";
        case kVK_ANSI_G: return @"G"; case kVK_ANSI_H: return @"H"; case kVK_ANSI_I: return @"I";
        case kVK_ANSI_J: return @"J"; case kVK_ANSI_K: return @"K"; case kVK_ANSI_L: return @"L";
        case kVK_ANSI_M: return @"M"; case kVK_ANSI_N: return @"N"; case kVK_ANSI_O: return @"O";
        case kVK_ANSI_P: return @"P"; case kVK_ANSI_Q: return @"Q"; case kVK_ANSI_R: return @"R";
        case kVK_ANSI_S: return @"S"; case kVK_ANSI_T: return @"T"; case kVK_ANSI_U: return @"U";
        case kVK_ANSI_V: return @"V"; case kVK_ANSI_W: return @"W"; case kVK_ANSI_X: return @"X";
        case kVK_ANSI_Y: return @"Y"; case kVK_ANSI_Z: return @"Z";
        case kVK_ANSI_0: return @"0"; case kVK_ANSI_1: return @"1"; case kVK_ANSI_2: return @"2";
        case kVK_ANSI_3: return @"3"; case kVK_ANSI_4: return @"4"; case kVK_ANSI_5: return @"5";
        case kVK_ANSI_6: return @"6"; case kVK_ANSI_7: return @"7"; case kVK_ANSI_8: return @"8";
        case kVK_ANSI_9: return @"9";
        case kVK_Space: return @"空格";
        case kVK_Return: return @"↩";
        case kVK_Tab: return @"⇥";
        case kVK_Delete: return @"⌫";
        case kVK_Escape: return @"esc";
        case kVK_LeftArrow: return @"←";
        case kVK_RightArrow: return @"→";
        case kVK_UpArrow: return @"↑";
        case kVK_DownArrow: return @"↓";
        case kVK_F1: return @"F1"; case kVK_F2: return @"F2"; case kVK_F3: return @"F3";
        case kVK_F4: return @"F4"; case kVK_F5: return @"F5"; case kVK_F6: return @"F6";
        case kVK_F7: return @"F7"; case kVK_F8: return @"F8"; case kVK_F9: return @"F9";
        case kVK_F10: return @"F10"; case kVK_F11: return @"F11"; case kVK_F12: return @"F12";
        default: return [NSString stringWithFormat:@"键%u", keyCode];
    }
}

static UInt32 CarbonModifiersFromFlags(NSEventModifierFlags flags) {
    UInt32 modifiers = 0;
    if (flags & NSEventModifierFlagCommand) modifiers |= cmdKey;
    if (flags & NSEventModifierFlagShift) modifiers |= shiftKey;
    if (flags & NSEventModifierFlagOption) modifiers |= optionKey;
    if (flags & NSEventModifierFlagControl) modifiers |= controlKey;
    return modifiers;
}

- (void)loadShortcuts {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    ToolConfiguration queue = Tools[DeskKitShortcutQueue];
    if (![defaults objectForKey:queue.codeKey]) {
        NSString *legacy = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences/local.handong.CopyQueue.plist"];
        NSDictionary *old = [NSDictionary dictionaryWithContentsOfFile:legacy];
        if (old[queue.codeKey] && old[queue.modifiersKey]) {
            [defaults setObject:old[queue.codeKey] forKey:queue.codeKey];
            [defaults setObject:old[queue.modifiersKey] forKey:queue.modifiersKey];
        }
    }
    for (DeskKitShortcut action = DeskKitShortcutQueue; action <= DeskKitShortcutScreenshot; action++) {
        ToolConfiguration config = Tools[action];
        _shortcuts[action].code = [defaults objectForKey:config.codeKey]
            ? (UInt32)[defaults integerForKey:config.codeKey] : config.defaultCode;
        _shortcuts[action].modifiers = [defaults objectForKey:config.modifiersKey]
            ? (UInt32)[defaults integerForKey:config.modifiersKey] : config.defaultModifiers;
    }
}

- (NSString *)shortcutTitle {
    return [self shortcutTitleForAction:DeskKitShortcutQueue];
}

- (NSString *)shortcutTitleForAction:(DeskKitShortcut)action {
    UInt32 modifiers = _shortcuts[action].modifiers;
    UInt32 code = _shortcuts[action].code;
    if (!modifiers) return @"未设置";
    NSMutableString *title = [NSMutableString string];
    if (modifiers & controlKey) [title appendString:@"⌃"];
    if (modifiers & optionKey) [title appendString:@"⌥"];
    if (modifiers & cmdKey) [title appendString:@"⌘"];
    if (modifiers & shiftKey) [title appendString:@"⇧"];
    [title appendString:HotkeyKeyName(code)];
    return title;
}

static EventHotKeyRef RegisterShortcut(DeskKitShortcut action, UInt32 code, UInt32 modifiers) {
    EventHotKeyID hotkey = {DeskKitHotkeySignature, (UInt32)action};
    EventHotKeyRef reference = NULL;
    OSStatus result = RegisterEventHotKey(code, modifiers, hotkey, GetApplicationEventTarget(), kEventHotKeyExclusive, &reference);
    return result == noErr ? reference : NULL;
}

- (BOOL)toolIsEnabledForAction:(DeskKitShortcut)action {
    return ![NSUserDefaults.standardUserDefaults boolForKey:Tools[action].disabledKey];
}

- (void)updateShortcutRegistrationForAction:(DeskKitShortcut)action {
    ToolShortcut *shortcut = &_shortcuts[action];
    if ([self toolIsEnabledForAction:action] && shortcut->modifiers) {
        if (self.hotkeyHandler && !shortcut->reference) {
            shortcut->reference = RegisterShortcut(action, shortcut->code, shortcut->modifiers);
        }
    } else if (shortcut->reference) {
        UnregisterEventHotKey(shortcut->reference);
        shortcut->reference = NULL;
    }
}

- (void)setToolEnabled:(BOOL)enabled forAction:(DeskKitShortcut)action {
    if (enabled == [self toolIsEnabledForAction:action]) return;
    [NSUserDefaults.standardUserDefaults setBool:!enabled forKey:Tools[action].disabledKey];
    [self updateShortcutRegistrationForAction:action];
    switch (action) {
        case DeskKitShortcutQueue:
            if (enabled) {
                self.lastChangeCount = NSPasteboard.generalPasteboard.changeCount;
                [self startMonitoring];
            } else {
                self.pasteGeneration++;
                [self.timer invalidate];
                self.timer = nil;
                [self.panel hide];
            }
            break;
        case DeskKitShortcutScreenshot:
            break;
    }
    [self.settings refreshTools];
}

- (void)registerHotkeys {
    EventTypeSpec spec = {kEventClassKeyboard, kEventHotKeyPressed};
    if (InstallEventHandler(GetApplicationEventTarget(), HotkeyHandler, 1, &spec, NULL, &_hotkeyHandler) != noErr) return;
    for (DeskKitShortcut action = DeskKitShortcutQueue; action <= DeskKitShortcutScreenshot; action++) {
        [self updateShortcutRegistrationForAction:action];
    }
}

- (BOOL)shortcutIsUnavailableForAction:(DeskKitShortcut)action {
    return [self toolIsEnabledForAction:action] &&
        _shortcuts[action].modifiers && !_shortcuts[action].reference;
}

- (void)startScreenshot {
    // Let the status menu finish closing before ScreenCaptureKit samples the display.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![self toolIsEnabledForAction:DeskKitShortcutScreenshot]) return;
        [self.panel hide];
        DeskKitStartScreenshot();
    });
}

- (void)saveShortcutForAction:(DeskKitShortcut)action {
    ToolShortcut shortcut = _shortcuts[action];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setInteger:shortcut.code forKey:Tools[action].codeKey];
    [defaults setInteger:shortcut.modifiers forKey:Tools[action].modifiersKey];
    if (action == DeskKitShortcutQueue) [self.panel setShortcutTitle:[self shortcutTitle]];
}

- (void)clearShortcutForAction:(DeskKitShortcut)action {
    ToolShortcut *shortcut = &_shortcuts[action];
    shortcut->modifiers = 0;
    [self updateShortcutRegistrationForAction:action];
    [self saveShortcutForAction:action];
}

- (BOOL)recordShortcutForAction:(DeskKitShortcut)action keyCode:(unsigned short)code modifierFlags:(NSEventModifierFlags)flags {
    if (!self.hotkeyHandler) return NO;
    UInt32 modifiers = CarbonModifiersFromFlags(flags);
    ToolShortcut *shortcut = &_shortcuts[action];
    if (shortcut->reference && code == shortcut->code && modifiers == shortcut->modifiers) return YES;
    for (DeskKitShortcut other = DeskKitShortcutQueue; other <= DeskKitShortcutScreenshot; other++) {
        if (other != action && code == _shortcuts[other].code && modifiers == _shortcuts[other].modifiers) return NO;
    }
    EventHotKeyRef replacement = RegisterShortcut(action, code, modifiers);
    if (!replacement) return NO;
    if (shortcut->reference) UnregisterEventHotKey(shortcut->reference);
    *shortcut = (ToolShortcut){code, modifiers, replacement};
    [self updateShortcutRegistrationForAction:action];
    [self saveShortcutForAction:action];
    return YES;
}

- (void)showSettings:(id)sender {
    [self.settings show];
}

- (BOOL)handleShortcutWhileRecording:(DeskKitShortcut)action {
    return [self.settings handleRegisteredShortcut:action];
}

- (void)hotkeyPressed {
    if (![NSThread isMainThread]) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self hotkeyPressed];
        });
        return;
    }
    [self togglePanel];
}

- (void)startMonitoring {
    self.timer = [NSTimer timerWithTimeInterval:0.45 repeats:YES block:^(__unused NSTimer *timer) {
        [self pollPasteboard];
    }];
    self.timer.tolerance = 0.05;
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)rememberFrontApp {
    NSRunningApplication *front = NSWorkspace.sharedWorkspace.frontmostApplication;
    if (front && !front.terminated && front.processIdentifier != getpid()) {
        self.previousApp = front;
    }
}

- (void)pollPasteboard {
    [self rememberFrontApp];
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    NSInteger count = pasteboard.changeCount;
    if (count == self.lastChangeCount) return;
    self.lastChangeCount = count;
    if (count == self.store.suppressedChangeCount) return;
    [self.store ingestPasteboard:pasteboard];
}

- (void)togglePanel {
    if (self.panel.isVisible) [self.panel hide];
    else [self showPanel];
}

- (void)showPanel {
    if (![self toolIsEnabledForAction:DeskKitShortcutQueue] || DeskKitScreenshotIsActive()) return;
    self.pasteGeneration++;
    [Analytics track:@"queue_opened"];
    [self pollPasteboard];
    [self.panel show];
}

#pragma mark - QueuePanelDelegate

- (void)queuePanel:(QueuePanel *)panel didChooseItem:(ClipItem *)item paste:(BOOL)paste plainText:(BOOL)plainText {
    NSUInteger generation = ++self.pasteGeneration;
    if (![self.store restoreItem:item plainText:plainText]) { NSBeep(); return; }
    if (paste) [Analytics track:@"paste_requested"];
    [self rememberFrontApp];
    NSRunningApplication *target = self.previousApp;
    if (!target || target.terminated || target.processIdentifier == getpid()) target = nil;

    [panel hide];
    if (!paste || !target) return;
    if (!DeskKitAccessibilityTrusted()) {
        DeskKitPromptAccessibility();
        return;
    }
    [self sendPasteToApplication:target attempt:0 generation:generation change:self.store.suppressedChangeCount];
}

- (void)sendPasteToApplication:(NSRunningApplication *)target attempt:(NSInteger)attempt
                    generation:(NSUInteger)generation change:(NSInteger)change {
    PasteCheck isCurrent = ^BOOL {
        return self.pasteGeneration == generation;
    };
    if (!isCurrent() || target.terminated ||
        self.panel.isVisible || NSPasteboard.generalPasteboard.changeCount != change) return;
    pid_t pid = target.processIdentifier;
    if (NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier != pid) {
        if (attempt >= 20) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 40 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            [self sendPasteToApplication:target attempt:attempt + 1 generation:generation change:change];
        });
        return;
    }

    // Allow the target's text field to regain focus. Menu traversal sends
    // synchronous AX messages, so do that work away from the event loop.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        PasteCheck canPaste = ^BOOL {
            return isCurrent() && !self.panel.isVisible &&
                !target.terminated && NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier == pid &&
                NSPasteboard.generalPasteboard.changeCount == change;
        };
        if (!canPaste()) return;
        dispatch_async(self.pasteQueue, ^{
            BOOL pressed = PressPasteMenu(pid, isCurrent, ^BOOL {
                __block BOOL allowed;
                dispatch_sync(dispatch_get_main_queue(), ^{ allowed = canPaste(); });
                return allowed;
            });
            if (!pressed) dispatch_async(dispatch_get_main_queue(), ^{
                if (canPaste()) PostCommandVToPid(pid);
            });
        });
    });
}

- (void)queuePanel:(QueuePanel *)panel didDeleteItem:(ClipItem *)item {
    [self.store deleteItem:item];
}

- (void)queuePanelDidRequestAccessibility:(QueuePanel *)panel {
    OpenAccessibilitySettings();
}

- (NSString *)queuePanelShortcutTitle:(QueuePanel *)panel {
    return [self shortcutTitle];
}

- (void)settingsPanelDidClose:(SettingsPanel *)panel {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
}

@end

static OSStatus HotkeyHandler(EventHandlerCallRef next, EventRef event, void *userData) {
    EventHotKeyID hotkey;
    if (GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID,
                          NULL, sizeof(hotkey), NULL, &hotkey) != noErr ||
        hotkey.signature != DeskKitHotkeySignature) return eventNotHandledErr;

    AppController *controller = [AppController shared];
    switch (hotkey.id) {
        case DeskKitShortcutQueue:
            if (![controller handleShortcutWhileRecording:DeskKitShortcutQueue]) [controller hotkeyPressed];
            break;
        case DeskKitShortcutScreenshot:
            if (![controller handleShortcutWhileRecording:DeskKitShortcutScreenshot]) [controller startScreenshot];
            break;
        default: return eventNotHandledErr;
    }
    return noErr;
}
