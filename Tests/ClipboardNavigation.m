#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import "QueuePanel.h"
#import "SettingsPanel.h"
#import "Theme.h"

@interface SettingsPanel (AppearanceTests)
+ (void)applyTheme:(HandyMinisTheme)theme;
@end

@interface QueuePanel (NavigationTests)
- (void)reloadKeepingSelection:(BOOL)keep;
- (void)moveSelection:(NSInteger)delta;
- (void)configureCell:(id)cell row:(NSInteger)row;
- (void)changeSection:(id)sender;
@end

@interface FixtureStore : ClipboardStore
@property NSArray<ClipItem *> *fixtures;
@end
@implementation FixtureStore
- (instancetype)init {
    return [super initWithSupportDirectory:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
}
- (NSArray<ClipItem *> *)items { return self.fixtures; }
@end

static void Render(NSWindow *window) {
    [window.contentView layoutSubtreeIfNeeded];
    [window displayIfNeeded];
}

static void Snapshot(NSView *view, NSString *path) {
    [view layoutSubtreeIfNeeded];
    NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
    NSCAssert([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES], @"snapshot write");
}

static void CheckDataAndSelection(FixtureStore *store, QueuePanel *panel, NSTableView *table, NSString *original) {
    ClipItem *longItem = store.fixtures[0];
    NSCAssert(longItem.displayPreview.length < 1200, @"bounded long text preview");
    NSCAssert([longItem.text isEqualToString:original], @"full payload preserved");
    NSCAssert([longItem matchesQuery:@"TAIL_SEARCH_MARKER"], @"search beyond preview");
    ClipItem *unicode = [ClipItem new];
    unicode.text = [[@"a" stringByPaddingToLength:1023 withString:@"a" startingAtIndex:0] stringByAppendingString:@"👩🏽‍💻abc"];
    NSCAssert([unicode.displayPreview dataUsingEncoding:NSUTF8StringEncoding] != nil, @"Unicode boundary");
    unicode.text = @"changed\nnew summary";
    NSCAssert([unicode.primaryText isEqualToString:@"changed"] && [unicode.secondaryText isEqualToString:@"new summary"], @"summary invalidation");
    NSCAssert([unicode.displayPreview isEqualToString:unicode.text], @"preview invalidation");
    ClipItem *files = [ClipItem new];
    files.kind = ClipKindFiles;
    NSMutableArray *paths = [NSMutableArray array];
    for (NSInteger i = 0; i < 1000; i++) [paths addObject:[NSString stringWithFormat:@"/tmp/notes/file-%ld.txt", i]];
    files.filePaths = paths;
    NSCAssert(files.displayPreview.length < 1200 && [files matchesQuery:@"file-999"], @"file preview/search");
    NSSearchField *search = [panel valueForKey:@"searchField"];
    // The flat search cell must retain native editing and live filtering.
    [search selectText:nil];
    NSTextView *editor = (NSTextView *)search.currentEditor;
    NSCAssert(editor != nil && search.editable, @"search accepts keyboard focus and editing");
    [editor insertText:@"TAIL_SEARCH_MARKER" replacementRange:NSMakeRange(0, editor.string.length)];
    NSCAssert([search.stringValue isEqualToString:@"TAIL_SEARCH_MARKER"], @"native editor updates search value");
    NSCAssert(table.numberOfRows == 14 && table.selectedRow == 0, @"filter matching full text");
    [search.window makeFirstResponder:table];
    search.stringValue = @"NO_MATCH_01234";
    [panel reloadKeepingSelection:NO];
    [panel moveSelection:1];
    NSCAssert(table.numberOfRows == 0 && table.selectedRow == -1, @"empty filter navigation");
    search.stringValue = @"";
    [panel reloadKeepingSelection:NO];
    [panel moveSelection:1];
    ClipItem *selected = store.fixtures[1];
    NSMutableArray *updated = [store.fixtures mutableCopy];
    [updated removeObjectAtIndex:0];
    store.fixtures = updated;
    [panel reloadKeepingSelection:YES];
    NSCAssert(table.selectedRow == 0 && store.fixtures[0] == selected, @"retain selection after preceding deletion");
    [updated removeObjectAtIndex:0];
    store.fixtures = [updated copy];
    [panel reloadKeepingSelection:YES];
    NSCAssert(table.selectedRow == 0, @"selection after selected deletion");
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:updated.count - 1] byExtendingSelection:NO];
    [panel moveSelection:1];
    NSCAssert(table.selectedRow == (NSInteger)updated.count - 1, @"lower bound");
    // Reload must not leave the previously expanded row at its old height.
    [panel reloadKeepingSelection:NO];
    printf("reload old row height=%.1f\n", [table rectOfRow:updated.count - 1].size.height);
    NSCAssert([table rectOfRow:updated.count - 1].size.height <= 53, @"reset old expanded height");
}

static void PumpUntil(BOOL (^finished)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!finished() && deadline.timeIntervalSinceNow > 0) {
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.005]];
    }
    NSCAssert(finished(), @"thumbnail completion deadline");
}

static void CheckThumbnails(FixtureStore *store, QueuePanel *panel, NSTableView *table) {
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    [store setValue:directory forKey:@"imagesDirectory"];
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:2400 pixelsHigh:1600
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    memset(bitmap.bitmapData, 180, bitmap.bytesPerRow * bitmap.pixelsHigh);
    NSString *name = [NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"png"];
    [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[directory stringByAppendingPathComponent:name] atomically:YES];
    ClipItem *picture = [ClipItem new];
    picture.kind = ClipKindImage;
    picture.imageFile = name;
    picture.pixelWidth = 2400;
    picture.pixelHeight = 1600;
    picture.itemID = NSUUID.UUID.UUIDString;
    picture.createdAt = [NSDate date];
    NSCAssert([store thumbnailForItem:picture] == nil, @"cold cache does not decode");
    __block NSUInteger completed = 0;
    __block NSImage *firstImage;
    for (NSUInteger i = 0; i < 4; i++) {
        [store requestThumbnailForItem:picture completion:^(NSImage *image) {
            NSCAssert(NSThread.isMainThread && image != nil, @"main-thread image delivery");
            NSCAssert(image.size.width <= 640 && image.size.height <= 640, @"downsampled image");
            if (!firstImage) firstImage = image;
            NSCAssert(firstImage == image, @"coalesced requests");
            completed++;
        }];
    }
    NSCAssert(completed == 0, @"cold request is asynchronous");
    ClipItem *text = store.fixtures[0];
    store.fixtures = @[picture, text];
    [panel reloadKeepingSelection:NO];
    NSWindow *window = [panel valueForKey:@"panel"];
    Render(window);
    id cell = [table viewAtColumn:0 row:0 makeIfNecessary:YES];
    // Reuse the very same view while its image is still being decoded.
    store.fixtures = @[text];
    [panel reloadKeepingSelection:NO];
    [panel configureCell:cell row:0];
    NSImageView *icon = [cell valueForKey:@"iconView"];
    NSImage *textIcon = icon.image;
    PumpUntil(^BOOL { return completed == 4; });
    NSCAssert(icon.image == textIcon, @"late thumbnail cannot overwrite reused text row");
    NSCAssert([store thumbnailForItem:picture] == firstImage, @"warm cache lookup");
    picture.imageFile = [NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"png"];
    __block BOOL missing = NO;
    [store requestThumbnailForItem:picture completion:^(NSImage *image) { NSCAssert(!image, @"missing image"); missing = YES; }];
    PumpUntil(^BOOL { return missing; });
    __block BOOL cachedMiss = NO;
    [store requestThumbnailForItem:picture completion:^(NSImage *image) { cachedMiss = image == nil; }];
    NSCAssert(cachedMiss, @"negative cache prevents repeated failed reads");
    [NSFileManager.defaultManager removeItemAtPath:directory error:NULL];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSApp.applicationIconImage = [[NSImage alloc] initWithContentsOfFile:@"Resources/AppIcon.icns"];
        [SettingsPanel applyTheme:HandyMinisThemeLight];
        FixtureStore *store = [FixtureStore new];
        NSMutableArray *items = [NSMutableArray array];
        NSString *paragraph = @"清爽的工作台 · HandyMinis\n记录想法，快速找到刚才复制的内容。\nhttps://example.com/notes\n";
        NSMutableString *longText = [NSMutableString string];
        while (longText.length < 500000) [longText appendString:paragraph];
        [longText appendString:@"TAIL_SEARCH_MARKER"];
        for (NSUInteger i = 0; i < 40; i++) {
            ClipItem *item = [ClipItem new];
            item.itemID = NSUUID.UUID.UUIDString;
            item.kind = ClipKindText;
            item.createdAt = [NSDate dateWithTimeIntervalSinceNow:-(NSTimeInterval)(i * 60)];
            item.text = i % 3 == 0 ? longText : [NSString stringWithFormat:@"第 %lu 条复制内容\n%@", i + 1, paragraph];
            [items addObject:item];
        }
        store.fixtures = items;
        QueuePanel *panel = [[QueuePanel alloc] initWithStore:store];
        NSWindow *window = [panel valueForKey:@"panel"];
        [[panel valueForKey:@"banner"] setHidden:YES];
        [window.contentView layoutSubtreeIfNeeded];
        [panel reloadKeepingSelection:NO];
        Render(window);
        NSTableView *table = [panel valueForKey:@"table"];
        NSMutableArray<NSNumber *> *times = [NSMutableArray array];
        for (NSUInteger i = 0; i < 156; i++) {
            @autoreleasepool {
                CFTimeInterval start = CACurrentMediaTime();
                NSInteger delta = (i / 39) % 2 == 0 ? 1 : -1;
                [panel moveSelection:delta];
                Render(window);
                [times addObject:@((CACurrentMediaTime() - start) * 1000)];
                NSCAssert(table.selectedRow >= 0 && table.selectedRow < 40, @"selection bounds");
            }
        }
        [times sortUsingSelector:@selector(compare:)];
        printf("navigation samples=%lu median=%.3fms p95=%.3fms max=%.3fms\n", times.count,
            times[times.count / 2].doubleValue, times[(NSUInteger)(times.count * .95)].doubleValue, times.lastObject.doubleValue);
        NSCAssert(table.selectedRow == 0, @"round trip selection");
        [panel moveSelection:-1];
        NSCAssert(table.selectedRow == 0, @"upper bound");
        CheckDataAndSelection(store, panel, table, longText);
        CheckThumbnails(store, panel, table);
        if (argc > 1) {
            // Illustrative fixtures rendered by the real AppKit views.
            NSArray *examples = @[@"下午的计划\n整理笔记，完成设计稿，再去散步。",
                @"https://developer.apple.com/documentation/", @"把常用的小工具，放在顺手的地方。",
                @"会议笔记\n先解决高频问题，再打磨每一个细节。", @"npm run build", @"周末清单\n咖啡豆 · 书 · 散步"];
            NSMutableArray *samples = [NSMutableArray array];
            for (NSString *example in examples) {
                ClipItem *item = [ClipItem new];
                item.kind = ClipKindText;
                item.text = example;
                item.itemID = NSUUID.UUID.UUIDString;
                item.createdAt = [NSDate dateWithTimeIntervalSinceNow:-(NSTimeInterval)(samples.count * 180)];
                [samples addObject:item];
            }
            store.fixtures = samples;
            [panel changeSection:nil];
            Render(window);
            Snapshot(window.contentView, [@(argv[1]) stringByAppendingString:@"-light.png"]);
            [panel moveSelection:1]; Render(window);
            Snapshot(window.contentView, [@(argv[1]) stringByAppendingString:@"-next.png"]);
            NSSearchField *demoSearch = [panel valueForKey:@"searchField"];
            demoSearch.stringValue = @"会议"; [panel reloadKeepingSelection:NO]; Render(window);
            Snapshot(window.contentView, [@(argv[1]) stringByAppendingString:@"-search.png"]);
            demoSearch.stringValue = @""; [panel reloadKeepingSelection:NO]; Render(window);

            [SettingsPanel applyTheme:HandyMinisThemeDark];
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
            Render(window);
            NSCAssert(([[window.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua]), @"dark appearance propagated");
            Snapshot(window.contentView, [@(argv[1]) stringByAppendingString:@"-dark.png"]);
            SettingsPanel *settings = [SettingsPanel new];
            [settings refreshTools];
            NSWindow *settingsWindow = [settings valueForKey:@"window"];
            [SettingsPanel applyTheme:HandyMinisThemeLight];
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
            NSDictionary *buttons = [settings valueForKey:@"shortcutButtons"];
            [buttons[@(HandyMinisShortcutQueue)] setTitle:@"⌘⇧C"];
            [buttons[@(HandyMinisShortcutScreenshot)] setTitle:@"⌃⌘A"];
            for (NSButton *button in [settings valueForKey:@"toolButtons"]) button.state = NSControlStateValueOn;
            [[settings valueForKey:@"statusLabel"] setStringValue:@"点击按钮修改快捷键。"];
            [[settings valueForKey:@"statusLabel"] setTextColor:NSColor.secondaryLabelColor];
            Render(settingsWindow);
            NSCAssert(([[settingsWindow.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameAqua]), @"light appearance propagated");
            Snapshot(settingsWindow.contentView, [@(argv[1]) stringByAppendingString:@"-settings.png"]);
        }
        puts("PASS: bounds, search, reload/delete, preview invalidation, Unicode, full payload, async thumbnails, reuse and appearance snapshots");
    }
    return 0;
}
