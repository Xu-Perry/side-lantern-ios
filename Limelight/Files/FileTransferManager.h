#import "FileTransferProtocol.h"

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSNotificationName const FileTransferManagerDidChange;
typedef NS_ENUM(NSInteger, FileTransferState) {
    FileTransferPreparing, FileTransferQueued, FileTransferRunning, FileTransferPaused,
    FileTransferFailed, FileTransferCompleted, FileTransferCancelled
};

@interface FileTransferTask : NSObject <NSCopying>
@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, readonly) BOOL upload;
@property (nonatomic, readonly) FileTransferState state;
@property (nonatomic, readonly) uint64_t size;
@property (nonatomic, readonly) uint64_t offset;
@property (nonatomic, strong, readonly) NSDate *date;
@property (nonatomic, strong, readonly, nullable) NSError *error;
@property (nonatomic, strong, readonly) NSURL *localURL;
@end

@interface FileTransferManager : NSObject
@property (atomic, copy, readonly) NSArray<FileTransferTask *> *tasks;
@property (atomic, strong, readonly, nullable) FileTransferCapabilities *capabilities;
@property (atomic, strong, readonly, nullable) NSError *capabilityError;
@property (atomic, readonly) BOOL capabilitiesProbed;
- (instancetype)initWithTransport:(id<FileTransferTransport>)transport directory:(NSURL *)directory;
- (void)refreshCapabilities:(nullable void (^)(void))completion;
- (void)listRoot:(NSString *)root path:(NSString *)path offset:(nullable NSNumber *)offset
    completion:(void (^)(FileTransferListing * _Nullable listing, NSError * _Nullable error))completion;
- (void)enqueueUpload:(NSURL *)file name:(nullable NSString *)name;
- (void)enqueueUpload:(NSURL *)file name:(nullable NSString *)name completion:(nullable void (^)(NSError * _Nullable error))completion;
- (void)enqueueDownload:(FileTransferEntry *)entry root:(NSString *)root path:(NSString *)path;
- (void)pauseTask:(NSString *)identifier;
- (void)resumeTask:(NSString *)identifier;
- (void)cancelTask:(NSString *)identifier;
- (void)clearHistory;
@end
NS_ASSUME_NONNULL_END
