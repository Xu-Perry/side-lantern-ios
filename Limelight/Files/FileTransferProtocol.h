#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString *const FileTransferErrorDomain;
FOUNDATION_EXPORT NSNumber * _Nullable FileTransferUnsigned(id _Nullable value, uint64_t maximum);
FOUNDATION_EXPORT BOOL FileTransferValidName(NSString * _Nullable name);
FOUNDATION_EXPORT NSError *FileTransferError(NSString *code, NSInteger status);
FOUNDATION_EXPORT NSError * _Nullable FileTransferResponseError(NSData * _Nullable data, NSHTTPURLResponse * _Nullable response, NSError * _Nullable error);
FOUNDATION_EXPORT NSURLRequest * _Nullable FileTransferRequest(NSURL *baseURL, NSString *method, NSString *route,
    NSDictionary<NSString *, NSString *> *query, NSData * _Nullable body, NSString * _Nullable contentType);

@interface FileTransferRoot : NSObject
@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSString *label;
@end

@interface FileTransferCapabilities : NSObject
@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) BOOL upload;
@property (nonatomic, copy, readonly) NSArray<FileTransferRoot *> *roots;
@property (nonatomic, readonly) NSUInteger uploadChunkBytes;
@property (nonatomic, readonly) NSUInteger downloadChunkBytes;
@property (nonatomic, readonly) uint64_t maxUploadBytes;
+ (nullable instancetype)parse:(NSData *)data;
@end

@interface FileTransferEntry : NSObject
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, readonly) BOOL directory;
@property (nonatomic, readonly) uint64_t size;
@property (nonatomic, strong, readonly) NSDate *modified;
@property (nonatomic, copy, readonly) NSString *version;
@end

@interface FileTransferListing : NSObject
@property (nonatomic, copy, readonly) NSArray<FileTransferEntry *> *entries;
@property (nonatomic, strong, readonly, nullable) NSNumber *nextOffset;
@property (nonatomic, readonly) BOOL truncated;
+ (nullable instancetype)parse:(NSData *)data;
@end

@interface FileTransferUploadStatus : NSObject
@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, readonly) uint64_t size;
@property (nonatomic, readonly) uint64_t offset;
@property (nonatomic, readonly) BOOL complete;
+ (nullable instancetype)parse:(NSData *)data;
@end

typedef void (^FileTransferReply)(NSData * _Nullable data, NSHTTPURLResponse * _Nullable response, NSError * _Nullable error);
@protocol FileTransferTransport <NSObject>
- (void)performMethod:(NSString *)method route:(NSString *)route query:(NSDictionary<NSString *, NSString *> *)query
    body:(nullable NSData *)body contentType:(nullable NSString *)contentType completion:(FileTransferReply)completion;
@end
NS_ASSUME_NONNULL_END
