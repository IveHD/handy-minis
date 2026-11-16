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
@property (nonatomic, copy, nullable) NSString *phraseName;
@property (nonatomic, copy, nullable) NSDictionary<NSPasteboardType, NSData *> *textFormats;
@property (nonatomic, copy, nullable) NSArray<NSString *> *filePaths;
@property (nonatomic, copy, nullable) NSString *imageFile;
@property (nonatomic) NSInteger pixelWidth;
@property (nonatomic) NSInteger pixelHeight;
@property (nonatomic, copy) NSString *contentHash;

- (NSString *)primaryText;
/// Bounded, cached presentation text. The original payload remains intact.
- (NSString *)displayPreview;
- (nullable NSString *)secondaryText;
- (BOOL)matchesQuery:(NSString *)query;
@end

extern NSNotificationName const CopyQueueItemsDidChangeNotification;

@interface ClipboardStore : NSObject
/// Explicit storage location for isolated stores; does not migrate user data.
- (instancetype)initWithSupportDirectory:(NSString *)directory;
@property (nonatomic, readonly) NSArray<ClipItem *> *items;
@property (nonatomic, readonly) NSString *supportDirectoryPath;
/// changeCount produced by our own pasteboard write. The monitor skips it.
@property (nonatomic) NSInteger suppressedChangeCount;

@property (nonatomic, readonly) NSArray<ClipItem *> *phrases;
- (void)load;
- (BOOL)savePhrase:(nullable ClipItem *)phrase name:(NSString *)name text:(NSString *)text;
- (void)ingestPasteboard:(NSPasteboard *)pasteboard;
- (BOOL)restoreItem:(ClipItem *)item;
- (BOOL)restoreItem:(ClipItem *)item plainText:(BOOL)plainText;
- (BOOL)copyPlainText:(NSString *)text;
- (void)deleteItem:(ClipItem *)item;
- (void)clear;
/// Cache-only lookup. Never performs file IO or decoding.
- (nullable NSImage *)thumbnailForItem:(ClipItem *)item;
/// Coalesced background decode, completion on main. Missing/corrupt files are cached.
- (void)requestThumbnailForItem:(ClipItem *)item completion:(void (^)(NSImage * _Nullable image))completion;
@end

NS_ASSUME_NONNULL_END
