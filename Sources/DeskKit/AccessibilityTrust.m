#import "AccessibilityTrust.h"
#import <ApplicationServices/ApplicationServices.h>

BOOL DeskKitAccessibilityTrusted(void) {
    NSDictionary *silent = @{(__bridge id)kAXTrustedCheckOptionPrompt: @NO};
    if (AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)silent)) return YES;

    // The trust flag is cached against the signed code hash and can stay false
    // after the switch is already on. A real Accessibility call tells them apart:
    // success or "no focused app" means the API is allowed.
    AXUIElementRef system = AXUIElementCreateSystemWide();
    if (!system) return NO;
    CFTypeRef value = NULL;
    AXError error = AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute, &value);
    if (value) CFRelease(value);
    CFRelease(system);
    return error == kAXErrorSuccess || error == kAXErrorNoValue;
}

void DeskKitPromptAccessibility(void) {
    if (DeskKitAccessibilityTrusted()) return;
    NSDictionary *options = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}
