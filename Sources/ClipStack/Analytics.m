#import "Analytics.h"

@implementation Analytics
+ (void)track:(NSString *)event {
    // Called on the main thread. Only fixed event names are accepted.
    if (![@[@"app_started", @"queue_opened", @"paste_requested"] containsObject:event]) return;
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"AnalyticsDisabled"]) return;
    NSString *key = [NSBundle.mainBundle objectForInfoDictionaryKey:@"AptabaseAppKey"];
    NSArray *parts = [key componentsSeparatedByString:@"-"];
    if (parts.count != 3) return;
    NSString *host = @{@"EU": @"https://eu.aptabase.com", @"US": @"https://us.aptabase.com"}[parts[1]];
    if (!host) return;
    static NSMutableDictionary<NSString *, NSDate *> *lastEvents;
    static NSString *sessionID;
    static NSDate *lastActivity;
    if (!lastEvents) lastEvents = [NSMutableDictionary new];
    NSDate *now = NSDate.date;
    // Bound event volume for a frequently used menu-bar utility.
    if (lastEvents[event] && [now timeIntervalSinceDate:lastEvents[event]] < 3600) return;
    lastEvents[event] = now;
    if (!sessionID || [now timeIntervalSinceDate:lastActivity] > 3600) {
        sessionID = [NSString stringWithFormat:@"%llu", (unsigned long long)(now.timeIntervalSince1970 * 100000000) + arc4random_uniform(100000000)];
    }
    lastActivity = now;
    NSISO8601DateFormatter *formatter = [NSISO8601DateFormatter new];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
    NSString *osVersion = [NSString stringWithFormat:@"%ld.%ld.%ld", (long)os.majorVersion, (long)os.minorVersion, (long)os.patchVersion];
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSDictionary *payload = @{@"timestamp": [formatter stringFromDate:now], @"sessionId": sessionID,
        @"eventName": event, @"props": @{}, @"systemProps": @{
            @"isDebug": @(![info[@"ClipStackReleaseBuild"] boolValue]), @"osName": @"macOS",
            @"osVersion": osVersion, @"deviceModel": @"Mac",
            @"locale": NSLocale.currentLocale.localeIdentifier,
            @"appVersion": info[@"CFBundleShortVersionString"] ?: @"",
            @"appBuildNumber": info[@"CFBundleVersion"] ?: @"",
            @"sdkVersion": @"clipstack-objc@1"}};
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[host stringByAppendingString:@"/api/v0/events"]]];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 15;
    [request setValue:key forHTTPHeaderField:@"App-Key"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:@[payload] options:0 error:nil];
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || [(NSHTTPURLResponse *)response statusCode] >= 300) {
            NSLog(@"ClipStack analytics delivery failed");
        }
    }] resume];
}
@end
