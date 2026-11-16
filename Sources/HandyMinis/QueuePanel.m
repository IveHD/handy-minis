#import "TextActions.h"
#import "QueuePanel.h"
#import "AccessibilityTrust.h"
#import "Theme.h"
#import <ApplicationServices/ApplicationServices.h>
#import <QuartzCore/QuartzCore.h>

@interface KeyablePanel : NSPanel
@end

@implementation KeyablePanel
- (BOOL)canBecomeKeyWindow { return YES; }
@end

@interface PassiveTextView : NSTextView
@end

@implementation PassiveTextView
- (BOOL)acceptsFirstResponder { return NO; }
@end

@interface FlatSearchFieldCell : NSSearchFieldCell
@end
@implementation FlatSearchFieldCell
- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view {
    [HMTheme.canvas setFill];
    [[NSBezierPath bezierPathWithRoundedRect:frame xRadius:8 yRadius:8] fill];
    [super drawInteriorWithFrame:frame inView:view];
}
@end

@interface FlatSearchField : NSSearchField
@end
@implementation FlatSearchField
+ (Class)cellClass { return FlatSearchFieldCell.class; }
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
@property (nonatomic, copy) NSString *representedImage;
@property (nonatomic, copy) NSString *requestedImage;
@property (nonatomic, copy) NSString *laidOutText;
@property CGFloat laidOutWidth;
@property CGFloat textHeight;
@property NSColor *selectionColor;
@property NSColor *iconBackgroundColor;
- (void)applyColors;
- (void)showThumbnail:(NSImage *)image;
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
        self.wantsLayer = YES;
        self.layer.cornerRadius = 10;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        _selectionColor = HMTheme.selection;
        _iconBackgroundColor = HMTheme.iconBackground;
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
    _textView.layoutManager.allowsNonContiguousLayout = YES;
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

- (void)applyColors {
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        self.layer.backgroundColor = (self.expanded ? self.selectionColor : NSColor.clearColor).CGColor;
        self.iconView.layer.backgroundColor = (self.iconView.contentTintColor ? self.iconBackgroundColor : NSColor.clearColor).CGColor;
    }];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self applyColors];
}

- (void)showThumbnail:(NSImage *)image {
    self.iconView.image = image;
    self.iconView.contentTintColor = nil;
    [self applyColors];
}

- (void)setExpanded:(BOOL)expanded {
    if (_expanded == expanded) return;
    _expanded = expanded;
    [self applyColors];
    if (!expanded) {
        self.textScroll.hidden = YES;
        // Retain bounded text/layout for returning to an already-visible row.
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
        if (!self.laidOutText || self.laidOutWidth != textW) {
            self.textView.textContainer.containerSize = NSMakeSize(textW, CGFLOAT_MAX);
            NSLayoutManager *manager = self.textView.layoutManager;
            NSTextContainer *container = self.textView.textContainer;
            [manager ensureLayoutForTextContainer:container];
            self.textHeight = ceil([manager usedRectForTextContainer:container].size.height);
            self.laidOutText = self.textView.string;
            self.laidOutWidth = textW;
        }
        self.textView.frame = NSMakeRect(0, 0, textW, MAX(self.textHeight, self.textScroll.frame.size.height));
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

typedef NS_ENUM(NSInteger, ClipboardSection) {
    ClipboardSectionHistory,
    ClipboardSectionPhrases,
    ClipboardSectionFiles,
    ClipboardSectionCount,
};

@interface ClickTableView : NSTableView
@property (nonatomic, weak) QueuePanel *owner;
@end

@interface PanelRootView : NSView
@property (weak) QueuePanel *owner;
@property NSSegmentedControl *sections;
@property NSButton *addPhrase;
@property NSButton *actions;
@property NSButton *closeShelf;
@property NSStackView *itemActions;
@property NSImageView *brandIcon;
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

@interface QueuePanel (FileDrop)
- (BOOL)acceptFileDrop:(id<NSDraggingInfo>)info;
@end

@implementation PanelRootView
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info {
    NSPasteboard *pasteboard = info.draggingPasteboard;
    BOOL fileURLs = [pasteboard canReadObjectForClasses:@[NSURL.class]
        options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    return info.draggingSource != self.table && (info.draggingSourceOperationMask & NSDragOperationCopy) && fileURLs
        ? NSDragOperationCopy : NSDragOperationNone;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)info {
    return [self.owner acceptFileDrop:info];
}

- (void)layout {
    [super layout];
    NSRect bounds = NSInsetRect(self.bounds, 18, 16);
    CGFloat top = NSMaxY(bounds);

    CGFloat headerCenterY = top - 12.5;
    [self.titleLabel sizeToFit];
    NSRect titleFrame = self.titleLabel.frame;
    self.brandIcon.frame = NSMakeRect(NSMinX(bounds), headerCenterY - 11, 22, 22);
    titleFrame.size.height = 25;
    titleFrame.origin = NSMakePoint(NSMaxX(self.brandIcon.frame) + 5, headerCenterY - NSHeight(titleFrame) / 2);
    self.titleLabel.frame = titleFrame;

    NSRect countFrame = NSMakeRect(NSMaxX(titleFrame) + 6, headerCenterY - 9, 28, 18);
    self.countLabel.frame = countFrame;

    [self.sections sizeToFit];
    NSRect tabFrame = self.sections.frame;
    tabFrame.origin = NSMakePoint(NSMaxX(countFrame) + 12, headerCenterY - NSHeight(tabFrame) / 2);
    self.sections.frame = tabFrame;
    [self.shortcutLabel sizeToFit];
    NSRect shortcutFrame = self.shortcutLabel.frame;
    shortcutFrame.size.height = 18;
    shortcutFrame.origin = NSMakePoint(NSMaxX(bounds) - NSWidth(shortcutFrame), headerCenterY - NSHeight(shortcutFrame) / 2);
    self.shortcutLabel.frame = shortcutFrame;
    CGFloat right = NSMaxX(bounds);
    for (NSButton *button in @[self.closeShelf, self.addPhrase, self.actions]) {
        if (button.hidden) continue;
        [button sizeToFit];
        CGFloat width = MAX(64, NSWidth(button.frame));
        button.frame = NSMakeRect(right - width, top - 62, width, 26);
        right -= width + 8;
    }
    self.searchField.frame = NSMakeRect(bounds.origin.x, top - 63, right - bounds.origin.x, 30);

    CGFloat cursor = top - 25 - 8 - 30 - 8;
    if (!self.banner.hidden) {
        self.banner.frame = NSMakeRect(bounds.origin.x, cursor - 58, bounds.size.width, 58);
        cursor -= 58 + 8;
    }
    // Place the toolbar and footer outside the scrolling viewport.
    self.footer.frame = NSMakeRect(bounds.origin.x, bounds.origin.y, bounds.size.width, 16);
    CGFloat listBottom = bounds.origin.y + 16 + 8;
    if (!self.itemActions.hidden) {
        self.itemActions.frame = NSMakeRect(bounds.origin.x, listBottom, bounds.size.width, 28);
        listBottom += 36;
    }
    self.scrollView.frame = NSMakeRect(bounds.origin.x, listBottom, bounds.size.width, MAX(0, cursor - listBottom));
    self.emptyLabel.frame = NSInsetRect(self.scrollView.frame, 16, MIN(28, NSHeight(self.scrollView.frame) / 2));
    self.emptyLabel.preferredMaxLayoutWidth = MAX(40, self.scrollView.frame.size.width - 32);
    NSTableColumn *column = self.table.tableColumns.firstObject;
    CGFloat listWidth = self.scrollView.contentSize.width;
    if (column.width != listWidth) column.width = listWidth;
}
@end

@interface QueuePanel () <NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>
@property ClipboardStore *store;
@property KeyablePanel *panel;
@property (weak) PanelRootView *root;
@property NSTextField *countLabel;
@property NSTextField *shortcutLabel;
@property NSSearchField *searchField;
@property NSView *banner;
@property NSScrollView *scrollView;
@property ClickTableView *table;
@property NSTextField *emptyLabel;
@property NSMutableArray<ClipItem *> *rows;
@property NSMutableArray<ClipItem *> *shelfItems;
@property (weak) NSButton *addPhraseButton;
@property (weak) NSButton *actionsButton;
@property (weak) NSTextField *footer;
@property (weak) NSButton *closeShelfButton;
@property (weak) NSStackView *itemActions;
@property (weak) NSButton *pasteButton;
@property (weak) NSButton *plainPasteButton;
@property (weak) NSButton *saveButton;
@property (weak) NSButton *secondaryButton;
@property id keyMonitor;
@property NSSegmentedControl *sections;
@property BOOL updatingSelection;
@property NSInteger lastSelectedRow;
@property NSMapTable<ClipItem *, NSDictionary *> *heightCache;
@property NSWindow *fullTextWindow;
- (void)pasteRow:(NSInteger)row;
- (void)pasteItem:(ClipItem *)item;
- (ClipItem *)itemForRow:(NSInteger)row;
- (NSMenu *)actionMenuForItem:(ClipItem *)item;
- (BOOL)showingShelf;
- (void)updateActionButtons;
@end

@implementation ClickTableView
- (NSMenu *)menuForEvent:(NSEvent *)event {
    NSInteger row = [self rowAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    ClipItem *item = [self.owner itemForRow:row];
    if (!item) return nil;
    [self selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    return [self.owner actionMenuForItem:item];
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
        _heightCache = [NSMapTable weakToStrongObjectsMapTable];
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
    self.sections.selectedSegment = ClipboardSectionHistory;
    [self refreshShortcutTitle];
    [self refreshBanner];
    [self placeOnMouseScreen];
    [self changeSection:nil];
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
    // The shelf remains available while users gather files in another app.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.panel.isVisible && !self.panel.isKeyWindow && !self.panel.attachedSheet && ![self showingShelf]) [self hide];
    });
}

#pragma mark - Construction

- (void)buildPanel {
    self.panel = [[KeyablePanel alloc] initWithContentRect:NSMakeRect(0, 0, 500, 520)
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

    HMPanelSurfaceView *effect = [HMPanelSurfaceView new];
    self.panel.contentView = effect;

    PanelRootView *root = [PanelRootView new];
    root.owner = self;
    self.root = root;
    [root registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [effect addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:effect.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:effect.trailingAnchor],
        [root.topAnchor constraintEqualToAnchor:effect.topAnchor],
        [root.bottomAnchor constraintEqualToAnchor:effect.bottomAnchor],
    ]];

    NSURL *iconURL = [NSBundle.mainBundle URLForResource:@"AppIcon" withExtension:@"icns"];
    NSImage *icon = iconURL ? [[NSImage alloc] initWithContentsOfURL:iconURL] : NSApp.applicationIconImage;
    NSImageView *brand = [NSImageView imageViewWithImage:icon];
    brand.imageScaling = NSImageScaleProportionallyUpOrDown;
    [brand setAccessibilityElement:NO];
    root.brandIcon = brand;
    NSTextField *title = MakeLabel(@"HandyMinis", 18, NSFontWeightSemibold);
    [self.panel setAccessibilityLabel:@"HandyMinis 剪贴板"];
    self.sections = [NSSegmentedControl segmentedControlWithLabels:@[@"历史", @"常用语", @"文件暂存"]
        trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(changeSection:)];
    self.sections.selectedSegment = ClipboardSectionHistory;
    self.sections.toolTip = @"← → 切换分区";
    [self.sections setAccessibilityLabel:@"剪贴板分区"];
    NSButton *addPhrase = [NSButton buttonWithTitle:@"新建常用语" target:self action:@selector(newPhrase:)];
    root.sections = self.sections;
    root.addPhrase = addPhrase;
    self.addPhraseButton = addPhrase;
    NSButton *actions = [NSButton buttonWithTitle:@"操作 ▾" target:self action:@selector(showActions:)];
    actions.toolTip = @"⌥↩ 打开选中条目的操作";
    [actions setAccessibilityLabel:@"选中条目的操作"];
    root.actions = actions;
    self.actionsButton = actions;
    NSButton *closeShelf = [NSButton buttonWithTitle:@"关闭" target:self action:@selector(closeShelf:)];
    [closeShelf setAccessibilityLabel:@"关闭文件暂存"];
    root.closeShelf = closeShelf;
    self.closeShelfButton = closeShelf;
    closeShelf.hidden = YES;
    NSButton *paste = [NSButton buttonWithTitle:@"粘贴 ↩" target:self action:@selector(pasteSelection:)];
    NSButton *plainPaste = [NSButton buttonWithTitle:@"去格式粘贴 ⇧↩" target:self action:@selector(pastePlainSelection:)];
    NSButton *save = [NSButton buttonWithTitle:@"存为常用语 ⌃↩" target:self action:@selector(saveSelection:)];
    NSButton *more = [NSButton buttonWithTitle:@"更多 ▾" target:self action:@selector(showActions:)];
    more.toolTip = @"⌥↩ 打开更多操作";
    for (NSButton *button in @[addPhrase, actions, closeShelf, paste, plainPaste, save, more]) {
        button.bezelStyle = NSBezelStyleRecessed;
        button.showsBorderOnlyWhileMouseInside = YES;
    }
    NSStackView *itemActions = [NSStackView stackViewWithViews:@[paste, plainPaste, save, more]];
    itemActions.spacing = 4;
    itemActions.distribution = NSStackViewDistributionFillProportionally;
    itemActions.autoresizingMask = NSViewNotSizable;
    itemActions.translatesAutoresizingMaskIntoConstraints = YES;
    root.itemActions = itemActions;
    self.itemActions = itemActions;
    self.pasteButton = paste;
    self.plainPasteButton = plainPaste;
    self.saveButton = save;
    self.secondaryButton = more;
    self.countLabel = MakeLabel(@"0", 12, NSFontWeightMedium);
    self.countLabel.textColor = NSColor.secondaryLabelColor;
    self.countLabel.alignment = NSTextAlignmentCenter;
    NSTextField *shortcut = MakeLabel(@"⌘⇧C", 11, NSFontWeightMedium);
    shortcut.textColor = NSColor.secondaryLabelColor;
    shortcut.alignment = NSTextAlignmentRight;
    self.shortcutLabel = shortcut;

    self.searchField = [FlatSearchField new];
    self.searchField.placeholderString = @"搜索复制内容";
    self.searchField.delegate = self;
    self.searchField.font = [NSFont systemFontOfSize:13];
    self.searchField.bezeled = YES;
    self.searchField.focusRingType = NSFocusRingTypeNone;
    self.searchField.translatesAutoresizingMaskIntoConstraints = YES;

    self.banner = [self makeBanner];

    self.table = [[ClickTableView alloc] initWithFrame:NSZeroRect];
    self.table.owner = self;
    self.table.target = self;
    self.table.doubleAction = @selector(pasteClickedRow:);
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"main"];
    [self.table addTableColumn:column];
    self.table.headerView = nil;
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.backgroundColor = NSColor.clearColor;
    self.table.rowHeight = 48;
    self.table.intercellSpacing = NSMakeSize(0, 5);
    self.table.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
    self.table.allowsMultipleSelection = NO;
    self.table.allowsEmptySelection = NO;
    self.table.focusRingType = NSFocusRingTypeNone;
    self.shelfItems = [NSMutableArray array];
    [self.table setDraggingSourceOperationMask:NSDragOperationCopy forLocal:NO];
    [self.table setDraggingSourceOperationMask:NSDragOperationNone forLocal:YES];
    if (@available(macOS 11.0, *)) {
        self.table.style = NSTableViewStylePlain;
    }

    self.scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.autohidesScrollers = YES;
    self.scrollView.scrollerStyle = NSScrollerStyleOverlay;
    self.scrollView.drawsBackground = NO;
    self.scrollView.borderType = NSNoBorder;
    self.scrollView.documentView = self.table;
    self.scrollView.contentView.wantsLayer = YES;
    self.scrollView.contentView.layer.masksToBounds = YES;
    self.scrollView.translatesAutoresizingMaskIntoConstraints = YES;

    self.emptyLabel = [NSTextField wrappingLabelWithString:@"还没有复制内容"];
    self.emptyLabel.alignment = NSTextAlignmentCenter;
    self.emptyLabel.font = [NSFont systemFontOfSize:13];
    self.emptyLabel.textColor = NSColor.secondaryLabelColor;
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = YES;
    self.emptyLabel.hidden = YES;

    NSTextField *footer = MakeLabel(@"↑↓ 选择    ↩ 粘贴    ⇧↩ 纯文本    ⌘↩ 复制    esc 关闭", 11, NSFontWeightRegular);
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
    self.footer = footer;
    root.table = self.table;
    for (NSView *view in @[brand, title, self.countLabel, self.sections, addPhrase, actions, closeShelf, itemActions, shortcut, self.searchField, self.banner, self.scrollView, self.emptyLabel, footer]) {
        [root addSubview:view];
    }
}

- (NSView *)makeBanner {
    HMSurfaceView *banner = [HMSurfaceView new];
    banner.translatesAutoresizingMaskIntoConstraints = YES;
    banner.fillColor = HMTheme.notice;
    banner.strokeColor = nil;
    banner.radius = 8;
    NSTextField *text = [NSTextField wrappingLabelWithString:@"还不能自动粘贴。在辅助功能里允许 HandyMinis 后，回车会直接贴到刚才的应用。"];
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

- (NSMenuItem *)addAction:(NSString *)title selector:(SEL)action item:(ClipItem *)item menu:(NSMenu *)menu {
    NSMenuItem *entry = [menu addItemWithTitle:title action:action keyEquivalent:@""];
    entry.target = self;
    entry.representedObject = item;
    return entry;
}

- (NSMenu *)actionMenuForItem:(ClipItem *)item {
    NSMenu *menu = [NSMenu new];
    [self addAction:@"粘贴" selector:@selector(contextPaste:) item:item menu:menu];
    [self addAction:@"仅复制" selector:@selector(contextCopy:) item:item menu:menu];
    if (item.kind == ClipKindText && item.text.length) {
        [self addAction:@"粘贴为纯文本" selector:@selector(contextPlainPaste:) item:item menu:menu];
        NSMenuItem *clean = [menu addItemWithTitle:@"清理文本并粘贴" action:nil keyEquivalent:@""];
        clean.submenu = [NSMenu new];
        NSArray *titles = @[@"去掉折行，保留段落", @"清理多余空格", @"合并为一行"];
        for (NSInteger i = 0; i < (NSInteger)titles.count; i++) {
            NSMenuItem *entry = [self addAction:titles[i] selector:@selector(contextClean:) item:item menu:clean.submenu];
            entry.tag = i;
        }
        NSString *title = item.phraseName ? @"编辑常用语…" : @"保存为常用语…";
        [self addAction:title selector:@selector(contextPhrase:) item:item menu:menu];
    } else if (item.kind == ClipKindFiles && ![self showingShelf]) {
        [self addAction:@"加入文件暂存" selector:@selector(contextStageFiles:) item:item menu:menu];
    }
    if (item.kind != ClipKindImage) [self addAction:@"查看全文…" selector:@selector(contextInspect:) item:item menu:menu];
    [menu addItem:NSMenuItem.separatorItem];
    [self addAction:[self showingShelf] ? @"移出暂存" : @"删除" selector:@selector(contextDelete:) item:item menu:menu];
    return menu;
}

- (void)showActions:(id)sender {
    ClipItem *item = [self itemForRow:self.table.selectedRow];
    if (!item) return;
    NSButton *button = self.itemActions.hidden ? self.actionsButton : self.secondaryButton;
    [[self actionMenuForItem:item] popUpMenuPositioningItem:nil atLocation:NSZeroPoint inView:button];
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
    self.banner.hidden = HandyMinisAccessibilityTrusted();
    self.root.needsLayout = YES;
}

- (void)openAccessibility:(id)sender {
    [self.delegate queuePanelDidRequestAccessibility:self];
}

- (void)setShortcutTitle:(NSString *)title {
    if (title.length == 0) title = @"⌘⇧C";
    self.shortcutLabel.stringValue = title;
    self.root.needsLayout = YES;
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

- (BOOL)showingShelf {
    return self.sections.selectedSegment == ClipboardSectionFiles;
}

- (NSArray<ClipItem *> *)sectionItems {
    switch (self.sections.selectedSegment) {
        case ClipboardSectionPhrases: return self.store.phrases;
        case ClipboardSectionFiles: return self.shelfItems;
        default: return self.store.items;
    }
}

- (void)changeSection:(id)sender {
    NSInteger section = self.sections.selectedSegment;
    BOOL phrases = section == ClipboardSectionPhrases;
    self.addPhraseButton.hidden = !phrases;
    BOOL shelf = section == ClipboardSectionFiles;
    self.itemActions.hidden = shelf;
    self.actionsButton.hidden = !shelf;
    self.secondaryButton.title = phrases ? @"仅复制 ⌘↩" : @"更多 ▾";
    self.secondaryButton.action = phrases ? @selector(copySelection:) : @selector(showActions:);
    self.secondaryButton.toolTip = phrases ? @"⌘↩ 仅复制" : @"⌥↩ 打开更多操作";
    self.closeShelfButton.hidden = ![self showingShelf];
    self.searchField.placeholderString = @[@"搜索复制内容", @"搜索常用语", @"搜索暂存文件"][section];
    self.footer.stringValue = shelf
        ? @"←→ 切换    ↑↓ 选择    拖入或拖出文件    Esc 关闭"
        : (phrases ? @"←→ 切换    ↑↓ 选择    Esc 关闭" : @"←→ 切换    ↑↓ 选择    ⌘↩ 仅复制    Esc 关闭");
    self.searchField.stringValue = @"";
    [self reloadKeepingSelection:NO];
    [self.panel makeFirstResponder:self.searchField];
}

- (NSArray<ClipItem *> *)filteredItems {
    NSString *query = [self.searchField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (query.length == 0) return [self sectionItems];
    NSMutableArray<ClipItem *> *matched = [NSMutableArray array];
    for (ClipItem *item in [self sectionItems]) {
        if ([item matchesQuery:query]) [matched addObject:item];
    }
    return matched;
}

- (void)reloadKeepingSelection:(BOOL)keep {
    NSInteger previous = keep ? self.table.selectedRow : 0;
    ClipItem *selectedItem = keep ? [self itemForRow:previous] : nil;
    self.updatingSelection = YES;
    self.root.needsLayout = YES;
    [self.panel.contentView layoutSubtreeIfNeeded];
    [self.rows setArray:[self filteredItems]];
    [self.table reloadData];
    NSInteger previouslyExpandedRow = self.table.selectedRow;
    self.countLabel.stringValue = [NSString stringWithFormat:@"%lu", (unsigned long)[self sectionItems].count];
    BOOL searching = [self.searchField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0;
    if (self.rows.count == 0) {
        self.emptyLabel.hidden = NO;
        NSArray *emptyMessages = @[
            @"还没有复制内容\n复制文本、图片或文件后，会出现在这里。",
            @"还没有常用语\n点「新建常用语」，或在历史里把文本存为常用语。",
            @"还没有暂存文件\n将文件拖到此处，或复制文件后在历史里点「加入暂存」。",
        ];
        self.emptyLabel.stringValue = searching ? @"没有匹配的内容" : emptyMessages[self.sections.selectedSegment];
    } else {
        self.emptyLabel.hidden = YES;
        NSUInteger retainedSelection = selectedItem ? [self.rows indexOfObjectIdenticalTo:selectedItem] : NSNotFound;
        if (retainedSelection != NSNotFound) previous = retainedSelection;
        if (previous < 0) previous = 0;
        if (previous >= (NSInteger)self.rows.count) previous = self.rows.count - 1;
        [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:previous] byExtendingSelection:NO];
    }
    self.lastSelectedRow = previouslyExpandedRow == self.table.selectedRow ? -1 : previouslyExpandedRow;
    self.updatingSelection = NO;
    [self updateSelectedRows];
    self.root.needsLayout = YES;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.rows.count;
}

- (NSString *)expandedTextForItem:(ClipItem *)item {
    if ([self showingShelf] && item.kind == ClipKindFiles) return item.primaryText;
    return item.displayPreview;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    if (row != tableView.selectedRow || row < 0 || row >= (NSInteger)self.rows.count) return 48;
    ClipItem *item = self.rows[row];
    CGFloat width = MAX(80, tableView.bounds.size.width - 68 - 82);
    if (item.kind == ClipKindImage) {
        // Dimensions are captured with the item: row sizing never opens a file.
        CGFloat height = item.pixelWidth > 0 && item.pixelHeight > 0
            ? (CGFloat)item.pixelHeight * width / item.pixelWidth : 120;
        return 36 + MIN(MAX(height, 64), 184);
    }
    NSString *text = [self expandedTextForItem:item];
    NSDictionary *cached = [self.heightCache objectForKey:item];
    if ([cached[@"width"] doubleValue] == width && cached[@"text"] == text) return [cached[@"height"] doubleValue];
    // Only enough layout to determine the capped expanded row height.
    NSRect rect = [text boundingRectWithSize:NSMakeSize(width, 200)
                                   options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:13]}];
    CGFloat height = MIN(MAX(48, ceil(rect.size.height) + 20), 220);
    [self.heightCache setObject:@{@"width": @(width), @"height": @(height), @"text": text} forKey:item];
    return height;
}

- (void)configureCell:(ClipCellView *)cell row:(NSInteger)row {
    ClipItem *item = self.rows[row];
    BOOL selected = row == self.table.selectedRow;
    cell.imagePreview = selected && item.kind == ClipKindImage;
    cell.expanded = selected;
    cell.indexLabel.stringValue = row < 9 ? [NSString stringWithFormat:@"%ld", (long)row + 1] : @"·";
    cell.indexLabel.textColor = selected ? HMTheme.accent : NSColor.secondaryLabelColor;
    cell.primaryLabel.stringValue = item.primaryText;
    cell.toolTip = [self showingShelf] ? item.filePaths.firstObject : nil;
    NSString *secondary = item.secondaryText;
    cell.secondaryLabel.hidden = selected || secondary.length == 0;
    cell.secondaryLabel.stringValue = secondary ?: @"";
    if (selected && item.kind != ClipKindImage) {
        [cell prepareTextPreview];
        cell.textView.textColor = NSColor.labelColor;
        NSString *preview = [self expandedTextForItem:item];
        if (![cell.textView.string isEqualToString:preview]) {
            cell.textView.string = preview;
            cell.laidOutText = nil;
            [cell.textScroll.contentView scrollToPoint:NSZeroPoint];
        }
    }
    cell.textScroll.hidden = !selected || item.kind == ClipKindImage;
    cell.primaryLabel.hidden = selected && item.kind != ClipKindImage;
    cell.timeLabel.stringValue = [self showingShelf] ? @"" : (item.phraseName ?: RelativeTime(item.createdAt));
    NSString *imageName = item.kind == ClipKindImage ? item.imageFile : nil;
    BOOL sameImage = (!cell.representedImage && !imageName) ||
        (imageName && [cell.representedImage isEqualToString:imageName]);
    if (!sameImage) cell.requestedImage = nil;
    cell.representedImage = imageName;
    NSImage *thumbnail = imageName ? [self.store thumbnailForItem:item] : nil;
    if (thumbnail) [cell showThumbnail:thumbnail];
    else {
        static NSArray<NSImage *> *symbols;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            symbols = @[[NSImage imageWithSystemSymbolName:@"text.alignleft" accessibilityDescription:nil],
                        [NSImage imageWithSystemSymbolName:@"photo" accessibilityDescription:nil],
                        [NSImage imageWithSystemSymbolName:@"doc" accessibilityDescription:nil]];
        });
        cell.iconView.image = symbols[item.kind];
        cell.iconView.contentTintColor = NSColor.secondaryLabelColor;
        [cell applyColors];
        if (imageName && ![cell.requestedImage isEqualToString:imageName]) {
            cell.requestedImage = imageName;
            __weak ClipCellView *weakCell = cell;
            [self.store requestThumbnailForItem:item completion:^(NSImage *image) {
                ClipCellView *current = weakCell;
                if (image && [current.representedImage isEqualToString:imageName]) [current showThumbnail:image];
            }];
        }
    }
    [cell setNeedsLayout:YES];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [self updateSelectedRows];
}

- (void)updateSelectedRows {
    if (self.updatingSelection) return;
    NSInteger selected = self.table.selectedRow;
    [self updateActionButtons];
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

- (void)pasteRow:(NSInteger)row {
    [self pasteItem:[self itemForRow:row]];
}

- (void)updateActionButtons {
    ClipItem *item = [self itemForRow:self.table.selectedRow];
    BOOL text = item.kind == ClipKindText && item.text.length > 0;
    BOOL files = item.kind == ClipKindFiles && item.filePaths.count > 0;
    self.pasteButton.enabled = item != nil;
    self.plainPasteButton.enabled = text;
    self.saveButton.title = item.phraseName ? @"编辑常用语 ⌃↩" : (files ? @"加入暂存 ⌃↩" : @"存为常用语 ⌃↩");
    self.saveButton.enabled = text || files;
    self.actionsButton.enabled = item != nil;
    self.secondaryButton.enabled = item != nil;
}

- (void)pasteSelection:(id)sender {
    [self pasteRow:self.table.selectedRow];
}

- (void)copySelection:(id)sender {
    ClipItem *item = [self itemForRow:self.table.selectedRow];
    if (item) [self.delegate queuePanel:self didChooseItem:item paste:NO plainText:NO];
}

- (void)pasteClickedRow:(id)sender {
    [self pasteRow:self.table.clickedRow];
}

- (void)pastePlainSelection:(id)sender {
    ClipItem *item = [self itemForRow:self.table.selectedRow];
    if (item.kind == ClipKindText && item.text.length) {
        [self.delegate queuePanel:self didChooseItem:item paste:YES plainText:YES];
    }
}

- (void)saveSelection:(id)sender {
    ClipItem *item = [self itemForRow:self.table.selectedRow];
    if (item.kind == ClipKindFiles && item.filePaths.count) [self stageItem:item];
    else if (item.kind == ClipKindText && item.text.length) [self editPhrase:item];
}

- (void)closeShelf:(id)sender {
    [self hide];
}

- (void)pasteItem:(ClipItem *)item {
    if (!item) return;
    [self.delegate queuePanel:self didChooseItem:item paste:YES plainText:NO];
}

- (void)contextPaste:(NSMenuItem *)sender {
    [self pasteItem:sender.representedObject];
}

- (void)contextCopy:(NSMenuItem *)sender {
    [self.delegate queuePanel:self didChooseItem:sender.representedObject paste:NO plainText:NO];
}

- (void)contextPlainPaste:(NSMenuItem *)sender {
    [self.delegate queuePanel:self didChooseItem:sender.representedObject paste:YES plainText:YES];
}

- (void)contextClean:(NSMenuItem *)sender {
    ClipItem *original = sender.representedObject;
    ClipItem *item = [ClipItem new];
    item.kind = ClipKindText;
    item.text = HandyMinisTransformText(original.text, sender.tag);
    if (item.text.length) [self.delegate queuePanel:self didChooseItem:item paste:YES plainText:YES];
    else NSBeep();
}

- (void)contextStageFiles:(NSMenuItem *)sender {
    [self stageItem:sender.representedObject];
}

- (void)stageItem:(ClipItem *)item {
    if (![self stagePaths:item.filePaths]) { NSBeep(); return; }
    self.sections.selectedSegment = ClipboardSectionFiles;
    [self changeSection:nil];
}

- (BOOL)stagePaths:(NSArray<NSString *> *)paths {
    BOOL foundFile = NO;
    for (NSString *path in paths) {
        NSString *normalized = path.stringByStandardizingPath;
        if (!normalized.isAbsolutePath || ![NSFileManager.defaultManager fileExistsAtPath:normalized]) continue;
        foundFile = YES;
        if ([self.shelfItems indexOfObjectPassingTest:^BOOL(ClipItem *item, NSUInteger idx, BOOL *stop) {
            return [item.filePaths.firstObject isEqualToString:normalized];
        }] != NSNotFound) continue;
        ClipItem *item = [ClipItem new];
        item.kind = ClipKindFiles;
        item.filePaths = @[normalized];
        item.itemID = NSUUID.UUID.UUIDString;
        item.createdAt = NSDate.date;
        [self.shelfItems addObject:item];
    }
    return foundFile;
}

- (BOOL)acceptFileDrop:(id<NSDraggingInfo>)info {
    NSArray<NSURL *> *urls = [info.draggingPasteboard readObjectsForClasses:@[NSURL.class]
        options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSURL *url in urls) if (url.isFileURL && url.path) [paths addObject:url.path];
    if (![self stagePaths:paths]) return NO;
    self.sections.selectedSegment = ClipboardSectionFiles;
    [self changeSection:nil];
    return YES;
}

- (void)contextInspect:(NSMenuItem *)sender {
    ClipItem *item = sender.representedObject;
    if (!item || item.kind == ClipKindImage) return;
    [self hide];
    if (!self.fullTextWindow) {
        self.fullTextWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 480)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
            backing:NSBackingStoreBuffered defer:NO];
        self.fullTextWindow.releasedWhenClosed = NO;
        self.fullTextWindow.title = @"HandyMinis · 完整内容";
    }
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:self.fullTextWindow.contentView.bounds];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.hasVerticalScroller = YES;
    NSTextView *text = [[NSTextView alloc] initWithFrame:scroll.bounds];
    text.editable = NO;
    text.font = [NSFont systemFontOfSize:14];
    text.textColor = NSColor.labelColor;
    text.backgroundColor = HMTheme.surface;
    text.textContainerInset = NSMakeSize(18, 18);
    text.verticallyResizable = YES;
    text.autoresizingMask = NSViewWidthSizable;
    text.layoutManager.allowsNonContiguousLayout = YES;
    text.string = item.kind == ClipKindText ? (item.text ?: @"") : [item.filePaths componentsJoinedByString:@"\n"];
    scroll.documentView = text;
    self.fullTextWindow.contentView = scroll;
    [self.fullTextWindow center];
    [NSApp activate];
    [self.fullTextWindow makeKeyAndOrderFront:nil];
}

- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row {
    if (![self showingShelf]) return nil;
    NSString *path = [self itemForRow:row].filePaths.firstObject;
    return path && [NSFileManager.defaultManager fileExistsAtPath:path] ? [NSURL fileURLWithPath:path] : nil;
}

- (void)newPhrase:(id)sender {
    [self editPhrase:nil];
}

- (void)contextPhrase:(NSMenuItem *)sender {
    [self editPhrase:sender.representedObject];
}

- (void)editPhrase:(ClipItem *)item {
    if (self.panel.attachedSheet) return;
    NSAlert *alert = [NSAlert new];
    alert.messageText = item.phraseName ? @"编辑常用短语" : @"新建常用短语";
    NSButton *save = [alert addButtonWithTitle:@"保存"];
    [alert addButtonWithTitle:@"取消"];
    NSView *form = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, 144)];
    NSTextField *name = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 118, 360, 24)];
    name.placeholderString = @"短语名称";
    name.stringValue = item.phraseName ?: (item ? [item.primaryText substringWithRange:
        [item.primaryText rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, MIN(item.primaryText.length, 40))]] : @"");
    [name setAccessibilityLabel:@"短语名称"];
    [form addSubview:name];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 360, 108)];
    scroll.borderType = NSBezelBorder;
    scroll.hasVerticalScroller = YES;
    NSTextView *body = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, scroll.contentSize.width, 108)];
    body.richText = NO;
    body.font = [NSFont systemFontOfSize:13];
    body.string = item.text ?: @"";
    body.verticallyResizable = YES;
    body.autoresizingMask = NSViewWidthSizable;
    [body setAccessibilityLabel:@"短语内容"];
    scroll.documentView = body;
    [form addSubview:scroll];
    alert.accessoryView = form;
    alert.window.initialFirstResponder = name;
    // Keep Return available for adding lines in the phrase.
    save.keyEquivalent = @"";
    [alert beginSheetModalForWindow:self.panel completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) return;
        if (![self.store savePhrase:item.phraseName ? item : nil name:name.stringValue text:body.string]) {
            NSAlert *failure = [NSAlert new];
            failure.messageText = @"无法保存短语";
            failure.informativeText = @"请输入名称和内容。内容最多可包含 500,000 个字符。";
            [failure beginSheetModalForWindow:self.panel completionHandler:nil];
            return;
        }
        self.sections.selectedSegment = ClipboardSectionPhrases;
        self.searchField.stringValue = @"";
        [self changeSection:nil];
    }];
}

- (void)contextDelete:(NSMenuItem *)sender {
    [self deleteItem:sender.representedObject];
}

- (void)deleteItem:(ClipItem *)item {
    if (!item) return;
    if ([self.shelfItems containsObject:item]) {
        [self.shelfItems removeObjectIdenticalTo:item];
        [self reloadKeepingSelection:YES];
    } else {
        [self.delegate queuePanel:self didDeleteItem:item];
    }
}

#pragma mark - Keyboard

- (void)installKeyMonitor {
    __weak QueuePanel *weakSelf = self;
    self.keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        QueuePanel *panel = weakSelf;
        if (!panel || !panel.panel.isVisible || !panel.panel.isKeyWindow || panel.panel.attachedSheet) return event;
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
        case 123:
        case 124: {
            if (flags & (NSEventModifierFlagCommand | NSEventModifierFlagOption |
                         NSEventModifierFlagControl | NSEventModifierFlagShift)) return event;
            NSInteger section = self.sections.selectedSegment + (event.keyCode == 123 ? -1 : 1);
            if (section >= 0 && section < ClipboardSectionCount) {
                self.sections.selectedSegment = section;
                [self changeSection:nil];
            }
            return nil;
        }
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
            NSEventModifierFlags modifiers = flags & (NSEventModifierFlagCommand | NSEventModifierFlagOption |
                NSEventModifierFlagControl | NSEventModifierFlagShift);
            if (modifiers == NSEventModifierFlagControl) {
                if (![self showingShelf]) [self saveSelection:nil];
                return nil;
            }
            if (modifiers == NSEventModifierFlagOption) {
                [self showActions:nil];
                return nil;
            }
            if (modifiers & (NSEventModifierFlagOption | NSEventModifierFlagControl)) return event;
            ClipItem *item = [self itemForRow:self.table.selectedRow];
            if (!item) return nil;
            BOOL copyOnly = (flags & NSEventModifierFlagCommand) != 0;
            BOOL plainText = (flags & NSEventModifierFlagShift) != 0;
            if (plainText && item.kind != ClipKindText) { NSBeep(); return nil; }
            [self.delegate queuePanel:self didChooseItem:item paste:!copyOnly plainText:plainText];
            return nil;
        }
        case 51: {
            BOOL searchEmpty = self.searchField.stringValue.length == 0;
            if ((flags & NSEventModifierFlagCommand) || searchEmpty) {
                [self deleteItem:[self itemForRow:self.table.selectedRow]];
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
    if (row == self.table.selectedRow) return;
    [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
}

@end
