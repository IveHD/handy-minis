#import "Theme.h"
#import <QuartzCore/QuartzCore.h>

static NSColor *Pair(NSString *name, unsigned light, unsigned dark) {
    return [NSColor colorWithName:name dynamicProvider:^NSColor *(NSAppearance *appearance) {
        BOOL isDark = [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];
        unsigned rgb = isDark ? dark : light;
        return [NSColor colorWithSRGBRed:((rgb >> 16) & 255) / 255.0
                                  green:((rgb >> 8) & 255) / 255.0
                                   blue:(rgb & 255) / 255.0 alpha:1];
    }];
}

@implementation HMTheme
+ (NSColor *)surface { return Pair(@"HM.surface", 0xFFFFFF, 0x20242B); }
+ (NSColor *)canvas { return Pair(@"HM.canvas", 0xF5F7FA, 0x181C22); }
+ (NSColor *)border { return Pair(@"HM.border", 0xE3E8EF, 0x353C47); }
+ (NSColor *)selection { return Pair(@"HM.selection", 0xEDF5FF, 0x263B52); }
+ (NSColor *)selectionBorder { return Pair(@"HM.selectionBorder", 0xB9D7FA, 0x527AA5); }
+ (NSColor *)accent { return Pair(@"HM.accent", 0x1769C2, 0x8FC4FF); }
+ (NSColor *)iconBackground { return Pair(@"HM.icon", 0xF1F4F8, 0x2C323C); }
+ (NSColor *)notice { return Pair(@"HM.notice", 0xFFF8EB, 0x3B3326); }
@end

@implementation HMSurfaceView
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _fillColor = HMTheme.surface;
        // Surfaces are separated by spacing and fill, without a surrounding rule.
        _strokeColor = nil;
        _radius = 12;
        self.wantsLayer = YES;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.masksToBounds = YES;
    }
    return self;
}
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer {
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        self.layer.backgroundColor = self.fillColor.CGColor;
        self.layer.borderColor = self.strokeColor.CGColor;
        self.layer.borderWidth = self.strokeColor ? 1 : 0;
        self.layer.cornerRadius = self.radius;
    }];
}
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
}
@end

NSNotificationName const HMPanelStyleDidChangeNotification = @"HMPanelStyleDidChange";
static NSString *const PaletteKey = @"PanelPalette";
static NSString *const TransparencyKey = @"PanelTransparency";
static NSString *const BlurKey = @"PanelBackgroundBlur";
static NSString *const LightColorKey = @"PanelCustomColorLight";
static NSString *const DarkColorKey = @"PanelCustomColorDark";

static BOOL DarkAppearance(NSAppearance *appearance) {
    return [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];
}

static NSColor *RGB(unsigned rgb) {
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 255) / 255.0 green:((rgb >> 8) & 255) / 255.0 blue:(rgb & 255) / 255.0 alpha:1];
}

static double LinearComponent(double component) {
    return component <= .04045 ? component / 12.92 : pow((component + .055) / 1.055, 2.4);
}

@interface HMPanelStyle ()
@property NSUserDefaults *defaults;
@end

@implementation HMPanelStyle
+ (instancetype)sharedStyle {
    static HMPanelStyle *style;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ style = [[self alloc] initWithDefaults:NSUserDefaults.standardUserDefaults]; });
    return style;
}
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    if ((self = [super init])) _defaults = defaults;
    return self;
}
- (void)notify {
    [NSNotificationCenter.defaultCenter postNotificationName:HMPanelStyleDidChangeNotification object:self];
}
- (NSInteger)palette {
    NSInteger value = [self.defaults integerForKey:PaletteKey];
    return value >= 0 && value <= 4 ? value : 0;
}
- (void)setPalette:(NSInteger)value {
    [self.defaults setInteger:MIN(MAX(value, 0), 4) forKey:PaletteKey];
    [self notify];
}
- (double)transparency {
    double value = [self.defaults doubleForKey:TransparencyKey];
    return isfinite(value) ? MIN(MAX(value, 0), 80) : 0;
}
- (void)setTransparency:(double)value {
    [self.defaults setDouble:isfinite(value) ? MIN(MAX(value, 0), 80) : 0 forKey:TransparencyKey];
    [self notify];
}
- (BOOL)blur {
    return [self.defaults objectForKey:BlurKey] ? [self.defaults boolForKey:BlurKey] : YES;
}
- (void)setBlur:(BOOL)value {
    [self.defaults setBool:value forKey:BlurKey];
    [self notify];
}
- (NSColor *)customColorForAppearance:(NSAppearance *)appearance {
    BOOL dark = DarkAppearance(appearance);
    NSArray *values = [self.defaults arrayForKey:dark ? DarkColorKey : LightColorKey];
    BOOL valid = values.count == 3;
    for (id value in values) {
        if (![value isKindOfClass:NSNumber.class] || !isfinite([value doubleValue]) || [value doubleValue] < 0 || [value doubleValue] > 1) valid = NO;
    }
    return valid ? [NSColor colorWithSRGBRed:[values[0] doubleValue] green:[values[1] doubleValue] blue:[values[2] doubleValue] alpha:1]
        : RGB(dark ? 0x20242B : 0xFFFFFF);
}
- (void)setCustomColor:(NSColor *)color forAppearance:(NSAppearance *)appearance {
    NSColor *rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!rgb) return;
    [self.defaults setObject:@[@(rgb.redComponent), @(rgb.greenComponent), @(rgb.blueComponent)]
                     forKey:DarkAppearance(appearance) ? DarkColorKey : LightColorKey];
    [self.defaults setInteger:4 forKey:PaletteKey];
    [self notify];
}
- (NSColor *)colorForAppearance:(NSAppearance *)appearance {
    if (self.palette == 4) return [self customColorForAppearance:appearance];
    static const unsigned light[] = {0xFFFFFF, 0xEEF5FC, 0xEDF7F2, 0xFAF5EC};
    static const unsigned dark[] = {0x20242B, 0x202D3B, 0x21332E, 0x332E25};
    return RGB(DarkAppearance(appearance) ? dark[self.palette] : light[self.palette]);
}
- (void)reset {
    for (NSString *key in @[PaletteKey, TransparencyKey, BlurKey, LightColorKey, DarkColorKey]) [self.defaults removeObjectForKey:key];
    [self notify];
}
@end

@interface HMPanelSurfaceView ()
@property HMPanelStyle *style;
@property NSVisualEffectView *blurView;
@property HMSurfaceView *tintView;
@property NSSize maskSize;
@end

@implementation HMPanelSurfaceView
- (instancetype)initWithFrame:(NSRect)frame {
    self = [self initWithStyle:HMPanelStyle.sharedStyle];
    if (self) self.frame = frame;
    return self;
}
- (instancetype)initWithStyle:(HMPanelStyle *)style {
    if ((self = [super initWithFrame:NSZeroRect])) {
        _style = style;
        self.wantsLayer = YES;
        self.layer.cornerRadius = 18;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.masksToBounds = YES;
        _blurView = [NSVisualEffectView new];
        _blurView.material = NSVisualEffectMaterialPopover;
        _blurView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        _blurView.state = NSVisualEffectStateActive;
        _tintView = [HMSurfaceView new];
        _tintView.radius = 18;
        [self addSubview:_blurView];
        [self addSubview:_tintView];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(styleChanged:)
            name:HMPanelStyleDidChangeNotification object:style];
        [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(styleChanged:)
            name:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification object:nil];
        [self refreshStyle];
    }
    return self;
}
- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
}
- (void)didAddSubview:(NSView *)subview {
    [super didAddSubview:subview];
    if (self.tintView && self.style) [self refreshStyle];
}
- (void)styleChanged:(NSNotification *)note { [self refreshStyle]; }
- (void)refreshStyle {
    NSColor *color = [self.style colorForAppearance:self.effectiveAppearance];
    double alpha = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceTransparency ? 1 : 1 - self.style.transparency / 100;
    // A custom dark background needs light controls even in a light system theme.
    NSAppearance *contentAppearance = nil;
    if (self.style.palette == 4) {
        double luminance = .2126 * LinearComponent(color.redComponent) +
            .7152 * LinearComponent(color.greenComponent) + .0722 * LinearComponent(color.blueComponent);
        contentAppearance = [NSAppearance appearanceNamed:luminance < .179 ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    }
    for (NSView *view in self.subviews) view.appearance = contentAppearance;
    self.tintView.fillColor = [color colorWithAlphaComponent:alpha];
    self.tintView.needsDisplay = YES;
    self.blurView.hidden = !self.style.blur || alpha >= 1;
}
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    if (self.style) [self refreshStyle];
}
- (void)layout {
    [super layout];
    self.blurView.frame = self.bounds;
    self.tintView.frame = self.bounds;
    NSSize size = self.bounds.size;
    if (size.width <= 0 || size.height <= 0 || NSEqualSizes(size, self.maskSize)) return;
    self.maskSize = size;
    self.blurView.maskImage = [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect bounds) {
        [NSColor.blackColor setFill];
        [[NSBezierPath bezierPathWithRoundedRect:bounds xRadius:18 yRadius:18] fill];
        return YES;
    }];
    [self.window invalidateShadow];
}
@end
