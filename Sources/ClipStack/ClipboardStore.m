#import "ClipboardStore.h"
#import <CommonCrypto/CommonDigest.h>

NSNotificationName const CopyQueueItemsDidChangeNotification = @"CopyQueueItemsDidChange";

static const NSUInteger kMaxItems = 40;
static const NSUInteger kMaxTextLength = 500000;

static NSString *HashData(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)MIN(data.length, (NSUInteger)UINT32_MAX), digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return hex;
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

@implementation ClipItem

- (NSString *)primaryText {
    switch (self.kind) {
        case ClipKindText: {
            NSString *line = NonEmptyLines(self.text).firstObject;
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
            NSArray<NSString *> *lines = NonEmptyLines(self.text);
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
    NSString *blob = [@[self.primaryText, self.secondaryText ?: @"", self.text ?: @""] componentsJoinedByString:@"\n"];
    return [blob rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound;
}

@end

@interface ClipboardStore ()
@property (nonatomic, strong) NSMutableArray<ClipItem *> *mutableItems;
@property (nonatomic, copy) NSString *directory;
@property (nonatomic, copy) NSString *imagesDirectory;
@property (nonatomic, strong) NSISO8601DateFormatter *dateFormatter;
@property (nonatomic, strong) NSCache<NSString *, NSImage *> *thumbnails;
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
        _dateFormatter = [NSISO8601DateFormatter new];
        _dateFormatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
        _thumbnails = [NSCache new];
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
    NSData *data = [NSData dataWithContentsOfFile:[self.directory stringByAppendingPathComponent:@"history.json"]];
    if (!data) return;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![json isKindOfClass:[NSArray class]]) return;
    NSMutableArray<ClipItem *> *loaded = [NSMutableArray array];
    for (id entry in (NSArray *)json) {
        ClipItem *item = [self itemFromJSON:entry];
        if (item) [loaded addObject:item];
    }
    self.mutableItems = loaded;
}

- (void)clear {
    NSArray<NSString *> *images = [self.mutableItems valueForKey:@"imageFile"];
    [self.mutableItems removeAllObjects];
    [self save];
    for (id name in images) {
        if ([name isKindOfClass:[NSString class]]) {
            [NSFileManager.defaultManager removeItemAtPath:[self.imagesDirectory stringByAppendingPathComponent:name] error:NULL];
        }
    }
    [self.thumbnails removeAllObjects];
    [self notify];
}

- (void)deleteItem:(ClipItem *)item {
    NSString *image = item.imageFile;
    NSIndexSet *indexes = [self.mutableItems indexesOfObjectsPassingTest:^BOOL(ClipItem *obj, NSUInteger idx, BOOL *stop) {
        return [obj.itemID isEqualToString:item.itemID];
    }];
    [self.mutableItems removeObjectsAtIndexes:indexes];
    [self save];
    [self removeImageIfUnused:image];
    [self notify];
}

- (void)ingestPasteboard:(NSPasteboard *)pasteboard {
    NSString *hash = nil;
    NSData *png = nil;
    ClipItem *draft = [self readPasteboard:pasteboard hash:&hash png:&png];
    if (!draft) return;

    NSUInteger existing = [self.mutableItems indexOfObjectPassingTest:^BOOL(ClipItem *obj, NSUInteger idx, BOOL *stop) {
        return [obj.contentHash isEqualToString:draft.contentHash];
    }];
    if (existing != NSNotFound) {
        ClipItem *item = self.mutableItems[existing];
        [self.mutableItems removeObjectAtIndex:existing];
        item.createdAt = [NSDate date];
        [self.mutableItems insertObject:item atIndex:0];
        [self save];
        [self notify];
        return;
    }

    if (png) {
        NSString *filename = [draft.itemID stringByAppendingPathExtension:@"png"];
        NSString *path = [self.imagesDirectory stringByAppendingPathComponent:filename];
        if (![png writeToFile:path atomically:YES]) return;
        draft.imageFile = filename;
    }
    [self.mutableItems insertObject:draft atIndex:0];
    [self trimIfNeeded];
    [self save];
    [self notify];
}

- (BOOL)restoreItem:(ClipItem *)item {
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    BOOL wrote = NO;
    switch (item.kind) {
        case ClipKindText:
            if (item.text.length == 0) return NO;
            wrote = [pasteboard setString:item.text forType:NSPasteboardTypeString];
            break;
        case ClipKindFiles: {
            NSMutableArray<NSURL *> *urls = [NSMutableArray array];
            for (NSString *path in item.filePaths) {
                [urls addObject:[NSURL fileURLWithPath:path]];
            }
            if (urls.count == 0) return NO;
            wrote = [pasteboard writeObjects:urls];
            break;
        }
        case ClipKindImage: {
            if (item.imageFile.length == 0) return NO;
            NSString *path = [self.imagesDirectory stringByAppendingPathComponent:item.imageFile];
            NSImage *image = [[NSImage alloc] initWithContentsOfFile:path];
            if (!image) return NO;
            wrote = [pasteboard writeObjects:@[image]];
            break;
        }
    }
    if (!wrote) return NO;
    self.suppressedChangeCount = pasteboard.changeCount;

    NSUInteger index = [self.mutableItems indexOfObjectPassingTest:^BOOL(ClipItem *obj, NSUInteger idx, BOOL *stop) {
        return [obj.itemID isEqualToString:item.itemID];
    }];
    if (index != NSNotFound) {
        ClipItem *existing = self.mutableItems[index];
        [self.mutableItems removeObjectAtIndex:index];
        existing.createdAt = [NSDate date];
        [self.mutableItems insertObject:existing atIndex:0];
        [self save];
        [self notify];
    }
    return YES;
}

- (NSImage *)thumbnailForItem:(ClipItem *)item {
    if (item.imageFile.length == 0) return nil;
    NSImage *cached = [self.thumbnails objectForKey:item.imageFile];
    if (cached) return cached;
    NSString *path = [self.imagesDirectory stringByAppendingPathComponent:item.imageFile];
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:path];
    if (image) [self.thumbnails setObject:image forKey:item.imageFile];
    return image;
}

#pragma mark - Persistence

- (void)trimIfNeeded {
    if (self.mutableItems.count <= kMaxItems) return;
    NSArray<ClipItem *> *removed = [self.mutableItems subarrayWithRange:NSMakeRange(kMaxItems, self.mutableItems.count - kMaxItems)];
    [self.mutableItems removeObjectsInRange:NSMakeRange(kMaxItems, self.mutableItems.count - kMaxItems)];
    for (ClipItem *item in removed) [self removeImageIfUnused:item.imageFile];
}

- (void)removeImageIfUnused:(NSString *)filename {
    if (filename.length == 0) return;
    for (ClipItem *item in self.mutableItems) {
        if ([item.imageFile isEqualToString:filename]) return;
    }
    [NSFileManager.defaultManager removeItemAtPath:[self.imagesDirectory stringByAppendingPathComponent:filename] error:NULL];
    [self.thumbnails removeObjectForKey:filename];
}

- (void)save {
    NSMutableArray *json = [NSMutableArray arrayWithCapacity:self.mutableItems.count];
    for (ClipItem *item in self.mutableItems) {
        [json addObject:[self jsonFromItem:item]];
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted error:NULL];
    if (!data) return;
    NSString *path = [self.directory stringByAppendingPathComponent:@"history.json"];
    if (![data writeToFile:path atomically:YES]) {
        fprintf(stderr, "ClipStack 无法保存历史\n");
    }
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
    if ([json[@"imageFile"] isKindOfClass:[NSString class]]) item.imageFile = json[@"imageFile"];
    if ([json[@"filePaths"] isKindOfClass:[NSArray class]]) item.filePaths = json[@"filePaths"];
    if ([json[@"pixelWidth"] isKindOfClass:[NSNumber class]]) item.pixelWidth = [json[@"pixelWidth"] integerValue];
    if ([json[@"pixelHeight"] isKindOfClass:[NSNumber class]]) item.pixelHeight = [json[@"pixelHeight"] integerValue];
    return item;
}

#pragma mark - Pasteboard

- (ClipItem *)readPasteboard:(NSPasteboard *)pasteboard hash:(NSString **)hashOut png:(NSData **)pngOut {
    NSArray<NSURL *> *fileURLs = [self fileURLsFromPasteboard:pasteboard];
    NSString *text = [pasteboard stringForType:NSPasteboardTypeString];
    if (text.length > kMaxTextLength) text = Truncate(text);
    BOOL hasText = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0;
    NSData *png = nil;
    NSInteger width = 0;
    NSInteger height = 0;
    BOOL hasImage = [self readImageFromPasteboard:pasteboard png:&png width:&width height:&height];

    // Text wins unless it is just the file list Finder puts on the pasteboard.
    // A lone image (screenshots) is kept as an image even if a single file URL is also present.
    if (hasText && ![self text:text isFileList:fileURLs]) {
        ClipItem *item = [self makeItemOfKind:ClipKindText hash:HashString([@"text:" stringByAppendingString:text])];
        item.text = text;
        return item;
    }
    if (hasImage && fileURLs.count <= 1) {
        ClipItem *item = [self makeItemOfKind:ClipKindImage hash:[@"image:" stringByAppendingString:HashData(png)]];
        item.pixelWidth = width;
        item.pixelHeight = height;
        if (pngOut) *pngOut = png;
        return item;
    }
    if (fileURLs.count > 0) {
        NSMutableArray<NSString *> *paths = [NSMutableArray array];
        for (NSURL *url in fileURLs) [paths addObject:url.path];
        NSString *joined = [[paths sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@"\n"];
        ClipItem *item = [self makeItemOfKind:ClipKindFiles hash:HashString([@"files:" stringByAppendingString:joined])];
        item.filePaths = paths;
        return item;
    }
    if (hasImage) {
        ClipItem *item = [self makeItemOfKind:ClipKindImage hash:[@"image:" stringByAppendingString:HashData(png)]];
        item.pixelWidth = width;
        item.pixelHeight = height;
        if (pngOut) *pngOut = png;
        return item;
    }
    return nil;
}

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

- (BOOL)readImageFromPasteboard:(NSPasteboard *)pasteboard png:(NSData **)pngOut width:(NSInteger *)widthOut height:(NSInteger *)heightOut {
    NSData *raw = [pasteboard dataForType:NSPasteboardTypePNG] ?: [pasteboard dataForType:NSPasteboardTypeTIFF];
    if (!raw || raw.length > 40000000) return NO;
    NSImage *image = [[NSImage alloc] initWithData:raw];
    if (!image) return NO;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithData:image.TIFFRepresentation];
    if (!rep || rep.pixelsWide <= 0 || rep.pixelsHigh <= 0) return NO;

    const NSInteger maxSide = 2400;
    if (raw.length < 6000000 && rep.pixelsWide <= maxSide && rep.pixelsHigh <= maxSide) {
        NSData *png = [pasteboard dataForType:NSPasteboardTypePNG] ?: [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        if (!png) return NO;
        if (pngOut) *pngOut = png;
        if (widthOut) *widthOut = rep.pixelsWide;
        if (heightOut) *heightOut = rep.pixelsHigh;
        return YES;
    }

    double scale = MIN(1.0, (double)maxSide / (double)MAX(rep.pixelsWide, rep.pixelsHigh));
    NSInteger width = MAX(1, (NSInteger)floor(rep.pixelsWide * scale));
    NSInteger height = MAX(1, (NSInteger)floor(rep.pixelsHigh * scale));
    NSBitmapImageRep *output = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                        pixelsWide:width
                                                                        pixelsHigh:height
                                                                     bitsPerSample:8
                                                                   samplesPerPixel:4
                                                                          hasAlpha:YES
                                                                          isPlanar:NO
                                                                    colorSpaceName:NSDeviceRGBColorSpace
                                                                       bytesPerRow:0
                                                                      bitsPerPixel:0];
    if (!output) return NO;
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:output]];
    [[NSColor clearColor] setFill];
    NSRectFill(NSMakeRect(0, 0, width, height));
    [image drawInRect:NSMakeRect(0, 0, width, height)];
    [NSGraphicsContext restoreGraphicsState];
    NSData *png = [output representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (!png) return NO;
    if (pngOut) *pngOut = png;
    if (widthOut) *widthOut = width;
    if (heightOut) *heightOut = height;
    return YES;
}

@end
