#import "AppController.h"
#import "Analytics.h"
#import <Sparkle/Sparkle.h>
#import "AccessibilityTrust.h"
#import "ClipboardStore.h"
#import "QueuePanel.h"
#import "SettingsPanel.h"
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>
#import <ServiceManagement/ServiceManagement.h>

static OSStatus HotkeyHandler(EventHandlerCallRef next, EventRef event, void *userData);

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

static BOOL PressPasteInElement(AXUIElementRef element, int depth) {
    if (!element || depth > 5) return NO;
    AXUIElementSetMessagingTimeout(element, 0.2);
    CFTypeRef role = NULL;
    if (AXUIElementCopyAttributeValue(element, kAXRoleAttribute, &role) != kAXErrorSuccess || !role) return NO;
    BOOL isItem = CFEqual(role, kAXMenuItemRole);
    BOOL descend = CFEqual(role, kAXMenuBarRole) || CFEqual(role, kAXMenuBarItemRole) || CFEqual(role, kAXMenuRole);
    CFRelease(role);
    if (isItem && IsPlainPasteItem(element) && AXEnabled(element)) {
        if (AXUIElementPerformAction(element, kAXPressAction) == kAXErrorSuccess) return YES;
    }
    if (!descend) return NO;
    CFArrayRef children = NULL;
    if (AXUIElementCopyAttributeValue(element, kAXChildrenAttribute, (CFTypeRef *)&children) != kAXErrorSuccess || !children) return NO;
    BOOL pressed = NO;
    CFIndex count = CFArrayGetCount(children);
    for (CFIndex i = 0; i < count && !pressed; i++) {
        pressed = PressPasteInElement((AXUIElementRef)CFArrayGetValueAtIndex(children, i), depth + 1);
    }
    CFRelease(children);
    return pressed;
}

static BOOL PressPasteMenu(pid_t pid) {
    if (pid <= 0 || !ClipStackAccessibilityTrusted()) return NO;
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
        for (CFIndex i = 0; i < count && !pressed; i++) {
            AXUIElementRef item = (AXUIElementRef)CFArrayGetValueAtIndex(top, i);
            if (AXTitleIs(item, CFSTR("编辑")) || AXTitleIs(item, CFSTR("編輯")) || AXTitleIs(item, CFSTR("Edit"))) {
                pressed = PressPasteInElement(item, 0);
            }
        }
        if (!pressed) {
            for (CFIndex i = 0; i < count && !pressed; i++) {
                pressed = PressPasteInElement((AXUIElementRef)CFArrayGetValueAtIndex(top, i), 0);
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

@interface AppController () <QueuePanelDelegate, SettingsPanelDelegate>
@property SPUStandardUpdaterController *updaterController;
@property ClipboardStore *store;
@property QueuePanel *panel;
@property SettingsPanel *settings;
@property NSStatusItem *statusItem;
@property NSTimer *timer;
@property NSInteger lastChangeCount;
@property NSRunningApplication *previousApp;
@property BOOL hotkeyRegistered;
@property EventHandlerRef hotkeyHandler;
@property EventHotKeyRef hotkeyRef;
@property UInt32 hotkeyCode;
@property UInt32 hotkeyModifiers;
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

    self.store = [ClipboardStore new];
    [self.store load];
    self.panel = [[QueuePanel alloc] initWithStore:self.store];
    self.panel.delegate = self;
    self.settings = [SettingsPanel new];
    self.settings.delegate = self;
    self.lastChangeCount = NSPasteboard.generalPasteboard.changeCount;
    [self.store ingestPasteboard:NSPasteboard.generalPasteboard];
    if ([NSBundle.mainBundle objectForInfoDictionaryKey:@"SUFeedURL"]) {
        self.updaterController = [[SPUStandardUpdaterController alloc] initWithStartingUpdater:YES updaterDelegate:nil userDriverDelegate:nil];
    }
    [Analytics track:@"app_started"];
    [self installStatusItem];
    [self loadHotkey];
    [self registerHotkey];
    [self startMonitoring];

    [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                        selector:@selector(showPanel)
                                                            name:@"local.handong.ClipStack.show"
                                                          object:nil];
    fprintf(stdout, "ClipStack 已启动。快捷键 %s。自动粘贴: %s。历史目录: %s\n",
            [self shortcutTitle].UTF8String,
            ClipStackAccessibilityTrusted() ? "可用" : "不可用",
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
    NSImage *image = [NSImage imageWithSystemSymbolName:@"doc.on.clipboard" accessibilityDescription:@"ClipStack"];
    image.template = YES;
    self.statusItem.button.image = image;
    self.statusItem.menu = [self buildMenu];
}

- (NSMenu *)buildMenu {
    NSMenu *menu = [NSMenu new];
    menu.delegate = (id<NSMenuDelegate>)self;
    [menu addItemWithTitle:@"打开队列" action:@selector(showPanel) keyEquivalent:@""].target = self;
    NSMenuItem *shortcut = [[NSMenuItem alloc] initWithTitle:@"唤起快捷键 ⌘⇧C" action:nil keyEquivalent:@""];
    shortcut.enabled = NO;
    shortcut.tag = 1;
    [menu addItem:shortcut];
    [menu addItemWithTitle:@"设置…" action:@selector(editShortcut:) keyEquivalent:@""].target = self;
    if (self.updaterController) {
        [menu addItemWithTitle:@"检查更新…" action:@selector(checkForUpdates:) keyEquivalent:@""].target = self.updaterController;
    }
    NSMenuItem *analytics = [menu addItemWithTitle:@"发送匿名使用统计" action:@selector(toggleAnalytics:) keyEquivalent:@""];
    analytics.target = self;
    analytics.tag = 5;
    analytics.hidden = ![[NSBundle.mainBundle objectForInfoDictionaryKey:@"AptabaseAppKey"] length];
    NSMenuItem *access = [[NSMenuItem alloc] initWithTitle:@"辅助功能未生效，无法自动粘贴" action:nil keyEquivalent:@""];
    access.enabled = NO;
    access.tag = 4;
    access.hidden = YES;
    [menu addItem:access];
    NSMenuItem *count = [[NSMenuItem alloc] initWithTitle:@"已保存 0 条" action:nil keyEquivalent:@""];
    count.enabled = NO;
    count.tag = 2;
    [menu addItem:count];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"清空历史…" action:@selector(confirmClear:) keyEquivalent:@""].target = self;
    NSMenuItem *login = [[NSMenuItem alloc] initWithTitle:@"登录时启动" action:@selector(toggleLaunchAtLogin:) keyEquivalent:@""];
    login.target = self;
    login.tag = 3;
    [menu addItem:login];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"退出" action:@selector(terminate:) keyEquivalent:@""].target = NSApp;
    return menu;
}

- (void)toggleAnalytics:(id)sender {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:![defaults boolForKey:@"AnalyticsDisabled"] forKey:@"AnalyticsDisabled"];
}

- (void)menuWillOpen:(NSMenu *)menu {
    [menu itemWithTag:5].state = [NSUserDefaults.standardUserDefaults boolForKey:@"AnalyticsDisabled"] ? NSControlStateValueOff : NSControlStateValueOn;
    NSMenuItem *shortcut = [menu itemWithTag:1];
    NSString *title = [NSString stringWithFormat:@"唤起快捷键 %@", [self shortcutTitle]];
    shortcut.title = self.hotkeyRegistered ? title : [title stringByAppendingString:@"（已被占用）"];
    [menu itemWithTag:4].hidden = ClipStackAccessibilityTrusted();
    [menu itemWithTag:2].title = [NSString stringWithFormat:@"已保存 %lu 条", (unsigned long)self.store.items.count];
    BOOL enabled = SMAppService.mainAppService.status == SMAppServiceStatusEnabled;
    [menu itemWithTag:3].title = enabled ? @"关闭登录时启动" : @"登录时启动";
}

- (void)confirmClear:(id)sender {
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

static NSString *const CopyQueueHotKeyCodeKey = @"CopyQueueHotKeyCode";
static NSString *const CopyQueueHotKeyModifiersKey = @"CopyQueueHotKeyModifiers";

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

- (void)loadHotkey {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (![defaults objectForKey:CopyQueueHotKeyCodeKey]) {
        NSString *legacy = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences/local.handong.CopyQueue.plist"];
        NSDictionary *old = [NSDictionary dictionaryWithContentsOfFile:legacy];
        if (old[CopyQueueHotKeyCodeKey]) {
            [defaults setObject:old[CopyQueueHotKeyCodeKey] forKey:CopyQueueHotKeyCodeKey];
            [defaults setObject:old[CopyQueueHotKeyModifiersKey] forKey:CopyQueueHotKeyModifiersKey];
        }
    }
    if ([defaults objectForKey:CopyQueueHotKeyCodeKey]) {
        self.hotkeyCode = (UInt32)[defaults integerForKey:CopyQueueHotKeyCodeKey];
        self.hotkeyModifiers = (UInt32)[defaults integerForKey:CopyQueueHotKeyModifiersKey];
    } else {
        self.hotkeyCode = kVK_ANSI_C;
        self.hotkeyModifiers = cmdKey | shiftKey;
    }
}

- (NSString *)shortcutTitle {
    NSMutableString *title = [NSMutableString string];
    if (self.hotkeyModifiers & cmdKey) [title appendString:@"⌘"];
    if (self.hotkeyModifiers & shiftKey) [title appendString:@"⇧"];
    if (self.hotkeyModifiers & optionKey) [title appendString:@"⌥"];
    if (self.hotkeyModifiers & controlKey) [title appendString:@"⌃"];
    [title appendString:HotkeyKeyName(self.hotkeyCode)];
    return title;
}

- (void)registerHotkey {
    if (!self.hotkeyHandler) {
        EventTypeSpec spec = {kEventClassKeyboard, kEventHotKeyPressed};
        OSStatus installed = InstallEventHandler(GetApplicationEventTarget(), HotkeyHandler, 1, &spec, NULL, &_hotkeyHandler);
        if (installed != noErr) return;
    }
    if (self.hotkeyRef) {
        UnregisterEventHotKey(self.hotkeyRef);
        self.hotkeyRef = NULL;
    }
    EventHotKeyID hotKeyID = {'CQUE', 1};
    OSStatus registered = RegisterEventHotKey(self.hotkeyCode, self.hotkeyModifiers, hotKeyID, GetApplicationEventTarget(), 0, &_hotkeyRef);
    self.hotkeyRegistered = registered == noErr;
}

- (BOOL)setHotkeyCode:(UInt32)keyCode modifiers:(UInt32)modifiers {
    UInt32 previousCode = self.hotkeyCode;
    UInt32 previousModifiers = self.hotkeyModifiers;
    self.hotkeyCode = keyCode;
    self.hotkeyModifiers = modifiers;
    [self registerHotkey];
    if (!self.hotkeyRegistered) {
        self.hotkeyCode = previousCode;
        self.hotkeyModifiers = previousModifiers;
        [self registerHotkey];
        return NO;
    }
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setInteger:keyCode forKey:CopyQueueHotKeyCodeKey];
    [defaults setInteger:modifiers forKey:CopyQueueHotKeyModifiersKey];
    return YES;
}

- (void)editShortcut:(id)sender {
    [self.settings show];
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
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)rememberFrontApp {
    if (self.panel.isVisible) return;
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
    [Analytics track:@"queue_opened"];
    [self rememberFrontApp];
    [self.panel show];
}

#pragma mark - QueuePanelDelegate

- (void)queuePanel:(QueuePanel *)panel didChooseItem:(ClipItem *)item paste:(BOOL)paste {
    if (![self.store restoreItem:item]) return;
    if (paste) [Analytics track:@"paste_requested"];
    NSRunningApplication *target = self.previousApp;
    if (!target || target.terminated || target.processIdentifier == getpid()) target = nil;

    [panel hide];
    if (!paste || !target) return;
    if (!ClipStackAccessibilityTrusted()) {
        ClipStackPromptAccessibility();
        return;
    }
    [self sendPasteToApplication:target attempt:0];
}

- (void)sendPasteToApplication:(NSRunningApplication *)target attempt:(NSInteger)attempt {
    if (target.terminated || self.panel.isVisible) return;
    pid_t frontPID = NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
    BOOL ready = frontPID == target.processIdentifier;
    if (!ready) {
        if (attempt >= 20) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.04 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self sendPasteToApplication:target attempt:attempt + 1];
        });
        return;
    }
    // Give the target a moment to restore its text field. Prefer the app's own
    // Paste menu: injected ⌘V is ignored by browsers, Electron, and secure input.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.panel.isVisible || target.terminated ||
            NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier != target.processIdentifier) return;
        BOOL pressed = PressPasteMenu(target.processIdentifier);
        if (!pressed) PostCommandVToPid(target.processIdentifier);
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

- (NSString *)settingsPanelShortcutTitle:(SettingsPanel *)panel {
    return [self shortcutTitle];
}

- (BOOL)settingsPanel:(SettingsPanel *)panel recordShortcutWithKeyCode:(unsigned short)keyCode modifierFlags:(NSEventModifierFlags)flags {
    BOOL saved = [self setHotkeyCode:keyCode modifiers:CarbonModifiersFromFlags(flags)];
    if (saved) [self.panel setShortcutTitle:[self shortcutTitle]];
    return saved;
}

- (void)settingsPanelDidClose:(SettingsPanel *)panel {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
}

@end

static OSStatus HotkeyHandler(EventHandlerCallRef next, EventRef event, void *userData) {
    [[AppController shared] hotkeyPressed];
    return noErr;
}
