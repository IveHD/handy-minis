#import <Foundation/Foundation.h>

/// Fresh Accessibility check. A granted switch can still make the plain
/// trust API return false for an ad-hoc build, so this also tries the API.
BOOL DeskKitAccessibilityTrusted(void);

/// Shows the system prompt only when the check above fails.
void DeskKitPromptAccessibility(void);
