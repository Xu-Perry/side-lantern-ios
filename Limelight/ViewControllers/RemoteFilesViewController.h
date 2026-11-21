#import <UIKit/UIKit.h>
@class FileTransferManager;

@interface RemoteFilesViewController : UIViewController
- (instancetype)initWithManager:(FileTransferManager *)manager;
@end
