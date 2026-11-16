#import "Analytics.h"

#ifdef HANDYMINIS_ALIYUN_RUM
#include <alibabacloud_rum.h>
static alibabacloud_rum_options_t *rumOptions;

static void ReportRUMEvent(const char *type, const char *name) {
    if (!rumOptions || [NSUserDefaults.standardUserDefaults boolForKey:@"AnalyticsDisabled"]) return;
    alibabacloud_rum_custom_event_t *event = alibabacloud_rum_custom_event_new(type, name);
    // The SDK takes ownership of a reported event.
    if (event) alibabacloud_rum_custom_event_report(event);
}
#endif

@implementation Analytics
+ (void)startRUM {
#ifdef HANDYMINIS_ALIYUN_RUM
    if (rumOptions || [NSUserDefaults.standardUserDefaults boolForKey:@"AnalyticsDisabled"]) return;
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSString *appID = info[@"AliyunRUMAppID"];
    NSString *configAddress = info[@"AliyunRUMConfigAddress"];
    if (!appID.length || !configAddress.length) return;

    NSFileManager *files = NSFileManager.defaultManager;
    NSURL *cache = [[files URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject
                    URLByAppendingPathComponent:@"HandyMinis/AlibabaCloudRUM" isDirectory:YES];
    if (!cache || ![files createDirectoryAtURL:cache withIntermediateDirectories:YES attributes:nil error:nil]) {
        NSLog(@"HandyMinis could not create the RUM cache directory");
        return;
    }

    alibabacloud_rum_options_t *options = alibabacloud_rum_options_new();
    if (!options) return;
    NSString *version = info[@"CFBundleShortVersionString"];
    alibabacloud_rum_options_set_app_id(options, appID.UTF8String);
    alibabacloud_rum_options_set_config_address(options, configAddress.UTF8String);
    alibabacloud_rum_options_set_app_name(options, "HandyMinis");
    alibabacloud_rum_options_set_app_version(options, version.UTF8String);
    alibabacloud_rum_options_set_cache_path(options, cache.fileSystemRepresentation);
    alibabacloud_rum_options_set_env(options, [info[@"HandyMinisReleaseBuild"] boolValue]
                                    ? ALIBABACLOUD_RUM_ENV_PROD : ALIBABACLOUD_RUM_ENV_LOCAL);
    alibabacloud_rum_options_set_auto_crash_tracking(options, 1);
    alibabacloud_rum_options_set_auto_curl_tracking(options, 0);
    alibabacloud_rum_options_set_auto_cef_tracking(options, 0);
    if (alibabacloud_rum_init(options) == 0) {
        rumOptions = options;
    } else {
        alibabacloud_rum_options_free(options);
        NSLog(@"HandyMinis could not initialize Alibaba Cloud RUM");
    }
#endif
}

+ (void)stopRUM {
#ifdef HANDYMINIS_ALIYUN_RUM
    if (rumOptions && alibabacloud_rum_close() == 0) {
        alibabacloud_rum_options_free(rumOptions);
        rumOptions = NULL;
    }
#endif
}

+ (void)reportLaunchToRUM {
#ifdef HANDYMINIS_ALIYUN_RUM
    ReportRUMEvent("lifecycle", "app_started");
#endif
}

+ (void)reportFeature:(NSString *)event {
#ifdef HANDYMINIS_ALIYUN_RUM
    static NSSet<NSString *> *events;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        events = [NSSet setWithArray:@[
            @"clipboard_panel_opened", @"clipboard_history_viewed", @"clipboard_item_copied",
            @"clipboard_paste_requested", @"clipboard_plain_paste_requested",
            @"clipboard_item_deleted", @"clipboard_history_cleared", @"clipboard_text_cleaned",
            @"phrase_viewed", @"phrase_created", @"phrase_edited", @"phrase_deleted",
            @"phrase_copied", @"phrase_paste_requested",
            @"file_shelf_viewed", @"file_shelf_added", @"file_shelf_removed", @"file_shelf_exported",
            @"screenshot_started", @"screenshot_annotated", @"screenshot_ocr_completed",
            @"screenshot_ocr_text_copied", @"screenshot_image_copied", @"screenshot_saved",
            @"screenshot_exported", @"window_snapped", @"window_layout_saved",
            @"window_layout_restored", @"window_layout_deleted"
        ]];
    });
    if ([events containsObject:event]) ReportRUMEvent("feature_usage", event.UTF8String);
#endif
}

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
            @"isDebug": @(![info[@"HandyMinisReleaseBuild"] boolValue]), @"osName": @"macOS",
            @"osVersion": osVersion, @"deviceModel": @"Mac",
            @"locale": NSLocale.currentLocale.localeIdentifier,
            @"appVersion": info[@"CFBundleShortVersionString"] ?: @"",
            @"appBuildNumber": info[@"CFBundleVersion"] ?: @"",
            @"sdkVersion": @"handyminis-objc@1"}};
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[host stringByAppendingString:@"/api/v0/events"]]];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 15;
    [request setValue:key forHTTPHeaderField:@"App-Key"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:@[payload] options:0 error:nil];
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || [(NSHTTPURLResponse *)response statusCode] >= 300) {
            NSLog(@"HandyMinis analytics delivery failed");
        }
    }] resume];
}
@end

void HandyMinisReportScreenshotUsage(const char *event) {
    [Analytics reportFeature:@(event)];
}
