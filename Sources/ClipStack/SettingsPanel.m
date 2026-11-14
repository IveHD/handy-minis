#import "SettingsPanel.h"

@interface SettingsPanel () <NSWindowDelegate>
@property NSWindow *window;
@property NSButton *shortcutButton;
@property NSTextField *statusLabel;
@property id keyMonitor;
@property BOOL recording;
@end

@implementation SettingsPanel

- (instancetype)init {
    self = [super init];
    if (self) {
        _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 198)
                                               styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];
        _window.title = @"设置";
        _window.delegate = self;
        _window.releasedWhenClosed = NO;
        [_window center];
        [self buildContent];
        [self installMonitor];
    }
    return self;
}

- (void)dealloc {
    if (_keyMonitor) [NSEvent removeMonitor:_keyMonitor];
}

- (void)buildContent {
    NSView *content = self.window.contentView;
    NSTextField *heading = [NSTextField labelWithString:@"唤起快捷键"];
    heading.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
    heading.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *detail = [NSTextField wrappingLabelWithString:@"用来打开最近复制。点击下方按钮后按下新的组合键，需要包含 ⌘ 或 ⌃。esc 取消。"];
    detail.font = [NSFont systemFontOfSize:12];
    detail.textColor = NSColor.secondaryLabelColor;
    detail.translatesAutoresizingMaskIntoConstraints = NO;

    NSButton *button = [NSButton buttonWithTitle:@"⌘⇧C" target:self action:@selector(recordClicked:)];
    button.bezelStyle = NSBezelStyleRounded;
    button.font = [NSFont systemFontOfSize:15 weight:NSFontWeightMedium];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    self.shortcutButton = button;

    NSTextField *status = [NSTextField labelWithString:@""];
    status.font = [NSFont systemFontOfSize:12];
    status.textColor = NSColor.systemRedColor;
    status.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel = status;

    [content addSubview:heading];
    [content addSubview:detail];
    [content addSubview:button];
    [content addSubview:status];
    [NSLayoutConstraint activateConstraints:@[
        [heading.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [heading.topAnchor constraintEqualToAnchor:content.topAnchor constant:18],
        [detail.leadingAnchor constraintEqualToAnchor:heading.leadingAnchor],
        [detail.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [detail.topAnchor constraintEqualToAnchor:heading.bottomAnchor constant:6],
        [button.leadingAnchor constraintEqualToAnchor:heading.leadingAnchor],
        [button.topAnchor constraintEqualToAnchor:detail.bottomAnchor constant:16],
        [button.widthAnchor constraintGreaterThanOrEqualToConstant:120],
        [status.leadingAnchor constraintEqualToAnchor:heading.leadingAnchor],
        [status.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [status.topAnchor constraintEqualToAnchor:button.bottomAnchor constant:10],
    ]];
}

- (void)installMonitor {
    __weak SettingsPanel *weakSelf = self;
    self.keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        SettingsPanel *panel = weakSelf;
        if (!panel || !panel.recording || !panel.window.isKeyWindow) return event;
        return [panel handleRecordingKey:event];
    }];
}

- (void)show {
    self.recording = NO;
    self.statusLabel.stringValue = @"";
    [self refreshButton];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [NSApp activateIgnoringOtherApps:YES];
#pragma clang diagnostic pop
    [self.window makeKeyAndOrderFront:nil];
    [self.window center];
}

- (void)refreshButton {
    NSString *title = self.recording ? @"按下快捷键" : [self.delegate settingsPanelShortcutTitle:self];
    if (title.length == 0) title = @"⌘⇧C";
    self.shortcutButton.title = title;
}

- (void)recordClicked:(id)sender {
    self.recording = YES;
    self.statusLabel.stringValue = @"";
    [self refreshButton];
    [self.window makeFirstResponder:self.window.contentView];
}

- (BOOL)isModifierKeyCode:(unsigned short)keyCode {
    switch (keyCode) {
        case 54: case 55: case 56: case 57: case 58: case 59: case 60: case 61: case 62: case 63:
            return YES;
        default:
            return NO;
    }
}

- (NSEvent *)handleRecordingKey:(NSEvent *)event {
    if (event.keyCode == 53) {
        self.recording = NO;
        [self refreshButton];
        return nil;
    }
    if ([self isModifierKeyCode:event.keyCode]) return nil;
    NSEventModifierFlags flags = event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagControl);
    if ((flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl)) == 0) {
        self.statusLabel.stringValue = @"需要包含 ⌘ 或 ⌃";
        return nil;
    }
    BOOL saved = [self.delegate settingsPanel:self recordShortcutWithKeyCode:event.keyCode modifierFlags:flags];
    self.recording = NO;
    if (saved) {
        self.statusLabel.stringValue = @"";
        [self refreshButton];
    } else {
        self.statusLabel.stringValue = @"这个快捷键已被占用";
        [self refreshButton];
    }
    return nil;
}

- (void)windowWillClose:(NSNotification *)notification {
    self.recording = NO;
    [self.delegate settingsPanelDidClose:self];
}

@end
