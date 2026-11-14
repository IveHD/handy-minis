#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ClipKind) {
    ClipKindText = 0,
    ClipKindImage,
    ClipKindFiles,
};

@interface ClipItem : NSObject
@property (nonatomic, copy) NSString *itemID;
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic) ClipKind kind;
@property (nonatomic, copy, nullable) NSString *text;
@property (nonatomic, copy, nullable) NSArray<NSString *> *filePaths;
@property (nonatomic, copy, nullable) NSString *imageFile;
@property (nonatomic) NSInteger pixelWidth;
@property (nonatomic) NSInteger pixelHeight;
@property (nonatomic, copy) NSString *contentHash;

- (NSString *)primaryText;
- (nullable NSString *)secondaryText;
- (BOOL)matchesQuery:(NSString *)query;
@end

extern NSNotificationName const CopyQueueItemsDidChangeNotification;

@interface ClipboardStore : NSObject
@property (nonatomic, readonly) NSArray<ClipItem *> *items;
@property (nonatomic, readonly) NSString *supportDirectoryPath;
/// changeCount produced by our own pasteboard write. The monitor skips it.
@property (nonatomic) NSInteger suppressedChangeCount;

- (void)load;
- (void)ingestPasteboard:(NSPasteboard *)pasteboard;
- (BOOL)restoreItem:(ClipItem *)item;
- (void)deleteItem:(ClipItem *)item;
- (void)clear;
- (nullable NSImage *)thumbnailForItem:(ClipItem *)item;
@end

NS_ASSUME_NONNULL_END
