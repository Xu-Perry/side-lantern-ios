#import <UIKit/UIKit.h>
@class TemporaryHost, FileTransferManager;

@interface FileTransferViewController : UITableViewController
- (instancetype)initWithHost:(TemporaryHost *)host;
- (instancetype)initWithHost:(TemporaryHost *)host manager:(FileTransferManager *)manager;
@end
