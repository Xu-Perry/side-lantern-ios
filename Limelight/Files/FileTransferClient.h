#import "FileTransferProtocol.h"
@class TemporaryHost, FileTransferManager;

@interface FileTransferClient : NSObject <FileTransferTransport>
- (instancetype)initWithHost:(TemporaryHost *)host;
@end

FOUNDATION_EXPORT FileTransferManager *FileTransferManagerForHost(TemporaryHost *host);
