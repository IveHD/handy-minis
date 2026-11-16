#import <Cocoa/Cocoa.h>

// Semantic colors resolve against each view's current appearance.
@interface HMTheme : NSObject
+ (NSColor *)surface;
+ (NSColor *)canvas;
+ (NSColor *)border;
+ (NSColor *)selection;
+ (NSColor *)selectionBorder;
+ (NSColor *)accent;
+ (NSColor *)iconBackground;
+ (NSColor *)notice;
@end

@interface HMSurfaceView : NSView
@property NSColor *fillColor;
@property NSColor *strokeColor;
@property CGFloat radius;
@end

extern NSNotificationName const HMPanelStyleDidChangeNotification;

@interface HMPanelStyle : NSObject
+ (instancetype)sharedStyle;
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
@property NSInteger palette; // Default, mist, mint, sand, custom.
@property double transparency; // 0–80%, background only.
@property BOOL blur;
- (NSColor *)colorForAppearance:(NSAppearance *)appearance;
- (NSColor *)customColorForAppearance:(NSAppearance *)appearance;
- (void)setCustomColor:(NSColor *)color forAppearance:(NSAppearance *)appearance;
- (void)reset;
@end

/// Background and tint are separate from content so text never fades.
@interface HMPanelSurfaceView : NSView
- (instancetype)initWithStyle:(HMPanelStyle *)style;
@end
