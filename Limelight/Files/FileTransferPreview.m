#import "FileTransferPreview.h"
#if DEBUG && TARGET_OS_SIMULATOR
#import "FileTransferViewController.h"
#import "RemoteFilesViewController.h"
#import "FileTransferManager.h"
#import "TemporaryHost.h"

@interface FileTransferPreviewTransport : NSObject <FileTransferTransport>
@property (nonatomic, strong) NSMutableDictionary *uploads;
@end
@implementation FileTransferPreviewTransport
- (instancetype)init { if ((self = [super init])) _uploads = [NSMutableDictionary dictionary]; return self; }
- (void)performMethod:(NSString *)method route:(NSString *)route query:(NSDictionary<NSString *,NSString *> *)query body:(NSData *)body contentType:(NSString *)type completion:(FileTransferReply)completion {
    @synchronized(self) {
        NSDictionary *json; NSData *data; NSDictionary *headers = @{@"Content-Type":@"application/json"}; NSInteger status = 200;
        if (route.length == 0) json = @{@"version":@1, @"enabled":@YES, @"upload":@YES, @"upload_chunk_bytes":@49152, @"download_chunk_bytes":@1048576,
            @"max_upload_bytes":@(8ULL * 1024 * 1024 * 1024), @"upload_idle_seconds":@1800,
            @"roots":@[@{@"id":@"c", @"label":@"(C:)"}, @{@"id":@"d", @"label":@"pan (D:)"}, @{@"id":@"docs", @"label":@"文档"},
                @{@"id":@"desktop", @"label":@"桌面"}, @{@"id":@"photos", @"label":@"图片"}, @{@"id":@"videos", @"label":@"视频"}, @{@"id":@"downloads", @"label":@"下载"}]};
        else if ([route isEqualToString:@"/list"]) {
            NSArray *entries = @[@{@"name":@"项目资料", @"kind":@"directory", @"size":@0, @"modified_unix_ms":@1795200000000, @"version":@""},
                @{@"name":@"会议记录.txt", @"kind":@"file", @"size":@38, @"modified_unix_ms":@1795200000000, @"version":@"sample-v1"},
                @{@"name":@"workflow-style-demo-with-a-long-filename.txt", @"kind":@"file", @"size":@38, @"modified_unix_ms":@1795200000000, @"version":@"sample-v1"}];
            if (query[@"path"].length) entries = @[entries[1], entries[2]];
            json = @{@"entries":entries, @"next_offset":NSNull.null, @"truncated":@NO};
        } else if ([route isEqualToString:@"/download"]) {
            NSData *sample = [@"SideLantern file transfer sample data." dataUsingEncoding:NSUTF8StringEncoding]; NSUInteger offset = [query[@"offset"] integerValue];
            data = [sample subdataWithRange:NSMakeRange(MIN(offset, sample.length), sample.length - MIN(offset, sample.length))];
            headers = @{@"Content-Type":@"application/octet-stream", @"X-SideLantern-File-Size":@(sample.length).stringValue, @"X-SideLantern-File-Version":@"sample-v1"};
        } else {
            NSMutableDictionary *job = self.uploads[query[@"id"]];
            if ([method isEqualToString:@"POST"] && [route isEqualToString:@"/uploads"]) {
                NSDictionary *request = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil]; NSString *identifier = NSUUID.UUID.UUIDString;
                job = [@{@"id":identifier, @"name":request[@"name"], @"size":request[@"size"], @"offset":@0, @"complete":@NO} mutableCopy]; self.uploads[identifier] = job; status = 201;
            } else if ([method isEqualToString:@"DELETE"]) { [self.uploads removeObjectForKey:query[@"id"]]; json = @{@"cancelled":@YES}; }
            else if ([method isEqualToString:@"PUT"]) job[@"offset"] = @([job[@"offset"] unsignedLongLongValue] + body.length);
            else if ([route isEqualToString:@"/uploads/complete"]) job[@"complete"] = @YES;
            if (!json) json = job ?: @{@"error":@"upload_not_found"};
        }
        if (!data) data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://preview/sidelantern/v1/files"] statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:headers];
        completion(data, response, nil);
    }
}
@end

static UITableView *PreviewRootTable(UIView *view) {
    if ([view isKindOfClass:UITableView.class] && [view.accessibilityIdentifier isEqualToString:@"file-transfer-roots"]) return (UITableView *)view;
    for (UIView *child in view.subviews) { UITableView *table = PreviewRootTable(child); if (table) return table; }
    return nil;
}

UIViewController *FileTransferPreview(BOOL browser) {
    NSURL *directory = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSMutableArray *rows = [NSMutableArray array];
    NSArray *names = @[@"会议记录.txt", @"workflow-style-demo-with-a-long-filename.txt", @"准备发送的资料.txt"];
    for (NSUInteger i = 0; i < names.count; i++) {
        NSString *identifier = NSUUID.UUID.UUIDString;
        NSURL *folder = [[directory URLByAppendingPathComponent:@"data" isDirectory:YES] URLByAppendingPathComponent:identifier isDirectory:YES];
        [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];
        NSData *data = [@"SideLantern sample file.\n" dataUsingEncoding:NSUTF8StringEncoding];
        [data writeToURL:[folder URLByAppendingPathComponent:names[i]] atomically:YES];
        [rows addObject:@{@"id":identifier, @"name":names[i], @"size":@(data.length), @"offset":@(i == 2 ? 0 : data.length), @"date":@(NSDate.date.timeIntervalSince1970 - i * 86400),
            @"upload":@(i == 2), @"state":@(i == 2 ? FileTransferPaused : FileTransferCompleted), @"root":@"docs", @"path":names[i], @"version":@"sample-v1", @"upload_id":@""}];
    }
    [[NSJSONSerialization dataWithJSONObject:rows options:0 error:nil] writeToURL:[directory URLByAppendingPathComponent:@"tasks.json"] atomically:YES];
    FileTransferManager *manager = [[FileTransferManager alloc] initWithTransport:[[FileTransferPreviewTransport alloc] init] directory:directory];
    TemporaryHost *host = [[TemporaryHost alloc] init]; host.name = @"示例主机"; host.uuid = @"file-preview"; host.state = StateOnline; host.pairState = PairStatePaired;
    FileTransferViewController *home = [[FileTransferViewController alloc] initWithHost:host manager:manager];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:home]; navigation.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--sidelantern-file-preview-light"]) navigation.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    [manager refreshCapabilities:^{
        if (browser) {
            RemoteFilesViewController *files = [[RemoteFilesViewController alloc] initWithManager:manager];
            [navigation setViewControllers:@[home, files] animated:NO];
            if ([NSProcessInfo.processInfo.arguments containsObject:@"--sidelantern-file-preview-directory"]) {
                [files loadViewIfNeeded]; UITableView *roots = PreviewRootTable(files.view);
                [roots.delegate tableView:roots didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:0]];
            }
        }
    }];
    return navigation;
}
#endif
