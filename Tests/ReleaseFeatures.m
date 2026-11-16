#import <Cocoa/Cocoa.h>
#import "ClipboardStore.h"
#import "QueuePanel.h"
#import "TextActions.h"
#import "WindowTiling.h"

// Exercise the shipping store with v1.0.4-compatible fixtures and a private
// pasteboard. Never load real history, write the system clipboard, or move windows.
@interface IsolatedStore : ClipboardStore
@property NSPasteboard *testPasteboard;
@end
@implementation IsolatedStore
- (NSPasteboard *)restorePasteboard { return self.testPasteboard; }
@end

@interface QueuePanel (ReleaseTests)
- (void)changeSection:(id)sender;
- (void)reloadKeepingSelection:(BOOL)keep;
- (NSEvent *)handleKey:(NSEvent *)event;
- (NSArray<ClipItem *> *)sectionItems;
- (NSMenu *)actionMenuForItem:(ClipItem *)item;
- (void)contextClean:(NSMenuItem *)sender;
- (void)stageItem:(ClipItem *)item;
- (BOOL)stagePaths:(NSArray<NSString *> *)paths;
- (BOOL)acceptFileDrop:(id<NSDraggingInfo>)info;
- (id<NSPasteboardWriting>)tableView:(NSTableView *)table pasteboardWriterForRow:(NSInteger)row;
@end

@interface DropFixture : NSObject
@property NSPasteboard *draggingPasteboard;
@property id draggingSource;
@property NSDragOperation draggingSourceOperationMask;
@end
@implementation DropFixture
@end

@interface RecordingDelegate : NSObject <QueuePanelDelegate>
@property ClipItem *chosen;
@property BOOL paste;
@property BOOL plain;
@property ClipboardStore *store;
@end
@implementation RecordingDelegate
- (void)queuePanel:(QueuePanel *)panel didChooseItem:(ClipItem *)item paste:(BOOL)paste plainText:(BOOL)plain {
    self.chosen = item; self.paste = paste; self.plain = plain;
}
- (void)queuePanel:(QueuePanel *)panel didDeleteItem:(ClipItem *)item { [self.store deleteItem:item]; }
- (void)queuePanelDidRequestAccessibility:(QueuePanel *)panel {}
- (NSString *)queuePanelShortcutTitle:(QueuePanel *)panel { return @"⌘⇧C"; }
@end

static void Key(QueuePanel *panel, unsigned short code, NSEventModifierFlags flags) {
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags
        timestamp:0 windowNumber:0 context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:code];
    [panel handleKey:event];
}

static void Snapshot(QueuePanel *panel, NSString *path) {
    NSWindow *window = [panel valueForKey:@"panel"];
    [window.contentView layoutSubtreeIfNeeded];
    NSBitmapImageRep *bitmap = [window.contentView bitmapImageRepForCachingDisplayInRect:window.contentView.bounds];
    [window.contentView cacheDisplayInRect:window.contentView.bounds toBitmapImageRep:bitmap];
    NSCAssert([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES], @"snapshot saved");
    NSView *root = [panel valueForKey:@"root"];
    NSSegmentedControl *sections = [panel valueForKey:@"sections"];
    NSView *shortcut = [panel valueForKey:@"shortcutLabel"];
    NSCAssert(NSMaxX(sections.frame) + 8 <= NSMinX(shortcut.frame), @"tabs and shortcut must not overlap");
    for (NSView *view in root.subviews) {
        if (!view.hidden) NSCAssert(NSContainsRect(root.bounds, view.frame), @"visible control fits panel: %@", view);
    }
}

static IsolatedStore *OpenStore(NSString *directory, NSPasteboard *pasteboard) {
    IsolatedStore *store = [[IsolatedStore alloc] initWithSupportDirectory:directory];
    store.testPasteboard = pasteboard;
    [store load];
    return store;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        NSApp.applicationIconImage = [[NSImage alloc] initWithContentsOfFile:@"Resources/AppIcon.icns"];
        NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
        NSPasteboard *board = [NSPasteboard pasteboardWithUniqueName];
        NSCAssert(board != nil, @"private pasteboard available");
        NSData *rtf = [@"{\\rtf1\\ansi Hello \\b world\\b0}" dataUsingEncoding:NSUTF8StringEncoding];
        NSData *html = [@"<p>Hello <strong>world</strong></p>" dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *phraseFixture = @{@"id": @"phrase-original", @"createdAt": @"2026-11-15T08:00:00Z",
            @"kind": @"text", @"contentHash": @"fixture", @"phraseName": @"工作回复", @"text": @"收到，我会整理后回复。\n谢谢！"};
        NSDictionary *historyFixture = @{@"id": @"history-original", @"createdAt": @"2026-11-15T08:00:00Z",
            @"kind": @"text", @"contentHash": @"rich-fixture", @"text": @"Hello world",
            @"textFormats": @{NSPasteboardTypeRTF: [rtf base64EncodedStringWithOptions:0],
                NSPasteboardTypeHTML: [html base64EncodedStringWithOptions:0]}};
        NSCAssert(([@[phraseFixture] writeToFile:[directory stringByAppendingPathComponent:@"phrases.plist"] atomically:YES]), @"legacy phrase fixture");
        NSData *json = [NSJSONSerialization dataWithJSONObject:@[historyFixture] options:0 error:NULL];
        [json writeToFile:[directory stringByAppendingPathComponent:@"history.json"] atomically:YES];
        IsolatedStore *store = OpenStore(directory, board);
        NSCAssert(store.phrases.count == 1 && [store.phrases[0].primaryText isEqualToString:@"工作回复"], @"read existing phrases.plist");
        NSCAssert([store.phrases[0] matchesQuery:@"工作回复"] && [store.phrases[0] matchesQuery:@"谢谢"], @"phrase name and body search");
        NSCAssert([store.items[0].textFormats[NSPasteboardTypeHTML] isEqual:html], @"read existing rich text format");
        NSCAssert([store savePhrase:nil name:@"地址模板" text:@"上海市 · 示例地址"], @"create phrase");
        ClipItem *address = store.phrases[0];
        NSCAssert([store savePhrase:address name:@"更新的地址" text:@"上海市 · 新地址"], @"edit phrase");
        NSCAssert(store.phrases.count == 2 && [store.phrases[0].text isEqualToString:@"上海市 · 新地址"], @"edit replaces existing phrase");
        NSCAssert(![store savePhrase:nil name:@" " text:@"body"] && ![store savePhrase:nil name:@"title" text:@" \n"], @"reject empty phrase");
        IsolatedStore *reopened = OpenStore(directory, board);
        NSCAssert(reopened.phrases.count == 2 && [reopened.phrases[0].phraseName isEqualToString:@"更新的地址"], @"phrases survive reopening");
        [store deleteItem:store.phrases[0]];
        reopened = OpenStore(directory, board);
        NSCAssert(reopened.phrases.count == 1 && reopened.items.count == 1, @"delete phrase preserves history");

        ClipItem *rich = store.items[0];
        NSCAssert([store restoreItem:rich plainText:NO], @"restore rich text");
        NSCAssert([[board dataForType:NSPasteboardTypeRTF] isEqual:rtf] && [[board dataForType:NSPasteboardTypeHTML] isEqual:html], @"preserve RTF and HTML");
        NSCAssert([store restoreItem:rich plainText:YES], @"plain paste");
        NSCAssert([[board stringForType:NSPasteboardTypeString] isEqualToString:@"Hello world"] &&
            ![board.types containsObject:NSPasteboardTypeRTF] && ![board.types containsObject:NSPasteboardTypeHTML], @"remove formatting only for plain paste");
        NSCAssert(store.suppressedChangeCount == board.changeCount, @"suppress own clipboard write");
        NSCAssert([store restoreItem:store.phrases[0] plainText:NO], @"copy saved phrase");
        NSCAssert([[board stringForType:NSPasteboardTypeString] isEqualToString:store.phrases[0].text], @"full phrase copied");
        NSPasteboardItem *incoming = [NSPasteboardItem new];
        [incoming setString:@"Fresh rich copy" forType:NSPasteboardTypeString];
        [incoming setData:html forType:NSPasteboardTypeHTML];
        [board clearContents]; [board writeObjects:@[incoming]];
        [store ingestPasteboard:board];
        reopened = OpenStore(directory, board);
        NSCAssert([reopened.items[0].textFormats[NSPasteboardTypeHTML] isEqual:html], @"capture and persist rich text");
        NSCAssert([HandyMinisTransformText(@"  a  b \n c  ", HandyMinisTextActionTrimSpaces) isEqualToString:@"a b\nc"], @"trim spaces");
        NSCAssert([HandyMinisTransformText(@"中文\n段落\n\n新段落", HandyMinisTextActionUnwrap) isEqualToString:@"中文段落\n\n新段落"], @"unwrap preserves paragraphs");
        NSCAssert([HandyMinisTransformText(@" a \n\n b \t c ", HandyMinisTextActionSingleLine) isEqualToString:@"a b c"], @"single line");

        QueuePanel *panel = [[QueuePanel alloc] initWithStore:store];
        RecordingDelegate *delegate = [RecordingDelegate new]; delegate.store = store; panel.delegate = delegate;
        [[panel valueForKey:@"banner"] setHidden:YES];
        [panel changeSection:nil];
        NSSegmentedControl *sections = [panel valueForKey:@"sections"];
        NSCAssert(sections.segmentCount == 3 && [[sections labelForSegment:1] isEqualToString:@"常用语"] &&
            [[sections labelForSegment:2] isEqualToString:@"文件暂存"], @"all release sections present");
        NSCAssert([(NSView *)[panel valueForKey:@"addPhraseButton"] isHidden], @"phrase creation belongs to phrases section");
        NSCAssert([(NSTableView *)[panel valueForKey:@"table"] doubleAction] == @selector(pasteClickedRow:), @"single-click selection, double-click paste");
        Key(panel, 36, 0);
        NSCAssert(delegate.paste && !delegate.plain && delegate.chosen == store.items[0], @"return paste original");
        Key(panel, 36, NSEventModifierFlagShift);
        NSCAssert(delegate.paste && delegate.plain, @"shift-return plain paste");
        Key(panel, 36, NSEventModifierFlagCommand);
        NSCAssert(!delegate.paste && !delegate.plain, @"command-return copy");
        NSMenu *textMenu = [panel actionMenuForItem:store.items[0]];
        NSCAssert([textMenu itemWithTitle:@"保存为常用语…"] && [textMenu itemWithTitle:@"粘贴为纯文本"], @"history actions present");
        NSMenu *clean = [textMenu itemWithTitle:@"清理文本并粘贴"].submenu;
        NSCAssert(clean.numberOfItems == 3, @"all text transforms available");
        [panel contextClean:clean.itemArray[2]];
        NSCAssert(delegate.paste && delegate.plain && delegate.chosen.text.length, @"clean action reaches paste delegate");
        if (argc > 1) Snapshot(panel, [@(argv[1]) stringByAppendingString:@"-history.png"]);
        Key(panel, 124, 0);
        NSCAssert(sections.selectedSegment == 1 && [panel sectionItems].count == 1, @"right arrow opens phrases");
        NSCAssert(![(NSView *)[panel valueForKey:@"addPhraseButton"] isHidden], @"new phrase button visible");
        NSMenu *phraseMenu = [panel actionMenuForItem:store.phrases[0]];
        NSCAssert([phraseMenu itemWithTitle:@"编辑常用语…"] != nil, @"edit saved phrase action");
        Key(panel, 36, NSEventModifierFlagCommand);
        NSCAssert(delegate.chosen == store.phrases[0] && !delegate.paste, @"copy phrase from section");
        if (argc > 1) Snapshot(panel, [@(argv[1]) stringByAppendingString:@"-phrases.png"]);
        Key(panel, 123, 0);
        NSCAssert(sections.selectedSegment == 0, @"left arrow returns to history");

        NSString *first = [directory stringByAppendingPathComponent:@"设计草稿.txt"];
        NSString *second = [directory stringByAppendingPathComponent:@"会议记录.txt"];
        [@"Sample draft" writeToFile:first atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [@"Sample notes" writeToFile:second atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        ClipItem *files = [ClipItem new]; files.kind = ClipKindFiles; files.filePaths = @[first];
        NSCAssert([[panel actionMenuForItem:files] itemWithTitle:@"加入文件暂存"] != nil, @"stage from history action");
        [panel stageItem:files];
        NSCAssert(sections.selectedSegment == 2 && [panel sectionItems].count == 1, @"stage history file and switch tab");
        NSCAssert([panel stagePaths:@[first]] && [panel sectionItems].count == 1, @"deduplicate staged paths");
        NSCAssert((![panel stagePaths:@[@"relative.txt", [directory stringByAppendingPathComponent:@"missing"]]]), @"reject missing and relative files");
        [board clearContents]; [board writeObjects:@[[NSURL fileURLWithPath:second]]];
        DropFixture *drop = [DropFixture new]; drop.draggingPasteboard = board; drop.draggingSourceOperationMask = NSDragOperationCopy;
        NSView *root = [panel valueForKey:@"root"];
        NSCAssert([root draggingEntered:(id)drop] == NSDragOperationCopy, @"accept file drag");
        NSCAssert([root performDragOperation:(id)drop] && [panel sectionItems].count == 2, @"drop adds file to shelf");
        NSCAssert([(NSView *)[panel valueForKey:@"itemActions"] isHidden] &&
            ![(NSView *)[panel valueForKey:@"closeShelfButton"] isHidden], @"shelf controls");
        NSURL *dragged = (NSURL *)[panel tableView:[panel valueForKey:@"table"] pasteboardWriterForRow:0];
        NSCAssert([dragged.path isEqualToString:first], @"drag-out exports original URL");
        if (argc > 1) Snapshot(panel, [@(argv[1]) stringByAppendingString:@"-files.png"]);
        drop.draggingSource = [panel valueForKey:@"table"];
        NSCAssert([root draggingEntered:(id)drop] == NSDragOperationNone, @"ignore self-drop");
        drop.draggingSource = nil; drop.draggingSourceOperationMask = NSDragOperationMove;
        NSCAssert([root draggingEntered:(id)drop] == NSDragOperationNone, @"do not accept destructive move drags");
        Key(panel, 51, 0);
        NSCAssert([panel sectionItems].count == 1 && [NSFileManager.defaultManager fileExistsAtPath:first], @"remove from shelf without deleting file");
        Key(panel, 123, 0); Key(panel, 124, 0);
        NSCAssert([panel sectionItems].count == 1, @"shelf survives section switching");
        [panel hide];
        NSCAssert([panel sectionItems].count == 1, @"shelf survives panel hiding");
        NSCAssert([WindowTiling instancesRespondToSelector:@selector(saveLayoutNamed:completion:)] &&
            [WindowTiling instancesRespondToSelector:@selector(restoreLayoutNamed:completion:)] &&
            [WindowTiling instancesRespondToSelector:@selector(deleteLayoutNamed:)] &&
            [WindowTiling instancesRespondToSelector:@selector(layoutNames)], @"window layout API restored");
        [board releaseGlobally];
        [NSFileManager.defaultManager removeItemAtPath:directory error:NULL];
        puts("PASS: v1.0.4 data compatibility; phrase create/edit/reopen/delete/search/copy; rich/plain paste; text cleanup; three sections; file stage/drop/drag-out/remove; shortcuts; layout API");
    }
    return 0;
}
