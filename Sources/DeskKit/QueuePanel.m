#import "QueuePanel.h"
#import "AccessibilityTrust.h"
#import <ApplicationServices/ApplicationServices.h>
#import <QuartzCore/QuartzCore.h>

@interface KeyablePanel : NSPanel
@end

@implementation KeyablePanel
- (BOOL)canBecomeKeyWindow { return YES; }
@end

@interface RoundedEffectView : NSVisualEffectView
@property NSSize maskSize;
@end

@implementation RoundedEffectView
- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.material = NSVisualEffectMaterialPopover;
        self.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        self.state = NSVisualEffectStateActive;
        self.wantsLayer = YES;
        self.layer.cornerRadius = 22;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.masksToBounds = YES;
        self.layer.borderWidth = 1;
    }
    return self;
}

- (void)layout {
    [super layout];
    NSSize size = self.bounds.size;
    if (size.width <= 0 || size.height <= 0 || NSEqualSizes(size, self.maskSize)) return;
    self.maskSize = size;
    // The material is composited separately from the view's backing layer.
    self.maskImage = [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect bounds) {
        [NSColor.blackColor setFill];
        [[NSBezierPath bezierPathWithRoundedRect:bounds xRadius:22 yRadius:22] fill];
        return YES;
    }];
    [self.window invalidateShadow];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        self.layer.borderColor = [NSColor.separatorColor colorWithAlphaComponent:0.32].CGColor;
    }];
}
@end

@interface PassiveTextView : NSTextView
@end

@implementation PassiveTextView
- (BOOL)acceptsFirstResponder { return NO; }
@end

@interface ClipCellView : NSTableCellView
@property NSTextField *indexLabel;
@property NSImageView *iconView;
@property NSTextField *primaryLabel;
@property NSTextField *secondaryLabel;
@property NSTextField *timeLabel;
@property NSScrollView *textScroll;
@property NSTextView *textView;
@property (nonatomic) BOOL expanded;
@property BOOL imagePreview;
- (void)prepareTextPreview;
@end

@implementation ClipCellView

+ (NSTextField *)label {
    NSTextField *label = [NSTextField labelWithString:@""];
    label.translatesAutoresizingMaskIntoConstraints = YES;
    return label;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _indexLabel = [ClipCellView label];
        _indexLabel.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightSemibold];
        _indexLabel.alignment = NSTextAlignmentCenter;
        _primaryLabel = [ClipCellView label];
        _primaryLabel.font = [NSFont systemFontOfSize:13];
        _primaryLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _secondaryLabel = [ClipCellView label];
        _secondaryLabel.font = [NSFont systemFontOfSize:11];
        _secondaryLabel.textColor = NSColor.secondaryLabelColor;
        _secondaryLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        _timeLabel = [ClipCellView label];
        _timeLabel.font = [NSFont systemFontOfSize:11];
        _timeLabel.textColor = NSColor.secondaryLabelColor;
        _timeLabel.alignment = NSTextAlignmentRight;
        _iconView = [NSImageView new];
        _iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
        _iconView.imageAlignment = NSImageAlignCenter;
        _iconView.wantsLayer = YES;
        _iconView.layer.cornerRadius = 6;
        _iconView.layer.masksToBounds = YES;
        for (NSView *view in @[_indexLabel, _iconView, _primaryLabel, _secondaryLabel, _timeLabel]) {
            [self addSubview:view];
        }
    }
    return self;
}

- (void)prepareTextPreview {
    if (_textView) return;
    _textView = [[PassiveTextView alloc] initWithFrame:NSZeroRect];
    _textView.editable = NO;
    _textView.selectable = NO;
    _textView.drawsBackground = NO;
    _textView.font = [NSFont systemFontOfSize:13];
    _textView.textContainerInset = NSMakeSize(0, 0);
    _textView.textContainer.lineFragmentPadding = 0;
    _textView.textContainer.widthTracksTextView = NO;
    _textView.textContainer.heightTracksTextView = NO;
    _textView.horizontallyResizable = NO;
    _textView.verticallyResizable = YES;
    _textView.minSize = NSMakeSize(0, 0);
    _textView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    _textScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _textScroll.drawsBackground = NO;
    _textScroll.hasVerticalScroller = YES;
    _textScroll.autohidesScrollers = YES;
    _textScroll.borderType = NSNoBorder;
    _textScroll.documentView = _textView;
    [self addSubview:_textScroll];
}

- (void)setExpanded:(BOOL)expanded {
    _expanded = expanded;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 10;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.backgroundColor = (expanded ? [NSColor.controlAccentColor colorWithAlphaComponent:0.14] : NSColor.clearColor).CGColor;
    if (!expanded) {
        self.textScroll.hidden = YES;
        self.textView.string = @"";
        self.primaryLabel.hidden = NO;
    }
}

- (void)layout {
    [super layout];
    NSRect bounds = self.bounds;
    self.indexLabel.frame = NSMakeRect(6, bounds.size.height - 22, 18, 18);
    self.timeLabel.frame = NSMakeRect(bounds.size.width - 78, bounds.size.height - 22, 70, 16);
    CGFloat textX = 68;
    CGFloat textW = MAX(40, bounds.size.width - textX - 82);
    if (self.expanded && self.imagePreview) {
        self.primaryLabel.hidden = NO;
        self.secondaryLabel.hidden = YES;
        self.textScroll.hidden = YES;
        self.primaryLabel.maximumNumberOfLines = 1;
        self.primaryLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        self.primaryLabel.frame = NSMakeRect(textX, bounds.size.height - 24, textW, 18);
        self.iconView.frame = NSMakeRect(textX, 8, textW, MAX(32, bounds.size.height - 36));
        return;
    }
    if (self.expanded) {
        self.primaryLabel.hidden = YES;
        self.secondaryLabel.hidden = YES;
        self.textScroll.hidden = NO;
        self.iconView.frame = NSMakeRect(28, bounds.size.height - 40, 32, 32);
        self.textScroll.frame = NSMakeRect(textX, 8, textW, MAX(20, bounds.size.height - 16));
        self.textView.textContainer.containerSize = NSMakeSize(textW, CGFLOAT_MAX);
        NSLayoutManager *manager = self.textView.layoutManager;
        NSTextContainer *container = self.textView.textContainer;
        [manager ensureLayoutForTextContainer:container];
        CGFloat textHeight = ceil([manager usedRectForTextContainer:container].size.height);
        self.textView.frame = NSMakeRect(0, 0, textW, MAX(textHeight, self.textScroll.frame.size.height));
        return;
    }
    self.textScroll.hidden = YES;
    self.primaryLabel.hidden = NO;
    self.iconView.frame = NSMakeRect(28, (bounds.size.height - 32) / 2.0, 32, 32);
    self.indexLabel.frame = NSMakeRect(6, 0, 18, bounds.size.height);
    self.timeLabel.frame = NSMakeRect(bounds.size.width - 78, 0, 70, bounds.size.height);
    self.primaryLabel.maximumNumberOfLines = 1;
    self.primaryLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    if (self.secondaryLabel.hidden) {
        self.primaryLabel.frame = NSMakeRect(textX, 0, textW, bounds.size.height);
    } else {
        self.primaryLabel.frame = NSMakeRect(textX, bounds.size.height / 2.0 - 1, textW, bounds.size.height / 2.0);
        self.secondaryLabel.frame = NSMakeRect(textX, 4, textW, bounds.size.height / 2.0 - 4);
    }
}

@end

@interface ClipRowView : NSTableRowView
@end

@implementation ClipRowView
- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) self.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
    return self;
}

- (BOOL)wantsUpdateLayer { return NO; }
- (BOOL)isOpaque { return NO; }
- (void)drawSelectionInRect:(NSRect)dirtyRect {}
- (void)drawRect:(NSRect)dirtyRect {}

- (void)layout {
    [super layout];
    self.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
    for (NSView *subview in self.subviews) {
        if (![subview isKindOfClass:[ClipCellView class]]) subview.hidden = YES;
    }
}
@end

@class QueuePanel;

@interface ClickTableView : NSTableView
@property (nonatomic, weak) QueuePanel *owner;
@end

@interface PanelRootView : NSView
@property NSTextField *titleLabel;
@property NSTextField *countLabel;
@property NSTextField *shortcutLabel;
@property NSSearchField *searchField;
@property NSView *banner;
@property NSScrollView *scrollView;
@property NSTextField *emptyLabel;
@property NSTextField *footer;
@property NSTableView *table;
@end

@implementation PanelRootView
- (void)layout {
    [super layout];
    NSRect bounds = NSInsetRect(self.bounds, 18, 16);
    CGFloat top = NSMaxY(bounds);

    [self.titleLabel sizeToFit];
    [self.countLabel sizeToFit];
    NSRect titleFrame = self.titleLabel.frame;
    titleFrame.origin = NSMakePoint(bounds.origin.x, top - 25);
    titleFrame.size.height = 25;
    self.titleLabel.frame = titleFrame;

    NSRect countFrame = self.countLabel.frame;
    countFrame.origin = NSMakePoint(NSMaxX(titleFrame) + 8, top - 20);
    countFrame.size.height = 18;
    self.countLabel.frame = countFrame;

    [self.shortcutLabel sizeToFit];
    NSRect shortcutFrame = self.shortcutLabel.frame;
    shortcutFrame.size.height = 18;
    shortcutFrame.origin = NSMakePoint(NSMaxX(bounds) - shortcutFrame.size.width, top - 20);
    self.shortcutLabel.frame = shortcutFrame;
    self.searchField.frame = NSMakeRect(bounds.origin.x, top - 25 - 8 - 30, bounds.size.width, 30);

    CGFloat cursor = top - 25 - 8 - 30 - 8;
    if (!self.banner.hidden) {
        self.banner.frame = NSMakeRect(bounds.origin.x, cursor - 58, bounds.size.width, 58);
        cursor -= 58 + 8;
    }
    self.footer.frame = NSMakeRect(bounds.origin.x, bounds.origin.y, bounds.size.width, 16);
    CGFloat listBottom = bounds.origin.y + 16 + 8;
    self.scrollView.frame = NSMakeRect(bounds.origin.x, listBottom, bounds.size.width, MAX(40, cursor - listBottom));
    self.emptyLabel.frame = NSInsetRect(self.scrollView.frame, 16, 28);
    self.emptyLabel.preferredMaxLayoutWidth = MAX(40, self.scrollView.frame.size.width - 32);
    self.table.tableColumns.firstObject.width = self.scrollView.contentSize.width;
}
@end

@interface QueuePanel () <NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>
@property ClipboardStore *store;
@property KeyablePanel *panel;
@property NSTextField *countLabel;
@property NSTextField *shortcutLabel;
@property NSSearchField *searchField;
@property NSView *banner;
@property NSScrollView *scrollView;
@property ClickTableView *table;
@property NSTextField *emptyLabel;
@property NSMutableArray<ClipItem *> *rows;
@property id keyMonitor;
@property BOOL updatingSelection;
@property NSInteger lastSelectedRow;
- (void)pasteRow:(NSInteger)row;
- (void)pasteItem:(ClipItem *)item;
- (ClipItem *)itemForRow:(NSInteger)row;
@end

@implementation ClickTableView
- (void)mouseDown:(NSEvent *)event {
    [super mouseDown:event];
    ClipItem *item = [self.owner itemForRow:self.clickedRow];
    if (!item) return;
    // Wait until this mouse tracking turn ends, or the target app receives the click.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.owner pasteItem:item];
    });
}
@end

static NSString *RelativeTime(NSDate *date) {
    NSTimeInterval seconds = [[NSDate date] timeIntervalSinceDate:date];
    if (seconds < 10) return @"刚刚";
    if (seconds < 60) return [NSString stringWithFormat:@"%d 秒前", (int)seconds];
    int minutes = (int)(seconds / 60);
    if (minutes < 60) return [NSString stringWithFormat:@"%d 分钟前", minutes];
    int hours = minutes / 60;
    if (hours < 24) return [NSString stringWithFormat:@"%d 小时前", hours];
    int days = hours / 24;
    if (days < 7) return [NSString stringWithFormat:@"%d 天前", days];
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
        formatter.dateFormat = @"M月d日";
    });
    return [formatter stringFromDate:date];
}

static NSTextField *MakeLabel(NSString *text, CGFloat size, NSFontWeight weight) {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.translatesAutoresizingMaskIntoConstraints = YES;
    return label;
}

@implementation QueuePanel

- (instancetype)initWithStore:(ClipboardStore *)store {
    self = [super init];
    if (self) {
        _store = store;
        _rows = [NSMutableArray array];
        _lastSelectedRow = -1;
        [self buildPanel];
        [self installKeyMonitor];
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(itemsChanged:)
                                                   name:CopyQueueItemsDidChangeNotification
                                                 object:store];
    }
    return self;
}

- (void)dealloc {
    if (_keyMonitor) [NSEvent removeMonitor:_keyMonitor];
}

- (BOOL)isVisible {
    return self.panel.isVisible;
}

- (void)show {
    self.searchField.stringValue = @"";
    [self refreshShortcutTitle];
    [self refreshBanner];
    [self reloadKeepingSelection:NO];
    [self placeOnMouseScreen];
    BOOL animate = !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    self.panel.alphaValue = animate ? 0.78 : 1;
    [self.panel orderFrontRegardless];
    [self.panel makeKeyWindow];
    [self.panel makeFirstResponder:self.searchField];
    if (!animate) return;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.14;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        self.panel.animator.alphaValue = 1;
    }];
}

- (void)hide {
    [self.panel orderOut:nil];
}

- (void)windowDidResignKey:(NSNotification *)notification {
    // Defer until AppKit finishes the current key-window transition.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.panel.isVisible && !self.panel.isKeyWindow) [self hide];
    });
}

#pragma mark - Construction

- (void)buildPanel {
    self.panel = [[KeyablePanel alloc] initWithContentRect:NSMakeRect(0, 0, 460, 520)
                                                 styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                   backing:NSBackingStoreBuffered
                                                     defer:NO];
    self.panel.delegate = self;
    self.panel.opaque = NO;
    self.panel.backgroundColor = NSColor.clearColor;
    self.panel.hasShadow = YES;
    self.panel.floatingPanel = YES;
    self.panel.level = NSPopUpMenuWindowLevel;
    self.panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                    NSWindowCollectionBehaviorFullScreenAuxiliary |
                                    NSWindowCollectionBehaviorCanJoinAllApplications;
    self.panel.movableByWindowBackground = YES;
    self.panel.hidesOnDeactivate = NO;
    self.panel.becomesKeyOnlyIfNeeded = NO;
    self.panel.releasedWhenClosed = NO;

    RoundedEffectView *effect = [RoundedEffectView new];
    self.panel.contentView = effect;

    PanelRootView *root = [PanelRootView new];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [effect addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:effect.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:effect.trailingAnchor],
        [root.topAnchor constraintEqualToAnchor:effect.topAnchor],
        [root.bottomAnchor constraintEqualToAnchor:effect.bottomAnchor],
    ]];

    NSTextField *title = MakeLabel(@"最近复制", 19, NSFontWeightSemibold);
    self.countLabel = MakeLabel(@"0", 12, NSFontWeightMedium);
    self.countLabel.textColor = NSColor.secondaryLabelColor;
    NSTextField *shortcut = MakeLabel(@"⌘⇧C", 11, NSFontWeightMedium);
    shortcut.textColor = NSColor.secondaryLabelColor;
    shortcut.alignment = NSTextAlignmentRight;
    self.shortcutLabel = shortcut;

    self.searchField = [NSSearchField new];
    self.searchField.placeholderString = @"搜索复制内容";
    self.searchField.delegate = self;
    self.searchField.font = [NSFont systemFontOfSize:13];
    self.searchField.focusRingType = NSFocusRingTypeNone;
    self.searchField.translatesAutoresizingMaskIntoConstraints = YES;

    self.banner = [self makeBanner];

    self.table = [[ClickTableView alloc] initWithFrame:NSZeroRect];
    self.table.owner = self;
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"main"];
    [self.table addTableColumn:column];
    self.table.headerView = nil;
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.backgroundColor = NSColor.clearColor;
    self.table.rowHeight = 48;
    self.table.intercellSpacing = NSMakeSize(0, 4);
    self.table.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
    self.table.allowsMultipleSelection = NO;
    self.table.allowsEmptySelection = NO;
    self.table.focusRingType = NSFocusRingTypeNone;
    self.table.menu = [self makeContextMenu];
    if (@available(macOS 11.0, *)) {
        self.table.style = NSTableViewStylePlain;
    }

    self.scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.drawsBackground = NO;
    self.scrollView.borderType = NSNoBorder;
    self.scrollView.documentView = self.table;
    self.scrollView.translatesAutoresizingMaskIntoConstraints = YES;

    self.emptyLabel = [NSTextField wrappingLabelWithString:@"还没有复制内容"];
    self.emptyLabel.alignment = NSTextAlignmentCenter;
    self.emptyLabel.font = [NSFont systemFontOfSize:13];
    self.emptyLabel.textColor = NSColor.secondaryLabelColor;
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = YES;
    self.emptyLabel.hidden = YES;

    NSTextField *footer = MakeLabel(@"↑↓ 选择      ↩ 粘贴      ⌘↩ 复制      ⌫ 删除      esc 关闭", 11, NSFontWeightRegular);
    footer.textColor = NSColor.secondaryLabelColor;
    footer.alignment = NSTextAlignmentCenter;

    root.titleLabel = title;
    root.countLabel = self.countLabel;
    root.shortcutLabel = shortcut;
    root.searchField = self.searchField;
    root.banner = self.banner;
    root.scrollView = self.scrollView;
    root.emptyLabel = self.emptyLabel;
    root.footer = footer;
    root.table = self.table;
    for (NSView *view in @[title, self.countLabel, shortcut, self.searchField, self.banner, self.scrollView, self.emptyLabel, footer]) {
        [root addSubview:view];
    }
}

- (NSView *)makeBanner {
    NSView *banner = [NSView new];
    banner.translatesAutoresizingMaskIntoConstraints = YES;
    banner.wantsLayer = YES;
    banner.layer.backgroundColor = [NSColor.systemOrangeColor colorWithAlphaComponent:0.16].CGColor;
    banner.layer.cornerRadius = 8;
    NSTextField *text = [NSTextField wrappingLabelWithString:@"还不能自动粘贴。在辅助功能里允许 DeskKit 后，回车会直接贴到刚才的应用。"];
    text.font = [NSFont systemFontOfSize:11];
    text.textColor = NSColor.labelColor;
    text.translatesAutoresizingMaskIntoConstraints = NO;
    NSButton *button = [NSButton buttonWithTitle:@"打开设置" target:self action:@selector(openAccessibility:)];
    button.bezelStyle = NSBezelStyleInline;
    button.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [banner addSubview:text];
    [banner addSubview:button];
    [NSLayoutConstraint activateConstraints:@[
        [text.leadingAnchor constraintEqualToAnchor:banner.leadingAnchor constant:8],
        [text.topAnchor constraintEqualToAnchor:banner.topAnchor constant:6],
        [text.bottomAnchor constraintEqualToAnchor:banner.bottomAnchor constant:-6],
        [button.leadingAnchor constraintEqualToAnchor:text.trailingAnchor constant:8],
        [button.trailingAnchor constraintEqualToAnchor:banner.trailingAnchor constant:-8],
        [button.centerYAnchor constraintEqualToAnchor:banner.centerYAnchor],
        [button.widthAnchor constraintEqualToConstant:72],
    ]];
    return banner;
}

- (NSMenu *)makeContextMenu {
    NSMenu *menu = [NSMenu new];
    NSMenuItem *paste = [[NSMenuItem alloc] initWithTitle:@"粘贴" action:@selector(contextPaste:) keyEquivalent:@""];
    paste.target = self;
    NSMenuItem *copy = [[NSMenuItem alloc] initWithTitle:@"仅复制" action:@selector(contextCopy:) keyEquivalent:@""];
    copy.target = self;
    NSMenuItem *delete = [[NSMenuItem alloc] initWithTitle:@"删除" action:@selector(contextDelete:) keyEquivalent:@""];
    delete.target = self;
    [menu addItem:paste];
    [menu addItem:copy];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:delete];
    return menu;
}

- (void)placeOnMouseScreen {
    NSPoint mouse = NSEvent.mouseLocation;
    NSScreen *screen = nil;
    for (NSScreen *candidate in NSScreen.screens) {
        if (NSMouseInRect(mouse, candidate.frame, NO)) {
            screen = candidate;
            break;
        }
    }
    if (!screen) screen = NSScreen.mainScreen;
    NSRect visible = screen.visibleFrame;
    NSRect frame = self.panel.frame;
    frame.origin.x = NSMidX(visible) - frame.size.width / 2.0;
    frame.origin.y = NSMidY(visible) - frame.size.height / 2.0 + 30;
    [self.panel setFrame:frame display:NO];
}

- (void)refreshBanner {
    self.banner.hidden = DeskKitAccessibilityTrusted();
    self.banner.superview.needsLayout = YES;
    [self.banner.superview layoutSubtreeIfNeeded];
    self.panel.contentView.needsLayout = YES;
}

- (void)openAccessibility:(id)sender {
    [self.delegate queuePanelDidRequestAccessibility:self];
}

- (void)setShortcutTitle:(NSString *)title {
    if (title.length == 0) title = @"⌘⇧C";
    self.shortcutLabel.stringValue = title;
    self.panel.contentView.needsLayout = YES;
}

- (void)refreshShortcutTitle {
    [self setShortcutTitle:[self.delegate queuePanelShortcutTitle:self]];
}

#pragma mark - Rows

- (void)itemsChanged:(NSNotification *)note {
    if (!self.panel.isVisible) return;
    [self reloadKeepingSelection:YES];
}

- (void)controlTextDidChange:(NSNotification *)obj {
    [self reloadKeepingSelection:NO];
}

- (NSArray<ClipItem *> *)filteredItems {
    NSString *query = [self.searchField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (query.length == 0) return self.store.items;
    NSMutableArray<ClipItem *> *matched = [NSMutableArray array];
    for (ClipItem *item in self.store.items) {
        if ([item matchesQuery:query]) [matched addObject:item];
    }
    return matched;
}

- (void)reloadKeepingSelection:(BOOL)keep {
    NSInteger previous = keep ? self.table.selectedRow : 0;
    ClipItem *selectedItem = keep ? [self itemForRow:previous] : nil;
    self.updatingSelection = YES;
    [self.rows removeAllObjects];
    [self.rows addObjectsFromArray:[self filteredItems]];
    [self.table reloadData];
    self.countLabel.stringValue = [NSString stringWithFormat:@"%lu", (unsigned long)self.store.items.count];
    [self.countLabel sizeToFit];
    BOOL searching = [self.searchField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0;
    if (self.rows.count == 0) {
        self.emptyLabel.hidden = NO;
        self.emptyLabel.stringValue = (self.store.items.count == 0)
            ? @"还没有复制内容\n复制文本、图片或文件后，会出现在这里。"
            : (searching ? @"没有匹配的内容" : @"还没有复制内容");
    } else {
        self.emptyLabel.hidden = YES;
        NSUInteger retainedSelection = selectedItem ? [self.rows indexOfObjectIdenticalTo:selectedItem] : NSNotFound;
        if (retainedSelection != NSNotFound) previous = retainedSelection;
        if (previous < 0) previous = 0;
        if (previous >= (NSInteger)self.rows.count) previous = self.rows.count - 1;
        [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:previous] byExtendingSelection:NO];
    }
    self.lastSelectedRow = -1;
    self.updatingSelection = NO;
    [self updateSelectedRows];
    self.panel.contentView.needsLayout = YES;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.rows.count;
}

- (NSString *)expandedTextForItem:(ClipItem *)item {
    switch (item.kind) {
        case ClipKindText:
            return item.text.length > 0 ? item.text : @"空白文本";
        case ClipKindFiles:
            return item.filePaths.count > 0 ? [item.filePaths componentsJoinedByString:@"\n"] : item.primaryText;
        case ClipKindImage:
            return item.primaryText;
    }
    return item.primaryText;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    if (row != tableView.selectedRow || row < 0 || row >= (NSInteger)self.rows.count) return 48;
    ClipItem *item = self.rows[row];
    CGFloat width = MAX(80, tableView.bounds.size.width - 68 - 82);
    if (item.kind == ClipKindImage) {
        NSImage *image = [self.store thumbnailForItem:item];
        CGFloat imageHeight = 120;
        if (image.size.width > 0) {
            imageHeight = image.size.height * (width / image.size.width);
            imageHeight = MIN(MAX(imageHeight, 64), 240);
        }
        return 36 + imageHeight;
    }
    NSString *text = [self expandedTextForItem:item];
    NSRect rect = [text boundingRectWithSize:NSMakeSize(width, CGFLOAT_MAX)
                                      options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                   attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:13]}];
    return MIN(MAX(48, ceil(rect.size.height) + 20), 420);
}

- (void)configureCell:(ClipCellView *)cell row:(NSInteger)row {
    ClipItem *item = self.rows[row];
    BOOL selected = row == self.table.selectedRow;
    cell.imagePreview = selected && item.kind == ClipKindImage;
    cell.expanded = selected;
    cell.indexLabel.stringValue = row < 9 ? [NSString stringWithFormat:@"%ld", (long)row + 1] : @"·";
    cell.indexLabel.textColor = selected ? NSColor.controlAccentColor : NSColor.secondaryLabelColor;
    cell.primaryLabel.stringValue = item.primaryText;
    NSString *secondary = item.secondaryText;
    cell.secondaryLabel.hidden = selected || secondary.length == 0;
    cell.secondaryLabel.stringValue = secondary ?: @"";
    if (selected && item.kind != ClipKindImage) {
        [cell prepareTextPreview];
        cell.textView.textColor = NSColor.labelColor;
        NSString *preview = [self expandedTextForItem:item];
        if (![cell.textView.string isEqualToString:preview]) cell.textView.string = preview;
    }
    cell.textScroll.hidden = !selected || item.kind == ClipKindImage;
    cell.primaryLabel.hidden = selected && item.kind != ClipKindImage;
    cell.timeLabel.stringValue = RelativeTime(item.createdAt);
    NSImage *thumbnail = item.kind == ClipKindImage ? [self.store thumbnailForItem:item] : nil;
    if (thumbnail) {
        cell.iconView.image = thumbnail;
        cell.iconView.contentTintColor = nil;
        cell.iconView.layer.backgroundColor = NSColor.clearColor.CGColor;
    } else {
        NSString *symbol = item.kind == ClipKindFiles ? @"doc" : (item.kind == ClipKindImage ? @"photo" : @"text.alignleft");
        cell.iconView.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
        cell.iconView.contentTintColor = NSColor.secondaryLabelColor;
        cell.iconView.layer.backgroundColor = [NSColor.labelColor colorWithAlphaComponent:0.06].CGColor;
    }
    [cell setNeedsLayout:YES];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [self updateSelectedRows];
}

- (void)updateSelectedRows {
    if (self.updatingSelection) return;
    NSInteger selected = self.table.selectedRow;
    if (selected == self.lastSelectedRow) return;
    self.updatingSelection = YES;
    NSMutableIndexSet *rows = [NSMutableIndexSet indexSet];
    if (self.lastSelectedRow >= 0 && self.lastSelectedRow < (NSInteger)self.rows.count) [rows addIndex:self.lastSelectedRow];
    if (selected >= 0 && selected < (NSInteger)self.rows.count) [rows addIndex:selected];
    self.lastSelectedRow = selected;
    if (rows.count > 0) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0;
            [self.table noteHeightOfRowsWithIndexesChanged:rows];
        }];
        [rows enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
            NSView *cell = [self.table viewAtColumn:0 row:index makeIfNecessary:NO];
            if ([cell isKindOfClass:[ClipCellView class]]) [self configureCell:(ClipCellView *)cell row:index];
        }];
    }
    if (selected >= 0) [self.table scrollRowToVisible:selected];
    self.updatingSelection = NO;
}

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
    ClipRowView *rowView = [tableView makeViewWithIdentifier:@"row" owner:self];
    if (!rowView) {
        rowView = [ClipRowView new];
        rowView.identifier = @"row";
    }
    rowView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
    return rowView;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    ClipCellView *cell = [tableView makeViewWithIdentifier:@"clip" owner:self];
    if (!cell) {
        cell = [[ClipCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = @"clip";
    }
    [self configureCell:cell row:row];
    return cell;
}

#pragma mark - Actions

- (ClipItem *)itemForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.rows.count) return nil;
    return self.rows[row];
}

- (NSInteger)contextRow {
    return self.table.clickedRow >= 0 ? self.table.clickedRow : self.table.selectedRow;
}

- (void)pasteRow:(NSInteger)row {
    [self pasteItem:[self itemForRow:row]];
}

- (void)pasteItem:(ClipItem *)item {
    if (!item) return;
    [self.delegate queuePanel:self didChooseItem:item paste:YES];
}

- (void)contextPaste:(id)sender {
    [self pasteRow:[self contextRow]];
}

- (void)contextCopy:(id)sender {
    ClipItem *item = [self itemForRow:[self contextRow]];
    if (item) [self.delegate queuePanel:self didChooseItem:item paste:NO];
}

- (void)contextDelete:(id)sender {
    [self deleteRow:[self contextRow]];
}

- (void)deleteRow:(NSInteger)row {
    ClipItem *item = [self itemForRow:row];
    if (!item) return;
    [self.delegate queuePanel:self didDeleteItem:item];
}

#pragma mark - Keyboard

- (void)installKeyMonitor {
    __weak QueuePanel *weakSelf = self;
    self.keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        QueuePanel *panel = weakSelf;
        if (!panel || !panel.panel.isVisible || !panel.panel.isKeyWindow) return event;
        return [panel handleKey:event];
    }];
}

- (NSEvent *)handleKey:(NSEvent *)event {
    id responder = self.panel.firstResponder;
    if ([responder isKindOfClass:[NSTextView class]] && [(NSTextView *)responder hasMarkedText]) {
        return event;
    }
    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    switch (event.keyCode) {
        case 53:
            [self hide];
            return nil;
        case 126:
            [self moveSelection:-1];
            return nil;
        case 125:
            [self moveSelection:1];
            return nil;
        case 36:
        case 76: {
            ClipItem *item = [self itemForRow:self.table.selectedRow];
            if (!item) return nil;
            BOOL copyOnly = (flags & NSEventModifierFlagCommand) != 0;
            [self.delegate queuePanel:self didChooseItem:item paste:!copyOnly];
            return nil;
        }
        case 51: {
            BOOL searchEmpty = self.searchField.stringValue.length == 0;
            if ((flags & NSEventModifierFlagCommand) || searchEmpty) {
                [self deleteRow:self.table.selectedRow];
                return nil;
            }
            return event;
        }
        default:
            break;
    }
    if ((flags & NSEventModifierFlagCommand) &&
        (flags & (NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagControl)) == 0) {
        NSString *chars = event.charactersIgnoringModifiers;
        NSInteger number = chars.integerValue;
        if (number >= 1 && number <= 9) {
            [self pasteRow:number - 1];
            return nil;
        }
    }
    return event;
}

- (void)moveSelection:(NSInteger)delta {
    if (self.rows.count == 0) return;
    NSInteger row = self.table.selectedRow;
    if (row < 0) row = 0;
    row = MIN(MAX(0, row + delta), (NSInteger)self.rows.count - 1);
    [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [self.table scrollRowToVisible:row];
}

@end
