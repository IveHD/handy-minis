#import "ClipboardStore.h"
#import <CommonCrypto/CommonDigest.h>
#import <ImageIO/ImageIO.h>

NSNotificationName const CopyQueueItemsDidChangeNotification = @"CopyQueueItemsDidChange";

static const NSUInteger kMaxItems = 40;
static const NSUInteger kMaxHistoryBytes = 64 * 1024 * 1024;

static BOOL IsImageFilename(NSString *name) {
    return name.length > 4 && [name isEqualToString:name.lastPathComponent] &&
        [name.pathExtension isEqualToString:@"png"];
}
static const NSUInteger kMaxTextLength = 500000;
static const NSUInteger kMaxTextFormatBytes = 512 * 1024;

static NSArray<NSPasteboardType> *RichTextTypes(void) {
    return @[NSPasteboardTypeRTF, NSPasteboardTypeHTML];
}

static NSString *HashData(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)MIN(data.length, (NSUInteger)UINT32_MAX), digest);
    static const char digits[] = "0123456789abcdef";
    char hex[CC_SHA256_DIGEST_LENGTH * 2];
    for (size_t i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        hex[i * 2] = digits[digest[i] >> 4];
        hex[i * 2 + 1] = digits[digest[i] & 15];
    }
    return [[NSString alloc] initWithBytes:hex length:sizeof(hex) encoding:NSASCIIStringEncoding];
}

static NSString *HashString(NSString *value) {
    return HashData([value dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data]);
}

static NSString *KindToString(ClipKind kind) {
    switch (kind) {
        case ClipKindImage: return @"image";
        case ClipKindFiles: return @"files";
        case ClipKindText: return @"text";
    }
    return @"text";
}

static ClipKind KindFromString(NSString *value) {
    if ([value isEqualToString:@"image"]) return ClipKindImage;
    if ([value isEqualToString:@"files"]) return ClipKindFiles;
    return ClipKindText;
}

static NSArray<NSString *> *NonEmptyLines(NSString *text) {
    if (text.length == 0) return @[];
    NSString *normalized = [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]
        stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *line in [normalized componentsSeparatedByString:@"\n"]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (trimmed.length > 0) [lines addObject:trimmed];
    }
    return lines;
}

static NSString *Truncate(NSString *text) {
    if (text.length <= kMaxTextLength) return text;
    NSRange range = [text rangeOfComposedCharacterSequenceAtIndex:kMaxTextLength - 1];
    return [text substringToIndex:range.location];
}

@interface ClipItem ()
@property (nonatomic, weak) NSString *previewSourceText;
@property (nonatomic, copy) NSArray<NSString *> *previewLines;
@end

@implementation ClipItem

- (NSArray<NSString *> *)textPreviewLines {
    if (!self.previewLines || self.previewSourceText != self.text) {
        self.previewSourceText = self.text;
        self.previewLines = NonEmptyLines(self.text);
    }
    return self.previewLines;
}

- (NSString *)primaryText {
    switch (self.kind) {
        case ClipKindText: {
            if (self.phraseName.length) return self.phraseName;
            NSString *line = self.textPreviewLines.firstObject;
            return line.length > 0 ? line : @"空白文本";
        }
        case ClipKindImage:
            if (self.pixelWidth > 0 && self.pixelHeight > 0) {
                return [NSString stringWithFormat:@"图片  %ld×%ld", (long)self.pixelWidth, (long)self.pixelHeight];
            }
            return @"图片";
        case ClipKindFiles: {
            NSArray<NSString *> *paths = self.filePaths ?: @[];
            if (paths.count == 1) return paths.firstObject.lastPathComponent;
            return [NSString stringWithFormat:@"%lu 个文件", (unsigned long)paths.count];
        }
    }
    return @"";
}

- (NSString *)secondaryText {
    switch (self.kind) {
        case ClipKindText: {
            NSArray<NSString *> *lines = self.textPreviewLines;
            if (lines.count < 2) return nil;
            return [[lines subarrayWithRange:NSMakeRange(1, lines.count - 1)] componentsJoinedByString:@" "];
        }
        case ClipKindImage:
            return nil;
        case ClipKindFiles: {
            NSArray<NSString *> *paths = self.filePaths ?: @[];
            if (paths.count == 1) return [paths.firstObject stringByDeletingLastPathComponent];
            NSMutableArray<NSString *> *names = [NSMutableArray array];
            for (NSString *path in paths) [names addObject:path.lastPathComponent];
            return [names componentsJoinedByString:@"、"];
        }
    }
    return nil;
}

- (BOOL)matchesQuery:(NSString *)query {
    if (self.text && [self.text rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    NSString *blob = [@[self.primaryText, self.secondaryText ?: @"", self.text ?: @""] componentsJoinedByString:@"\n"];
    return [blob rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound;
}

@end

@interface ClipboardStore ()
@property (nonatomic, strong) NSMutableArray<ClipItem *> *mutableItems;
@property (nonatomic, copy, readwrite) NSArray<ClipItem *> *phrases;
@property (nonatomic, copy) NSString *directory;
@property (nonatomic, copy) NSString *imagesDirectory;
@property (nonatomic, strong) NSISO8601DateFormatter *dateFormatter;
@property (nonatomic, strong) NSCache<NSString *, NSImage *> *thumbnails;
@property (nonatomic, strong) NSMapTable<ClipItem *, NSData *> *encodedItems;
@property (nonatomic, copy) NSSet<NSString *> *referencedImages;
@property (nonatomic, strong) dispatch_queue_t imageQueue;
@property (nonatomic) NSUInteger pendingCaptures;
@property (nonatomic) NSUInteger captureGeneration;
@end

@implementation ClipboardStore

- (instancetype)init {
    self = [super init];
    if (self) {
        NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
        NSString *modern = [support stringByAppendingPathComponent:@"ClipStack"];
        NSString *legacy = [support stringByAppendingPathComponent:@"CopyQueue"];
        NSFileManager *fm = NSFileManager.defaultManager;
        if (![fm fileExistsAtPath:modern] && [fm fileExistsAtPath:legacy]) {
            [fm moveItemAtPath:legacy toPath:modern error:nil];
        }
        _directory = modern;
        _imagesDirectory = [_directory stringByAppendingPathComponent:@"images"];
        _mutableItems = [NSMutableArray array];
        _phrases = @[];
        _dateFormatter = [NSISO8601DateFormatter new];
        _dateFormatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
        _thumbnails = [NSCache new];
        _thumbnails.totalCostLimit = 12 * 1024 * 1024;
        _encodedItems = [NSMapTable weakToStrongObjectsMapTable];
        _referencedImages = [NSSet set];
        _imageQueue = dispatch_queue_create("local.handong.DeskKit.clipboard-images",
            dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0));
        _suppressedChangeCount = NSNotFound;
    }
    return self;
}

- (NSArray<ClipItem *> *)items {
    return self.mutableItems;
}

- (NSString *)supportDirectoryPath {
    return self.directory;
}

- (void)load {
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:self.directory withIntermediateDirectories:YES attributes:nil error:NULL];
    [fm createDirectoryAtPath:self.imagesDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
    NSArray *savedPhrases = [NSArray arrayWithContentsOfFile:[self.directory stringByAppendingPathComponent:@"phrases.plist"]];
    NSMutableArray *phrases = [NSMutableArray array];
    for (id entry in savedPhrases) {
        ClipItem *item = [self itemFromJSON:entry];
        if (item.kind == ClipKindText && item.phraseName.length && item.text.length) [phrases addObject:item];
    }
    self.phrases = phrases;
    NSString *path = [self.directory stringByAppendingPathComponent:@"history.json"];
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&error];
    if (!data) {
        if ([error.domain isEqualToString:NSCocoaErrorDomain] && error.code == NSFileReadNoSuchFileError) {
            [self removeUnreferencedImages:[NSSet set]];
        }
        return;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![json isKindOfClass:[NSArray class]]) return;
    NSMutableArray<ClipItem *> *loaded = [NSMutableArray array];
    for (id entry in (NSArray *)json) {
        ClipItem *item = [self itemFromJSON:entry];
        if (item) [loaded addObject:item];
    }
    self.mutableItems = loaded;
    [self.encodedItems removeAllObjects];
    if ([self persistItems:loaded]) [self removeUnreferencedImages:self.referencedImages];
}

- (void)clear {
    if (![self persistItems:@[]]) return;
    self.captureGeneration++;
    [self.thumbnails removeAllObjects];
    [self notify];
}

- (BOOL)persistPhrases:(NSArray<ClipItem *> *)phrases {
    NSMutableArray *entries = [NSMutableArray array];
    for (ClipItem *item in phrases) [entries addObject:[self jsonFromItem:item]];
    NSString *path = [self.directory stringByAppendingPathComponent:@"phrases.plist"];
    if (![entries writeToFile:path atomically:YES]) return NO;
    self.phrases = phrases;
    [self notify];
    return YES;
}

- (BOOL)savePhrase:(ClipItem *)phrase name:(NSString *)name text:(NSString *)text {
    name = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!name.length || ![text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length ||
        text.length > kMaxTextLength) return NO;
    NSMutableArray *updated = [self.phrases mutableCopy];
    NSUInteger index = phrase ? [updated indexOfObjectIdenticalTo:phrase] : NSNotFound;
    ClipItem *item = [self makeItemOfKind:ClipKindText hash:HashString(text)];
    item.phraseName = name;
    item.text = text;
    if (index == NSNotFound) [updated insertObject:item atIndex:0];
    else updated[index] = item;
    return [self persistPhrases:updated];
}

- (void)deleteItem:(ClipItem *)item {
    if (item.phraseName) {
        NSMutableArray *updated = [self.phrases mutableCopy];
        [updated removeObjectIdenticalTo:item];
        if (![self persistPhrases:updated]) NSBeep();
        return;
    }
    NSMutableArray<ClipItem *> *updated = [self.mutableItems mutableCopy];
    NSIndexSet *indexes = [updated indexesOfObjectsPassingTest:^BOOL(ClipItem *obj, NSUInteger idx, BOOL *stop) {
        return [obj.itemID isEqualToString:item.itemID];
    }];
    [updated removeObjectsAtIndexes:indexes];
    if ([self persistItems:updated]) [self notify];
}

- (void)moveItemToFrontAtIndex:(NSUInteger)index {
    NSMutableArray<ClipItem *> *updated = [self.mutableItems mutableCopy];
    ClipItem *item = updated[index];
    NSDate *previousDate = item.createdAt;
    item.createdAt = [NSDate date];
    [self.encodedItems removeObjectForKey:item];
    [updated removeObjectAtIndex:index];
    [updated insertObject:item atIndex:0];
    if ([self persistItems:updated]) [self notify];
    else {
        item.createdAt = previousDate;
        [self.encodedItems removeObjectForKey:item];
    }
}

- (void)ingestPasteboard:(NSPasteboard *)pasteboard {
    NSInteger change = pasteboard.changeCount;
    NSArray<NSURL *> *fileURLs = [self fileURLsFromPasteboard:pasteboard];
    NSString *text = [pasteboard stringForType:NSPasteboardTypeString];
    BOOL truncated = text.length > kMaxTextLength;
    if (truncated) text = Truncate(text);
    BOOL hasText = text.length > 0 &&
        [text rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet.invertedSet].location != NSNotFound;

    ClipItem *fallback = nil;
    NSData *rawImage = nil;
    BOOL originalPNG = NO;
    if (hasText && ![self text:text isFileList:fileURLs]) {
        NSMutableString *identity = [NSMutableString stringWithFormat:@"text:%@", text];
        NSMutableDictionary *formats = [NSMutableDictionary dictionary];
        if (!truncated) {
            NSArray *available = pasteboard.types;
            for (NSPasteboardType type in RichTextTypes()) {
                if (![available containsObject:type]) continue;
                NSData *data = [pasteboard dataForType:type];
                if (!data.length || data.length > kMaxTextFormatBytes) continue;
                formats[type] = data;
                [identity appendFormat:@":%@:%@", type, HashData(data)];
            }
        }
        fallback = [self makeItemOfKind:ClipKindText hash:HashString(identity)];
        fallback.text = text;
        fallback.textFormats = formats.count ? formats : nil;
    } else {
        if (fileURLs.count <= 1) {
            rawImage = [pasteboard dataForType:NSPasteboardTypePNG];
            originalPNG = rawImage != nil;
            if (!rawImage) rawImage = [pasteboard dataForType:NSPasteboardTypeTIFF];
            if (rawImage.length > 40000000) rawImage = nil;
        }
        if (fileURLs.count > 0) {
            NSMutableArray<NSString *> *paths = [NSMutableArray array];
            for (NSURL *url in fileURLs) [paths addObject:url.path];
            NSString *joined = [[paths sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@"\n"];
            fallback = [self makeItemOfKind:ClipKindFiles hash:HashString([@"files:" stringByAppendingString:joined])];
            fallback.filePaths = paths;
        }
    }
    if (pasteboard.changeCount != change || (!rawImage && !fallback)) return;
    if (!rawImage && self.pendingCaptures == 0) {
        [self storeDraft:fallback png:nil];
        return;
    }

    // Capture pasteboard data on the main thread. Decode snapshots serially so
    // a subsequent text copy cannot overtake an image in the history.
    NSDate *capturedAt = [NSDate date];
    NSUInteger generation = self.captureGeneration;
    self.pendingCaptures++;
    dispatch_async(self.imageQueue, ^{
        ClipItem *draft = fallback;
        NSInteger width = 0, height = 0;
        NSData *png = rawImage ? [self normalizedPNG:rawImage originalPNG:originalPNG width:&width height:&height] : nil;
        if (png) {
            draft = [self makeItemOfKind:ClipKindImage hash:[@"image:" stringByAppendingString:HashData(png)]];
            draft.createdAt = capturedAt;
            draft.pixelWidth = width;
            draft.pixelHeight = height;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.pendingCaptures--;
            if (draft && self.captureGeneration == generation) [self storeDraft:draft png:png];
        });
    });
}

- (void)storeDraft:(ClipItem *)draft png:(NSData *)png {
    NSUInteger existing = [self.mutableItems indexOfObjectPassingTest:^BOOL(ClipItem *obj, NSUInteger idx, BOOL *stop) {
        return [obj.contentHash isEqualToString:draft.contentHash];
    }];
    if (existing != NSNotFound) {
        [self moveItemToFrontAtIndex:existing];
        return;
    }

    NSString *imagePath = nil;
    if (png) {
        if (png.length >= kMaxHistoryBytes) return;
        draft.imageFile = [draft.itemID stringByAppendingPathExtension:@"png"];
        imagePath = [self.imagesDirectory stringByAppendingPathComponent:draft.imageFile];
        if (![png writeToFile:imagePath atomically:YES]) return;
    }
    NSMutableArray<ClipItem *> *updated = [self.mutableItems mutableCopy];
    [updated insertObject:draft atIndex:0];
    BOOL saved = [self persistItems:updated];
    if (imagePath && (!saved || ![self.referencedImages containsObject:draft.imageFile])) {
        [NSFileManager.defaultManager removeItemAtPath:imagePath error:NULL];
    }
    if (saved) [self notify];
}

- (BOOL)copyPlainText:(NSString *)text {
    if (!text.length) return NO;
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    if (![pasteboard setString:text forType:NSPasteboardTypeString]) return NO;
    self.suppressedChangeCount = pasteboard.changeCount;
    return YES;
}

- (BOOL)restoreItem:(ClipItem *)item {
    return [self restoreItem:item plainText:NO];
}

- (BOOL)restoreItem:(ClipItem *)item plainText:(BOOL)plainText {
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    BOOL wrote = NO;
    switch (item.kind) {
        case ClipKindText:
            if (item.text.length == 0) return NO;
            if (plainText || !item.textFormats.count) {
                wrote = [self copyPlainText:item.text];
            } else {
                NSPasteboardItem *entry = [NSPasteboardItem new];
                [entry setString:item.text forType:NSPasteboardTypeString];
                for (NSPasteboardType type in item.textFormats) [entry setData:item.textFormats[type] forType:type];
                [pasteboard clearContents];
                wrote = [pasteboard writeObjects:@[entry]];
            }
            break;
        case ClipKindFiles: {
            NSMutableArray<NSURL *> *urls = [NSMutableArray array];
            for (NSString *path in item.filePaths) {
                [urls addObject:[NSURL fileURLWithPath:path]];
            }
            if (urls.count == 0) return NO;
            [pasteboard clearContents];
            wrote = [pasteboard writeObjects:urls];
            break;
        }
        case ClipKindImage: {
            if (item.imageFile.length == 0) return NO;
            NSString *path = [self.imagesDirectory stringByAppendingPathComponent:item.imageFile];
            NSImage *image = [[NSImage alloc] initWithContentsOfFile:path];
            if (!image) return NO;
            [pasteboard clearContents];
            wrote = [pasteboard writeObjects:@[image]];
            break;
        }
    }
    if (!wrote) return NO;
    self.suppressedChangeCount = pasteboard.changeCount;

    NSUInteger index = [self.mutableItems indexOfObjectPassingTest:^BOOL(ClipItem *obj, NSUInteger idx, BOOL *stop) {
        return [obj.itemID isEqualToString:item.itemID];
    }];
    if (index != NSNotFound) [self moveItemToFrontAtIndex:index];
    return YES;
}

- (NSImage *)thumbnailForItem:(ClipItem *)item {
    if (item.imageFile.length == 0) return nil;
    NSImage *cached = [self.thumbnails objectForKey:item.imageFile];
    if (cached) return cached;
    NSString *path = [self.imagesDirectory stringByAppendingPathComponent:item.imageFile];
    NSURL *url = [NSURL fileURLWithPath:path];
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) return nil;
    NSDictionary *options = @{(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                              (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
                              (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @640};
    CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    if (!thumbnail) return nil;
    NSImage *image = [[NSImage alloc] initWithCGImage:thumbnail size:NSZeroSize];
    NSUInteger bytes = CGImageGetBytesPerRow(thumbnail) * CGImageGetHeight(thumbnail);
    CFRelease(thumbnail);
    [self.thumbnails setObject:image forKey:item.imageFile cost:bytes];
    return image;
}

#pragma mark - Persistence

- (void)removeUnreferencedImages:(NSSet<NSString *> *)referenced {
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![[fm attributesOfItemAtPath:self.imagesDirectory error:NULL].fileType isEqualToString:NSFileTypeDirectory]) return;
    for (NSString *name in [fm contentsOfDirectoryAtPath:self.imagesDirectory error:NULL]) {
        if (![referenced containsObject:name]) [self removeStoredImage:name];
    }
}

- (void)removeStoredImage:(NSString *)name {
    if (!IsImageFilename(name) || ![[NSUUID alloc] initWithUUIDString:name.stringByDeletingPathExtension]) return;
    NSString *path = [self.imagesDirectory stringByAppendingPathComponent:name];
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![[fm attributesOfItemAtPath:path error:NULL].fileType isEqualToString:NSFileTypeRegular]) return;
    if ([fm removeItemAtPath:path error:NULL]) [self.thumbnails removeObjectForKey:name];
}

- (BOOL)persistItems:(NSArray<ClipItem *> *)items {
    NSMutableArray<ClipItem *> *retained = [NSMutableArray array];
    NSMutableSet<NSString *> *referenced = [NSMutableSet set];
    NSMutableData *history = [NSMutableData data];
    [history appendBytes:"[" length:1];
    NSUInteger remaining = kMaxHistoryBytes - 2; // JSON brackets.
    for (ClipItem *item in items) {
        if (retained.count == kMaxItems) break;
        NSData *entry = [self.encodedItems objectForKey:item];
        if (!entry) {
            entry = [NSJSONSerialization dataWithJSONObject:[self jsonFromItem:item] options:0 error:NULL];
            if (!entry) return NO;
            [self.encodedItems setObject:entry forKey:item];
        }
        NSString *image = item.imageFile;
        unsigned long long imageBytes = 0;
        if (IsImageFilename(image) && ![referenced containsObject:image]) {
            NSString *path = [self.imagesDirectory stringByAppendingPathComponent:image];
            imageBytes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL].fileSize;
        }
        // A single oversized copy must not evict the entire history.
        if (entry.length > kMaxHistoryBytes - 2 || imageBytes > kMaxHistoryBytes - 2 - entry.length) continue;
        NSUInteger bytes = entry.length + (NSUInteger)imageBytes + (retained.count != 0);
        if (bytes > remaining) break;
        if (retained.count) [history appendBytes:"," length:1];
        [history appendData:entry];
        remaining -= bytes;
        [retained addObject:item];
        if (IsImageFilename(image)) [referenced addObject:image];
    }
    [history appendBytes:"]" length:1];

    NSString *path = [self.directory stringByAppendingPathComponent:@"history.json"];
    if (![history writeToFile:path atomically:YES]) {
        fprintf(stderr, "DeskKit 无法保存历史\n");
        return NO;
    }
    self.mutableItems = retained;
    for (NSString *name in self.referencedImages) {
        if (![referenced containsObject:name]) [self removeStoredImage:name];
    }
    self.referencedImages = referenced;
    return YES;
}

- (void)notify {
    [NSNotificationCenter.defaultCenter postNotificationName:CopyQueueItemsDidChangeNotification object:self];
}

- (NSDictionary *)jsonFromItem:(ClipItem *)item {
    NSMutableDictionary *json = [@{
        @"id": item.itemID ?: NSUUID.UUID.UUIDString,
        @"createdAt": [self.dateFormatter stringFromDate:item.createdAt ?: [NSDate date]],
        @"kind": KindToString(item.kind),
        @"contentHash": item.contentHash ?: @"",
    } mutableCopy];
    if (item.text) json[@"text"] = item.text;
    if (item.phraseName) json[@"phraseName"] = item.phraseName;
    if (item.textFormats.count) {
        NSMutableDictionary *formats = [NSMutableDictionary dictionary];
        for (NSPasteboardType type in item.textFormats) {
            formats[type] = [item.textFormats[type] base64EncodedStringWithOptions:0];
        }
        json[@"textFormats"] = formats;
    }
    if (item.filePaths) json[@"filePaths"] = item.filePaths;
    if (item.imageFile) json[@"imageFile"] = item.imageFile;
    if (item.pixelWidth > 0) json[@"pixelWidth"] = @(item.pixelWidth);
    if (item.pixelHeight > 0) json[@"pixelHeight"] = @(item.pixelHeight);
    return json;
}

- (ClipItem *)itemFromJSON:(id)entry {
    if (![entry isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *json = entry;
    NSString *itemID = json[@"id"];
    NSString *hash = json[@"contentHash"];
    if (![itemID isKindOfClass:[NSString class]] || ![hash isKindOfClass:[NSString class]]) return nil;
    ClipItem *item = [ClipItem new];
    item.itemID = itemID;
    item.contentHash = hash;
    item.kind = KindFromString([json[@"kind"] isKindOfClass:[NSString class]] ? json[@"kind"] : @"text");
    NSString *date = json[@"createdAt"];
    item.createdAt = [date isKindOfClass:[NSString class]] ? [self.dateFormatter dateFromString:date] : [NSDate date];
    if (!item.createdAt) item.createdAt = [NSDate date];
    if ([json[@"text"] isKindOfClass:[NSString class]]) item.text = json[@"text"];
    if ([json[@"phraseName"] isKindOfClass:[NSString class]]) item.phraseName = json[@"phraseName"];
    if ([json[@"textFormats"] isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *formats = [NSMutableDictionary dictionary];
        for (NSPasteboardType type in RichTextTypes()) {
            id encoded = json[@"textFormats"][type];
            if (![encoded isKindOfClass:[NSString class]] || [encoded length] > 4 * ((kMaxTextFormatBytes + 2) / 3)) continue;
            NSData *data = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
            if (data.length && data.length <= kMaxTextFormatBytes) formats[type] = data;
        }
        if (formats.count) item.textFormats = formats;
    }
    if ([json[@"imageFile"] isKindOfClass:[NSString class]] && IsImageFilename(json[@"imageFile"])) item.imageFile = json[@"imageFile"];
    if ([json[@"filePaths"] isKindOfClass:[NSArray class]]) item.filePaths = json[@"filePaths"];
    if ([json[@"pixelWidth"] isKindOfClass:[NSNumber class]]) item.pixelWidth = [json[@"pixelWidth"] integerValue];
    if ([json[@"pixelHeight"] isKindOfClass:[NSNumber class]]) item.pixelHeight = [json[@"pixelHeight"] integerValue];
    return item;
}

#pragma mark - Pasteboard

- (ClipItem *)makeItemOfKind:(ClipKind)kind hash:(NSString *)hash {
    ClipItem *item = [ClipItem new];
    item.itemID = NSUUID.UUID.UUIDString;
    item.createdAt = [NSDate date];
    item.kind = kind;
    item.contentHash = hash;
    return item;
}

- (NSArray<NSURL *> *)fileURLsFromPasteboard:(NSPasteboard *)pasteboard {
    NSArray *urls = [pasteboard readObjectsForClasses:@[[NSURL class]]
                                              options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    NSMutableArray<NSURL *> *files = [NSMutableArray array];
    for (NSURL *url in urls) {
        if (url.isFileURL) [files addObject:url];
    }
    return files;
}

- (BOOL)text:(NSString *)text isFileList:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) return NO;
    NSMutableSet<NSString *> *names = [NSMutableSet set];
    NSMutableSet<NSString *> *paths = [NSMutableSet set];
    for (NSURL *url in urls) {
        [names addObject:url.lastPathComponent];
        if (url.path) [paths addObject:url.path];
    }
    NSArray<NSString *> *lines = NonEmptyLines(text);
    if (lines.count == 0) return YES;
    for (NSString *line in lines) {
        if (![names containsObject:line] && ![paths containsObject:line]) return NO;
    }
    return YES;
}

- (NSData *)normalizedPNG:(NSData *)raw originalPNG:(BOOL)originalPNG width:(NSInteger *)widthOut height:(NSInteger *)heightOut {
    NSDictionary *disableCache = @{(__bridge NSString *)kCGImageSourceShouldCache: @NO};
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)raw, (__bridge CFDictionaryRef)disableCache);
    if (!source) return nil;
    NSDictionary *metadata = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    NSInteger width = [metadata[(__bridge NSString *)kCGImagePropertyPixelWidth] integerValue];
    NSInteger height = [metadata[(__bridge NSString *)kCGImagePropertyPixelHeight] integerValue];
    const NSInteger maxSide = 2400;
    if (width <= 0 || height <= 0 || CGImageSourceGetStatusAtIndex(source, 0) != kCGImageStatusComplete) {
        CFRelease(source);
        return nil;
    }
    NSData *png = nil;
    if (originalPNG && raw.length < 6000000 && MAX(width, height) <= maxSide) {
        png = raw;
        CFRelease(source);
    } else {
        NSDictionary *options = @{(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                                  (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
                                  (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @(MIN(MAX(width, height), maxSide))};
        CGImageRef image = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
        CFRelease(source);
        if (!image) return nil;
        NSMutableData *encoded = [NSMutableData data];
        CGImageDestinationRef destination = CGImageDestinationCreateWithData(
            (__bridge CFMutableDataRef)encoded, CFSTR("public.png"), 1, NULL);
        if (destination) {
            CGImageDestinationAddImage(destination, image, NULL);
            if (CGImageDestinationFinalize(destination)) png = encoded;
            CFRelease(destination);
        }
        width = CGImageGetWidth(image);
        height = CGImageGetHeight(image);
        CFRelease(image);
    }
    if (!png) return nil;
    if (widthOut) *widthOut = width;
    if (heightOut) *heightOut = height;
    return png;
}

@end
