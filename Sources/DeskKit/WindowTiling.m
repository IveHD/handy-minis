#import "WindowTiling.h"
#import "AccessibilityTrust.h"
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <QuartzCore/QuartzCore.h>

typedef NS_OPTIONS(NSUInteger, TileEdge) {
    TileLeft = 1 << 0,
    TileRight = 1 << 1,
    TileBottom = 1 << 2,
    TileTop = 1 << 3,
};

static NSRect TileFrame(NSPoint mouse, NSRect screen, NSRect usable) {
    const CGFloat edge = 8;
    const CGFloat corner = 36;
    CGFloat left = mouse.x - NSMinX(screen), right = NSMaxX(screen) - mouse.x;
    CGFloat bottom = mouse.y - NSMinY(screen), top = NSMaxY(screen) - mouse.y;
    TileEdge horizontal = left <= right ? TileLeft : TileRight;
    TileEdge vertical = bottom <= top ? TileBottom : TileTop;
    CGFloat dx = MIN(left, right), dy = MIN(bottom, top);
    TileEdge tile = 0;
    if ((dx <= edge && dy <= corner) || (dy <= edge && dx <= corner)) tile = horizontal | vertical;
    else if (dx <= edge) tile = horizontal;
    else if (dy <= edge) tile = vertical;

    if (!tile) return NSZeroRect;
    NSRect slice, remainder;
    if (tile & (TileLeft | TileRight)) {
        NSDivideRect(usable, &slice, &remainder, floor(NSWidth(usable) / 2), NSMinXEdge);
        usable = tile & TileLeft ? slice : remainder;
    }
    if (tile & (TileBottom | TileTop)) {
        NSDivideRect(usable, &slice, &remainder, floor(NSHeight(usable) / 2), NSMinYEdge);
        usable = tile & TileBottom ? slice : remainder;
    }
    return usable;
}

static NSRect TargetAtPoint(NSPoint point) {
    for (NSScreen *screen in NSScreen.screens) {
        if (NSMouseInRect(point, screen.frame, NO)) return TileFrame(point, screen.frame, screen.visibleFrame);
    }
    return NSZeroRect;
}

static id AXAttribute(AXUIElementRef element, CFStringRef attribute) {
    CFTypeRef value = NULL;
    AXUIElementCopyAttributeValue(element, attribute, &value);
    return CFBridgingRelease(value);
}

static BOOL AXRect(AXUIElementRef window, CGRect *rect) {
    id position = AXAttribute(window, kAXPositionAttribute);
    id size = AXAttribute(window, kAXSizeAttribute);
    return position && size &&
        CFGetTypeID((__bridge CFTypeRef)position) == AXValueGetTypeID() &&
        CFGetTypeID((__bridge CFTypeRef)size) == AXValueGetTypeID() &&
        AXValueGetValue((__bridge AXValueRef)position, kAXValueCGPointType, &rect->origin) &&
        AXValueGetValue((__bridge AXValueRef)size, kAXValueCGSizeType, &rect->size);
}

static BOOL AXSettable(AXUIElementRef window, CFStringRef attribute) {
    Boolean settable = false;
    return AXUIElementIsAttributeSettable(window, attribute, &settable) == kAXErrorSuccess && settable;
}

static BOOL ReadWindowFrame(NSDictionary *info, CGRect *frame) {
    NSDictionary *bounds = info[(__bridge NSString *)kCGWindowBounds];
    return bounds && CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)bounds, frame);
}

@class TiledWindow;

@interface TileDrag : NSObject
@property CGWindowID windowID;
@property pid_t ownerPID;
@property CGRect original;
@property NSPoint startPoint;
// Main thread owns the event state and publishes the latest cursor to the AX queue.
@property BOOL restoring;
@property BOOL confirmedMove;
@property BOOL checkedAccessibility;
@property BOOL canUseAccessibility;
@property BOOL restoreUpdatePending;
@property (atomic) BOOL ended;
@property (atomic, strong) NSValue *restoreCursor;
@property (atomic, strong) NSValue *restoreVisibleFrame;
// Used by the AX queue only.
@property (strong) TiledWindow *restoreRecord;
@property BOOL didApplyRestoreSize;
@end

@implementation TileDrag
@end

static TileDrag *BeginDrag(CGPoint point, NSPoint mouse) {
    NSArray<NSDictionary *> *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID));
    for (NSDictionary *info in windows) {
        if ([info[(__bridge NSString *)kCGWindowLayer] integerValue] != 0) continue;
        CGRect frame;
        if (!ReadWindowFrame(info, &frame) || !CGRectContainsPoint(frame, point)) continue;
        pid_t owner = [info[(__bridge NSString *)kCGWindowOwnerPID] intValue];
        CGWindowID windowID = [info[(__bridge NSString *)kCGWindowNumber] unsignedIntValue];
        if (owner <= 0 || owner == getpid() || windowID == kCGNullWindowID) return nil;
        TileDrag *drag = [TileDrag new];
        drag.windowID = windowID;
        drag.ownerPID = owner;
        drag.original = frame;
        drag.startPoint = mouse;
        return drag;
    }
    return nil;
}

static BOOL ReadCurrentFrame(TileDrag *drag, CGRect *frame) {
    NSArray<NSDictionary *> *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(
        kCGWindowListOptionIncludingWindow, drag.windowID));
    NSDictionary *info = windows.firstObject;
    return [info[(__bridge NSString *)kCGWindowOwnerPID] intValue] == drag.ownerPID && ReadWindowFrame(info, frame);
}

static BOOL SameSize(CGSize a, CGSize b) {
    return fabs(a.width - b.width) <= 1 && fabs(a.height - b.height) <= 1;
}

static BOOL ReadMovedFrame(TileDrag *drag, CGRect *frame) {
    if (!drag || !ReadCurrentFrame(drag, frame)) return NO;
    // Resizing and dragging a window's contents must not trigger tiling.
    CGRect original = drag.original;
    return hypot(frame->origin.x - original.origin.x, frame->origin.y - original.origin.y) >= 4 &&
        SameSize(original.size, frame->size);
}

static id FindAXWindow(TileDrag *drag, CGRect expected) {
    AXUIElementRef app = AXUIElementCreateApplication(drag.ownerPID);
    if (!app) return nil;
    AXUIElementSetMessagingTimeout(app, 0.15);
    id focused = AXAttribute(app, kAXFocusedWindowAttribute);
    NSArray *windows = AXAttribute(app, kAXWindowsAttribute);
    // Some apps expose the focused window before publishing it in AXWindows.
    if (focused && ![windows containsObject:focused]) {
        windows = [@[focused] arrayByAddingObjectsFromArray:windows ?: @[]];
    }
    CFRelease(app);

    id best = nil;
    CGFloat bestDistance = 8;
    for (id candidate in windows) {
        AXUIElementRef window = (__bridge AXUIElementRef)candidate;
        CGRect frame;
        if (!AXRect(window, &frame)) continue;
        CGFloat distance = fabs(frame.origin.x - expected.origin.x) + fabs(frame.origin.y - expected.origin.y) +
            fabs(frame.size.width - expected.size.width) + fabs(frame.size.height - expected.size.height);
        if (distance < bestDistance || (distance == bestDistance && best && [candidate isEqual:focused])) {
            best = candidate;
            bestDistance = distance;
        }
    }
    return best;
}

static AXError SetAXValue(AXUIElementRef window, CFStringRef attribute, AXValueType type, const void *data) {
    AXValueRef value = AXValueCreate(type, data);
    if (!value) return kAXErrorFailure;
    AXError error = AXUIElementSetAttributeValue(window, attribute, value);
    CFRelease(value);
    return error;
}

static CGFloat Interpolate(CGFloat start, CGFloat end, CGFloat progress) {
    return start + (end - start) * progress;
}

static CGRect RestoredFrame(TileDrag *drag, CGSize size, CGPoint cursor, CGRect visible, CGFloat desktopTop) {
    CGRect original = drag.original;
    CGFloat fractionX = (drag.startPoint.x - CGRectGetMinX(original)) / CGRectGetWidth(original);
    CGFloat offsetY = desktopTop - drag.startPoint.y - CGRectGetMinY(original);
    CGFloat x = cursor.x - size.width * fractionX;
    CGFloat y = cursor.y - offsetY;
    if (!CGRectIsEmpty(visible)) {
        x = MAX(CGRectGetMinX(visible), MIN(x, CGRectGetMaxX(visible) - size.width));
        y = MAX(CGRectGetMinY(visible), MIN(y, CGRectGetMaxY(visible) - size.height));
    }
    return CGRectMake(x, y, size.width, size.height);
}

@interface TiledWindow : NSObject
@property (strong) id accessibilityWindow;
@property CGSize restoredSize;
@property CGSize tiledSize;
@end

@implementation TiledWindow
@end

@interface TilePreviewView : NSVisualEffectView
@end

@implementation TilePreviewView

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.material = NSVisualEffectMaterialPopover;
        self.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        self.state = NSVisualEffectStateActive;
        const CGFloat radius = 18;
        NSImage *mask = [NSImage imageWithSize:NSMakeSize(2 * radius + 1, 2 * radius + 1)
                                      flipped:NO drawingHandler:^BOOL(NSRect bounds) {
            [NSColor.blackColor setFill];
            [[NSBezierPath bezierPathWithRoundedRect:bounds xRadius:radius yRadius:radius] fill];
            return YES;
        }];
        mask.capInsets = NSEdgeInsetsMake(radius, radius, radius, radius);
        mask.resizingMode = NSImageResizingModeStretch;
        self.maskImage = mask;
        self.wantsLayer = YES;
        self.layer.cornerRadius = radius;
        self.layer.masksToBounds = YES;
    }
    return self;
}

@end

@interface WindowTiling ()
@property (strong) id mouseMonitor;
@property (strong) id localMonitor;
@property (strong) dispatch_queue_t accessibilityQueue;
@property (strong) TileDrag *drag;
@property (strong) NSPanel *preview;
@property (strong) NSTimer *previewTimer;
@property NSRect target;
@property NSRect displayedTarget;
@property NSUInteger previewVersion;
@property (atomic) NSUInteger dragGeneration;
@property (atomic, copy) NSSet<NSNumber *> *tiledWindowIDs;
// Read and written only on accessibilityQueue.
@property (strong) NSMutableDictionary<NSNumber *, TiledWindow *> *tiledWindows;
@end

@implementation WindowTiling

- (instancetype)init {
    if ((self = [super init])) {
        _tiledWindows = [NSMutableDictionary dictionary];
        _accessibilityQueue = dispatch_queue_create("local.handong.ClipStack.window-tiling", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)start {
    if (self.mouseMonitor) return;
    NSEventMask mask = NSEventMaskLeftMouseDown | NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp;
    __weak typeof(self) weakSelf = self;
    self.mouseMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:mask handler:^(NSEvent *event) {
        [weakSelf handleMouseEvent:event];
    }];
    self.localMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:mask handler:^NSEvent *(NSEvent *event) {
        if (event.type == NSEventTypeLeftMouseDown) [weakSelf cancelDrag];
        else if (event.type == NSEventTypeLeftMouseUp) [weakSelf handleMouseEvent:event];
        return event;
    }];
}

- (void)stop {
    if (self.mouseMonitor) [NSEvent removeMonitor:self.mouseMonitor];
    if (self.localMonitor) [NSEvent removeMonitor:self.localMonitor];
    self.mouseMonitor = nil;
    self.localMonitor = nil;
    self.dragGeneration++;
    [self cancelDrag];
}

- (void)clearPreviewTarget {
    self.target = NSZeroRect;
    [self.previewTimer invalidate];
    self.previewTimer = nil;
    [self hidePreview];
}

- (void)cancelDrag {
    self.drag.ended = YES;
    self.drag = nil;
    [self clearPreviewTarget];
}

- (BOOL)updatePreview {
    TileDrag *drag = self.drag;
    CGRect frame;
    if (!drag || NSIsEmptyRect(self.target) ||
        (!drag.restoring && !ReadMovedFrame(drag, &frame))) {
        [self hidePreview];
        return NO;
    }
    drag.confirmedMove = YES;
    [self.previewTimer invalidate];
    self.previewTimer = nil;
    if (!drag.checkedAccessibility) {
        drag.canUseAccessibility = DeskKitAccessibilityTrusted();
        drag.checkedAccessibility = YES;
    }
    if (drag.canUseAccessibility) [self showPreviewForFrame:self.target];
    return YES;
}

- (void)animateWindow:(AXUIElementRef)window from:(CGRect)start to:(CGRect)target
             duration:(NSTimeInterval)duration generation:(NSUInteger)generation {
    NSProcessInfo *clock = NSProcessInfo.processInfo;
    NSTimeInterval began = clock.systemUptime;
    // AX sends synchronous requests to another app. Use elapsed time so a slow
    // responder skips intermediate frames and the animation cannot queue up.
    while (self.dragGeneration == generation && duration > 0) {
        CGFloat linear = (clock.systemUptime - began) / duration;
        if (linear >= 1) break;
        CGFloat eased = linear * linear * (3 - 2 * linear);
        CGSize size = CGSizeMake(Interpolate(start.size.width, target.size.width, eased),
                                 Interpolate(start.size.height, target.size.height, eased));
        CGPoint origin = CGPointMake(Interpolate(start.origin.x, target.origin.x, eased),
                                     Interpolate(start.origin.y, target.origin.y, eased));
        if (SetAXValue(window, kAXSizeAttribute, kAXValueCGSizeType, &size) != kAXErrorSuccess ||
            self.dragGeneration != generation ||
            SetAXValue(window, kAXPositionAttribute, kAXValueCGPointType, &origin) != kAXErrorSuccess) break;
        NSTimeInterval nextFrame = began + (floor(linear * duration * 60) + 1) / 60;
        NSTimeInterval delay = nextFrame - clock.systemUptime;
        if (delay > 0) [NSThread sleepForTimeInterval:delay];
    }

    if (self.dragGeneration != generation) return;
    // Some apps apply size limits for the display that contains the window.
    SetAXValue(window, kAXPositionAttribute, kAXValueCGPointType, &target.origin);
    if (self.dragGeneration != generation) return;
    SetAXValue(window, kAXSizeAttribute, kAXValueCGSizeType, &target.size);
    if (self.dragGeneration == generation) SetAXValue(window, kAXPositionAttribute, kAXValueCGPointType, &target.origin);
}

- (void)pruneTiledWindows {
    NSArray<NSDictionary *> *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID));
    if (!windows) return;
    NSMutableSet<NSNumber *> *liveIDs = [NSMutableSet setWithCapacity:self.tiledWindows.count];
    for (NSDictionary *info in windows) {
        NSNumber *windowID = info[(__bridge NSString *)kCGWindowNumber];
        if (windowID && self.tiledWindows[windowID]) [liveIDs addObject:windowID];
    }
    for (NSNumber *windowID in self.tiledWindows.allKeys) {
        if (![liveIDs containsObject:windowID]) [self.tiledWindows removeObjectForKey:windowID];
    }
}

- (void)updateRestoredWindow:(TileDrag *)drag desktopTop:(CGFloat)desktopTop generation:(NSUInteger)generation {
    if (drag.ended || self.dragGeneration != generation) return;
    if (!drag.restoreRecord) {
        TiledWindow *record = self.tiledWindows[@(drag.windowID)];
        if (!record || !SameSize(drag.original.size, record.tiledSize)) return;
        drag.restoreRecord = record;
    }

    AXUIElementRef window = (__bridge AXUIElementRef)drag.restoreRecord.accessibilityWindow;
    if (!drag.didApplyRestoreSize) {
        CGSize size = drag.restoreRecord.restoredSize;
        if (SetAXValue(window, kAXSizeAttribute, kAXValueCGSizeType, &size) != kAXErrorSuccess) return;
        drag.didApplyRestoreSize = YES;
    }
    if (drag.ended || self.dragGeneration != generation) return;
    CGRect target = RestoredFrame(drag, drag.restoreRecord.restoredSize, drag.restoreCursor.pointValue,
                                  drag.restoreVisibleFrame.rectValue, desktopTop);
    SetAXValue(window, kAXPositionAttribute, kAXValueCGPointType, &target.origin);
}

- (void)queueRestoreUpdate:(TileDrag *)drag desktopTop:(CGFloat)desktopTop {
    if (drag.restoreUpdatePending) return;
    drag.restoreUpdatePending = YES;
    NSUInteger generation = self.dragGeneration;
    NSValue *cursor = drag.restoreCursor;
    dispatch_async(self.accessibilityQueue, ^{
        [self updateRestoredWindow:drag desktopTop:desktopTop generation:generation];
        dispatch_async(dispatch_get_main_queue(), ^{
            drag.restoreUpdatePending = NO;
            if (self.drag == drag && self.dragGeneration == generation && ![cursor isEqual:drag.restoreCursor]) {
                [self queueRestoreUpdate:drag desktopTop:desktopTop];
            }
        });
    });
}

- (void)finishDrag:(TileDrag *)drag target:(CGRect)target cursor:(CGPoint)cursor
       visibleFrame:(CGRect)visible desktopTop:(CGFloat)desktopTop
           duration:(NSTimeInterval)duration generation:(NSUInteger)generation {
    if (self.dragGeneration != generation) return;
    NSNumber *windowID = @(drag.windowID);
    TiledWindow *record = self.tiledWindows[windowID];
    BOOL tiling = !CGRectIsEmpty(target);
    if (!tiling && !drag.didApplyRestoreSize) return;
    CGRect current;
    // Once the preview confirmed a move, don't reject it if macOS or the app
    // changes the window size as part of its own mouse-up handling.
    if (drag.didApplyRestoreSize || drag.confirmedMove) {
        if (!ReadCurrentFrame(drag, &current)) return;
    } else if (!ReadMovedFrame(drag, &current)) {
        return;
    }
    if (tiling && !DeskKitAccessibilityTrusted()) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.dragGeneration == generation) DeskKitPromptAccessibility();
        });
        return;
    }
    id candidate = drag.didApplyRestoreSize ? drag.restoreRecord.accessibilityWindow : FindAXWindow(drag, current);
    AXUIElementRef window = (__bridge AXUIElementRef)candidate;
    if (!window || self.dragGeneration != generation) return;

    CGRect initial;
    if (!AXRect(window, &initial)) return;
    if (record && (![record.accessibilityWindow isEqual:candidate] || (!drag.didApplyRestoreSize && !SameSize(record.tiledSize, initial.size)))) {
        [self.tiledWindows removeObjectForKey:windowID];
        record = nil;
    }
    if ((!tiling && !record) || [AXAttribute(window, CFSTR("AXFullScreen")) isEqual:@YES] ||
        !AXSettable(window, kAXPositionAttribute) || !AXSettable(window, kAXSizeAttribute)) return;

    CGSize originalSize = record ? record.restoredSize : initial.size;
    if (tiling) {
        [self animateWindow:window from:initial to:target duration:duration generation:generation];
    } else {
        if (self.dragGeneration != generation) return;
        // Native drag tracking can deliver one last position update at release.
        CGRect placement = RestoredFrame(drag, initial.size, cursor, visible, desktopTop);
        SetAXValue(window, kAXPositionAttribute, kAXValueCGPointType, &placement.origin);
    }

    CGRect applied;
    if (!AXRect(window, &applied)) return;
    if (SameSize(applied.size, originalSize)) {
        [self.tiledWindows removeObjectForKey:windowID];
    } else if (tiling) {
        [self pruneTiledWindows];
        TiledWindow *updated = [TiledWindow new];
        updated.accessibilityWindow = candidate;
        updated.restoredSize = originalSize;
        updated.tiledSize = applied.size;
        self.tiledWindows[windowID] = updated;
    } else {
        record.tiledSize = applied.size;
    }
    self.tiledWindowIDs = [NSSet setWithArray:self.tiledWindows.allKeys];
}

static CGRect VisibleFrameAtPoint(NSPoint point, CGFloat desktopTop) {
    for (NSScreen *screen in NSScreen.screens) {
        if (!NSMouseInRect(point, screen.frame, NO)) continue;
        NSRect frame = screen.visibleFrame;
        return CGRectMake(NSMinX(frame), desktopTop - NSMaxY(frame), NSWidth(frame), NSHeight(frame));
    }
    return CGRectZero;
}

- (void)handleMouseEvent:(NSEvent *)event {
    NSScreen *primary = NSScreen.screens.firstObject;
    if (!primary) {
        [self cancelDrag];
        return;
    }
    CGFloat desktopTop = NSMaxY(primary.frame);
    CGEventRef cgEvent = event.CGEvent;
    NSPoint mouse = event.locationInWindow;
    if (cgEvent) {
        CGPoint point = CGEventGetLocation(cgEvent);
        mouse = NSMakePoint(point.x, desktopTop - point.y);
    } else if (event.window) {
        mouse = [event.window convertPointToScreen:mouse];
    }

    if (event.type == NSEventTypeLeftMouseDown) {
        [self cancelDrag];
        self.dragGeneration++;
        if (event.clickCount == 1) {
            self.drag = BeginDrag(CGPointMake(mouse.x, desktopTop - mouse.y), mouse);
        }
        return;
    }

    TileDrag *drag = self.drag;
    if (!drag) return;
    NSRect target = hypot(mouse.x - drag.startPoint.x, mouse.y - drag.startPoint.y) >= 6
        ? TargetAtPoint(mouse) : NSZeroRect;
    if (event.type == NSEventTypeLeftMouseUp) {
        [self cancelDrag];
        if (NSIsEmptyRect(target) && !drag.restoring) return;
        CGRect axTarget = NSIsEmptyRect(target) ? CGRectZero :
            CGRectMake(NSMinX(target), desktopTop - NSMaxY(target), NSWidth(target), NSHeight(target));
        CGRect visible = VisibleFrameAtPoint(mouse, desktopTop);
        CGPoint cursor = CGPointMake(mouse.x, desktopTop - mouse.y);
        NSUInteger generation = self.dragGeneration;
        NSTimeInterval duration = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion ? 0 : 0.22;
        // A global mouse-up monitor can fire before the target app finishes
        // native drag tracking. Let that final move settle before reading AX.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 35 * NSEC_PER_MSEC), self.accessibilityQueue, ^{
            [self finishDrag:drag target:axTarget cursor:cursor visibleFrame:visible
                  desktopTop:desktopTop duration:duration generation:generation];
        });
        return;
    }

    if (!drag.restoring && NSIsEmptyRect(target) && [self.tiledWindowIDs containsObject:@(drag.windowID)] &&
        hypot(mouse.x - drag.startPoint.x, mouse.y - drag.startPoint.y) >= 10) {
        CGRect moved;
        drag.restoring = ReadMovedFrame(drag, &moved);
    }
    if (drag.restoring) {
        drag.restoreCursor = [NSValue valueWithPoint:NSMakePoint(mouse.x, desktopTop - mouse.y)];
        drag.restoreVisibleFrame = [NSValue valueWithRect:VisibleFrameAtPoint(mouse, desktopTop)];
        [self queueRestoreUpdate:drag desktopTop:desktopTop];
    }

    if (NSIsEmptyRect(target)) {
        [self clearPreviewTarget];
        return;
    }
    if (NSEqualRects(self.target, target)) return;
    self.target = target;
    if (![self updatePreview] && !self.previewTimer) {
        // WindowServer may publish the new frame after the last drag event.
        __weak typeof(self) weakSelf = self;
        self.previewTimer = [NSTimer timerWithTimeInterval:1.0 / 30.0 repeats:YES block:^(__unused NSTimer *timer) {
            [weakSelf updatePreview];
        }];
        self.previewTimer.tolerance = 0.008;
        [NSRunLoop.mainRunLoop addTimer:self.previewTimer forMode:NSRunLoopCommonModes];
    }
}

- (void)showPreviewForFrame:(NSRect)target {
    NSRect frame = NSInsetRect(target, 6, 6);
    if (!self.preview) {
        NSPanel *panel = [[NSPanel alloc] initWithContentRect:frame
            styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
            backing:NSBackingStoreBuffered defer:NO];
        panel.opaque = NO;
        panel.backgroundColor = NSColor.clearColor;
        panel.hasShadow = NO;
        panel.ignoresMouseEvents = YES;
        panel.hidesOnDeactivate = NO;
        panel.level = NSStatusWindowLevel - 1;
        panel.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace | NSWindowCollectionBehaviorTransient |
            NSWindowCollectionBehaviorIgnoresCycle;
        TilePreviewView *view = [[TilePreviewView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height)];
        panel.contentView = view;
        self.preview = panel;
    }
    if (NSEqualRects(self.displayedTarget, target)) return;
    self.displayedTarget = target;
    ++self.previewVersion;
    BOOL reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    if (!self.preview.isVisible) {
        CGFloat inset = reduceMotion ? 0 : 0.065;
        [self.preview setFrame:NSInsetRect(frame, frame.size.width * inset, frame.size.height * inset) display:YES];
        self.preview.alphaValue = reduceMotion ? 1 : 0;
        [self.preview orderFrontRegardless];
    }
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = reduceMotion ? 0 : 0.17;
        context.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.2 :0.7 :0.3 :1.0];
        [self.preview.animator setFrame:frame display:YES];
        self.preview.animator.alphaValue = 1;
    }];
}

- (void)hidePreview {
    if (NSIsEmptyRect(self.displayedTarget)) return;
    self.displayedTarget = NSZeroRect;
    NSUInteger version = ++self.previewVersion;
    BOOL reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = reduceMotion ? 0 : 0.11;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        if (!reduceMotion) {
            NSRect frame = self.preview.frame;
            [self.preview.animator setFrame:NSInsetRect(frame, frame.size.width * 0.03, frame.size.height * 0.03)
                                   display:YES];
        }
        self.preview.animator.alphaValue = 0;
    } completionHandler:^{
        if (version == self.previewVersion) [self.preview orderOut:nil];
    }];
}

@end
