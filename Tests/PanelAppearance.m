#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import "Theme.h"
#import "SettingsPanel.h"

static void Snapshot(NSView *view, NSString *path) {
    [view layoutSubtreeIfNeeded];
    NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
    NSCAssert([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES], @"snapshot saved");
}
static void Send(NSControl *control) {
    NSCAssert([NSApp sendAction:control.action to:control.target from:control], @"setting control has a working action");
}
static void ValidateViews(NSView *parent) {
    for (NSView *view in parent.subviews) {
        if (view.hidden) continue;
        if ([view isKindOfClass:NSTextField.class]) {
            NSString *text = [(NSTextField *)view stringValue];
            NSCAssert(![text containsString:@"让小工具"] && ![text containsString:@"外观、快捷键"], @"removed headings stay removed");
        }
        NSRect frame = [view convertRect:view.bounds toView:parent.window.contentView];
        NSCAssert(NSContainsRect(NSInsetRect(parent.window.contentView.bounds, -1, -1), frame), @"settings control fits content: %@", view);
        ValidateViews(view);
    }
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 3) {
            NSString *mode = @(argv[1]);
            NSString *suite = @(argv[2]);
            NSCAssert([suite hasPrefix:@"test.HandyMinis.PanelAppearance."], @"isolated preference domain required");
            NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
            HMPanelStyle *style = [[HMPanelStyle alloc] initWithDefaults:defaults];
            if ([mode isEqualToString:@"--write-preferences"]) {
                style.palette = 2; style.transparency = 35; style.blur = NO;
                [defaults synchronize];
            } else if ([mode isEqualToString:@"--read-preferences"]) {
                NSCAssert(style.palette == 2 && style.transparency == 35 && !style.blur, @"preferences survive process restart");
                puts("PASS: panel preferences survive a separate process restart");
            } else NSCAssert([mode isEqualToString:@"--cleanup-preferences"], @"known test mode");
            if (![mode isEqualToString:@"--write-preferences"]) {
                [defaults removePersistentDomainForName:suite];
                [defaults synchronize];
            }
            return 0;
        }
        [NSApplication sharedApplication];
        NSAppearance *light = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        NSAppearance *dark = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        NSApp.appearance = light;
        NSString *suite = [@"test.HandyMinis.PanelAppearance." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        [defaults setInteger:2 forKey:@"AppearanceTheme"];
        [defaults setInteger:42 forKey:@"QueueShortcutKeyCode"];
        HMPanelStyle *style = [[HMPanelStyle alloc] initWithDefaults:defaults];
        NSCAssert(style.palette == 0 && style.transparency == 0 && style.blur, @"safe appearance defaults");
        SettingsPanel *settings = [[SettingsPanel alloc] initWithPanelStyle:style];
        NSWindow *settingsWindow = [settings valueForKey:@"window"];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 320, 160)
            styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        window.opaque = NO;
        window.backgroundColor = NSColor.clearColor;
        window.appearance = light;
        HMPanelSurfaceView *surface = [[HMPanelSurfaceView alloc] initWithStyle:style];
        window.contentView = surface;
        NSTextField *label = [NSTextField labelWithString:@"文字保持清晰"];
        label.frame = NSMakeRect(20, 50, 240, 24);
        [surface addSubview:label];
        HMSurfaceView *tint = [surface valueForKey:@"tintView"];
        NSVisualEffectView *blur = [surface valueForKey:@"blurView"];
        NSSlider *slider = [settings valueForKey:@"transparencySlider"];
        slider.doubleValue = 35; Send(slider);
        double alpha = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceTransparency ? 1 : .65;
        NSCAssert(fabs(tint.fillColor.alphaComponent - alpha) < .001, @"live background transparency");
        NSCAssert(surface.alphaValue == 1 && label.alphaValue == 1, @"transparency does not fade content");
        NSCAssert(blur.hidden == (alpha == 1), @"blur follows transparency and accessibility preference");
        NSButton *blurToggle = [settings valueForKey:@"blurToggle"];
        blurToggle.state = NSControlStateValueOff; Send(blurToggle);
        NSCAssert(blur.hidden && !style.blur, @"blur can be disabled");
        NSPopUpButton *palette = [settings valueForKey:@"palettePicker"];
        [palette selectItemAtIndex:2]; Send(palette);
        NSCAssert(style.palette == 2 && [style colorForAppearance:light].greenComponent > [style colorForAppearance:light].redComponent, @"mint preset");
        NSCAssert([style colorForAppearance:dark].brightnessComponent < [style colorForAppearance:light].brightnessComponent, @"presets adapt to dark appearance");
        NSColorWell *well = [settings valueForKey:@"colorWell"];
        well.color = [NSColor colorWithSRGBRed:.1 green:.15 blue:.2 alpha:.2]; Send(well);
        NSCAssert(style.palette == 4 && fabs([style colorForAppearance:light].redComponent - .1) < .001, @"custom color persists and selects custom mode");
        NSCAssert(fabs(tint.fillColor.alphaComponent - alpha) < .001, @"color well alpha cannot override transparency slider");
        NSCAssert([label.effectiveAppearance.name isEqualToString:NSAppearanceNameDarkAqua], @"dark custom background receives light text appearance");
        [style setCustomColor:[NSColor colorWithSRGBRed:.8 green:.9 blue:1 alpha:1] forAppearance:dark];
        NSCAssert(fabs([style colorForAppearance:light].redComponent - .1) < .001, @"light custom color retained separately");
        window.appearance = dark;
        NSCAssert(fabs(tint.fillColor.redComponent - .8) < .001 && [label.effectiveAppearance.name isEqualToString:NSAppearanceNameAqua], @"dark-mode custom color updates live with readable content");
        HMPanelStyle *reopened = [[HMPanelStyle alloc] initWithDefaults:[[NSUserDefaults alloc] initWithSuiteName:suite]];
        NSCAssert(reopened.palette == 4 && reopened.transparency == 35 && !reopened.blur, @"settings persist across model recreation");
        NSCAssert(fabs([reopened colorForAppearance:dark].blueComponent - 1) < .001, @"custom RGB persists");
        style.transparency = 100;
        NSCAssert(style.transparency == 80, @"upper transparency bound");
        style.transparency = -5;
        NSCAssert(style.transparency == 0 && blur.hidden, @"opaque background hides blur");
        [style reset];
        NSCAssert(style.palette == 0 && style.transparency == 0 && style.blur, @"restore panel defaults");
        NSCAssert([defaults integerForKey:@"AppearanceTheme"] == 2 && [defaults integerForKey:@"QueueShortcutKeyCode"] == 42, @"reset preserves unrelated preferences");
        NSCAssert(palette.indexOfSelectedItem == 0 && slider.doubleValue == 0 && !blurToggle.enabled, @"reset refreshes settings controls");
        [settingsWindow.contentView layoutSubtreeIfNeeded];
        ValidateViews(settingsWindow.contentView);
        if (argc > 1) {
            NSDictionary *buttons = [settings valueForKey:@"shortcutButtons"];
            [buttons[@(HandyMinisShortcutQueue)] setTitle:@"⌘⇧C"];
            [buttons[@(HandyMinisShortcutScreenshot)] setTitle:@"⌃⌘A"];
            for (NSButton *button in [settings valueForKey:@"toolButtons"]) button.state = NSControlStateValueOn;
            [[settings valueForKey:@"statusLabel"] setStringValue:@"点击按钮修改快捷键。"];
            [[settings valueForKey:@"statusLabel"] setTextColor:NSColor.secondaryLabelColor];
            style.palette = 2; style.transparency = 25;
            Snapshot(settingsWindow.contentView, [@(argv[1]) stringByAppendingString:@"-light.png"]);
            settingsWindow.appearance = dark;
            Snapshot(settingsWindow.contentView, [@(argv[1]) stringByAppendingString:@"-dark.png"]);
        }
        [defaults removePersistentDomainForName:suite];
        puts("PASS: palette/color/opacity controls; immediate background-only update; independent light/dark colors; readable text; blur; persistence; reset; settings layout");
    }
    return 0;
}
