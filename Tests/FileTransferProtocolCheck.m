#import <Foundation/Foundation.h>
#import "FileTransferProtocol.h"
#import "FileTransferManager.h"
#include <assert.h>

static NSData *JSON(id object) { return [NSJSONSerialization dataWithJSONObject:object options:0 error:nil]; }
static NSDictionary *Capabilities(void) {
    return @{@"version":@1, @"enabled":@YES, @"upload":@YES, @"roots":@[@{@"id":@"docs", @"label":@"文档"}],
        @"upload_chunk_bytes":@4, @"download_chunk_bytes":@3, @"max_upload_bytes":@(8ULL * 1024 * 1024 * 1024), @"upload_idle_seconds":@1800};
}
static void Wait(BOOL (^condition)(void)) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!condition() && limit.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    assert(condition());
}
static FileTransferEntry *Entry(NSString *name, NSUInteger size, NSString *version) {
    return [FileTransferListing parse:JSON(@{@"entries":@[@{@"name":name, @"kind":@"file", @"size":@(size), @"modified_unix_ms":@1234, @"version":version}],
        @"next_offset":NSNull.null, @"truncated":@NO})].entries.firstObject;
}

@interface FakeFiles : NSObject <FileTransferTransport>
@property (atomic, strong) NSData *contents;
@property (atomic, copy) NSString *version;
@property (atomic) BOOL holdCreate, holdDownload, holdAppend, loseAppend, mismatchAppend;
@property (atomic, copy) void (^held)(void);
@property (atomic, strong) NSMutableDictionary *uploads;
@property (atomic) NSUInteger statusQueries, downloadRequests;
@end
@implementation FakeFiles
- (instancetype)init { if ((self = [super init])) { _contents = [@"a\0bcdefgh" dataUsingEncoding:NSUTF8StringEncoding]; _version = @"v1"; _uploads = [NSMutableDictionary dictionary]; } return self; }
- (void)performMethod:(NSString *)method route:(NSString *)route query:(NSDictionary<NSString *,NSString *> *)query body:(NSData *)body contentType:(NSString *)type completion:(FileTransferReply)completion {
    @synchronized(self) {
        NSInteger status = 200; NSDictionary *headers = @{@"Content-Type":@"application/json"}; NSData *data;
        BOOL hold = NO, lose = NO;
        if (route.length == 0) data = JSON(Capabilities());
        else if ([route isEqualToString:@"/download"]) {
            self.downloadRequests++;
            NSUInteger offset = [query[@"offset"] integerValue], length = [query[@"length"] integerValue];
            assert(length <= 3);
            if (query[@"version"].length && ![query[@"version"] isEqualToString:self.version]) { status = 409; data = JSON(@{@"error":@"file_changed"}); }
            else {
                assert(offset <= self.contents.length); if (offset > 0) assert(query[@"version"].length > 0);
                data = [self.contents subdataWithRange:NSMakeRange(offset, MIN(length, self.contents.length - offset))];
                headers = @{@"Content-Type":@"application/octet-stream", @"X-SideLantern-File-Size":@(self.contents.length).stringValue, @"X-SideLantern-File-Version":self.version};
                hold = self.holdDownload; self.holdDownload = NO;
            }
        } else if ([route isEqualToString:@"/uploads"] && [method isEqualToString:@"POST"]) {
            assert([type isEqualToString:@"application/json"]);
            NSDictionary *request = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
            NSString *identifier = NSUUID.UUID.UUIDString;
            NSMutableDictionary *job = [@{@"id":identifier, @"name":request[@"name"], @"size":request[@"size"], @"bytes":[NSMutableData data], @"complete":@NO} mutableCopy];
            self.uploads[identifier] = job; data = [self status:job]; status = 201;
            hold = self.holdCreate; self.holdCreate = NO;
        } else {
            NSMutableDictionary *job = self.uploads[query[@"id"]];
            if (!job) { status = 404; data = JSON(@{@"error":@"upload_not_found"}); }
            else if ([method isEqualToString:@"DELETE"]) { [self.uploads removeObjectForKey:query[@"id"]]; data = JSON(@{@"cancelled":@YES}); }
            else if ([method isEqualToString:@"GET"]) { self.statusQueries++; data = [self status:job]; }
            else if ([method isEqualToString:@"PUT"]) {
                NSMutableData *bytes = job[@"bytes"]; assert([type isEqualToString:@"application/octet-stream"] && body.length <= 4);
                if (self.mismatchAppend) {
                    self.mismatchAppend = NO; [bytes appendData:[body subdataWithRange:NSMakeRange(0, MIN(2, body.length))]];
                    status = 409; data = JSON(@{@"error":@"offset_mismatch"});
                } else if ([query[@"offset"] longLongValue] != bytes.length) { status = 409; data = JSON(@{@"error":@"offset_mismatch"}); }
                else {
                    [bytes appendData:body]; data = [self status:job];
                    lose = self.loseAppend; self.loseAppend = NO; hold = self.holdAppend; self.holdAppend = NO;
                }
            } else {
                assert([route isEqualToString:@"/uploads/complete"]);
                assert([job[@"bytes"] length] == [job[@"size"] unsignedLongLongValue]); job[@"complete"] = @YES; data = [self status:job];
            }
        }
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://host/sidelantern/v1/files"] statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:headers];
        void (^reply)(void) = ^{ completion(lose ? nil : data, lose ? nil : response, lose ? [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil] : nil); };
        if (hold) self.held = reply; else reply();
    }
}
- (NSData *)status:(NSDictionary *)job { return JSON(@{@"id":job[@"id"], @"name":job[@"name"], @"size":job[@"size"], @"offset":@([job[@"bytes"] length]), @"complete":job[@"complete"]}); }
- (void)releaseReply { void (^reply)(void) = self.held; self.held = nil; assert(reply); reply(); }
@end

static FileTransferManager *Manager(FakeFiles *server, NSURL *directory) {
    FileTransferManager *manager = [[FileTransferManager alloc] initWithTransport:server directory:directory];
    [manager refreshCapabilities:nil]; Wait(^BOOL { return manager.capabilities != nil; }); return manager;
}
static NSURL *Folder(NSURL *base) { return [base URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES]; }

int main(void) {
    @autoreleasepool {
        assert([FileTransferCapabilities parse:JSON(Capabilities())]);
        for (id bad in @[@2, @YES, @"1"]) { NSMutableDictionary *caps = Capabilities().mutableCopy; caps[@"version"] = bad; assert(![FileTransferCapabilities parse:JSON(caps)]); }
        NSMutableDictionary *caps = Capabilities().mutableCopy; caps[@"upload_chunk_bytes"] = @49153; assert(![FileTransferCapabilities parse:JSON(caps)]);
        caps = Capabilities().mutableCopy; caps[@"roots"] = @[@{@"id":@"../disk", @"label":@"Private"}]; assert(![FileTransferCapabilities parse:JSON(caps)]);
        assert(![FileTransferCapabilities parse:[@"<root status_code=\"404\"/>" dataUsingEncoding:NSUTF8StringEncoding]]);
        FileTransferListing *page = [FileTransferListing parse:JSON(@{@"entries":@[], @"next_offset":@512, @"truncated":@NO})];
        assert(page.nextOffset.integerValue == 512 && !page.truncated);
        assert([FileTransferListing parse:JSON(@{@"entries":@[], @"next_offset":NSNull.null, @"truncated":@YES})].truncated);
        for (NSNumber *badOffset in @[@(-1), @100001, @YES]) assert(![FileTransferListing parse:JSON(@{@"entries":@[], @"next_offset":badOffset, @"truncated":@NO})]);
        assert(!FileTransferValidName(@"../escape.bin") && !FileTransferValidName(@"a\\b.bin") && !FileTransferUnsigned(@(-1), INT64_MAX));
        assert(![FileTransferUploadStatus parse:JSON(@{@"id":@"x", @"name":@"x", @"size":@4, @"offset":@5, @"complete":@NO})]);
        NSURLRequest *request = FileTransferRequest([NSURL URLWithString:@"https://[::1]:47984"], @"GET", @"/download", @{@"root":@"docs", @"path":@"文档/a+b & #?.bin"}, nil, nil);
        NSURLComponents *url = [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
        assert([url.percentEncodedQuery containsString:@"%2B"] && [url.percentEncodedQuery containsString:@"%26"] && url.queryItems.count == 2);
        assert(!FileTransferRequest([NSURL URLWithString:@"http://host"], @"GET", @"", @{}, nil, nil));
        NSURL *base = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
        [NSFileManager.defaultManager createDirectoryAtURL:base withIntermediateDirectories:YES attributes:nil error:nil];
        NSData *original = [@"a\0bcdefgh" dataUsingEncoding:NSUTF8StringEncoding]; NSURL *source = [base URLByAppendingPathComponent:@"测试+文件.bin"];
        [original writeToURL:source atomically:YES];

        FakeFiles *server = [[FakeFiles alloc] init]; FileTransferManager *manager = Manager(server, Folder(base));
        server.holdAppend = YES; [manager enqueueUpload:source name:nil]; Wait(^BOOL { return server.held != nil; });
        NSString *identifier = manager.tasks.firstObject.identifier; [manager pauseTask:identifier]; Wait(^BOOL { return manager.tasks.firstObject.state == FileTransferPaused; });
        [server releaseReply]; Wait(^BOOL { return manager.tasks.firstObject.offset == 4; });
        [manager resumeTask:identifier]; Wait(^BOOL { return manager.tasks.firstObject.state == FileTransferCompleted; });
        assert(server.statusQueries > 0 && [server.uploads.allValues.firstObject[@"bytes"] isEqualToData:original]);

        for (NSNumber *mismatch in @[@NO, @YES]) {
            server = [[FakeFiles alloc] init]; manager = Manager(server, Folder(base));
            server.loseAppend = !mismatch.boolValue; server.mismatchAppend = mismatch.boolValue;
            [manager enqueueUpload:source name:nil]; Wait(^BOOL { return manager.tasks.firstObject.state == FileTransferCompleted; });
            assert(server.statusQueries > 0 && [server.uploads.allValues.firstObject[@"bytes"] isEqualToData:original]);
        }
        server = [[FakeFiles alloc] init]; manager = Manager(server, Folder(base)); server.holdCreate = YES;
        [manager enqueueUpload:source name:nil]; Wait(^BOOL { return server.held != nil; }); [manager cancelTask:manager.tasks.firstObject.identifier];
        Wait(^BOOL { return manager.tasks.firstObject.state == FileTransferCancelled; }); [server releaseReply]; Wait(^BOOL { return server.uploads.count == 0; });

        server = [[FakeFiles alloc] init]; NSURL *directory = Folder(base); manager = Manager(server, directory); server.holdDownload = YES;
        [manager enqueueDownload:Entry(@"remote.bin", original.length, @"v1") root:@"docs" path:@"remote.bin"];
        Wait(^BOOL { return server.held != nil; }); identifier = manager.tasks.firstObject.identifier; [manager pauseTask:identifier];
        Wait(^BOOL { return manager.tasks.firstObject.state == FileTransferPaused; }); [server releaseReply]; Wait(^BOOL { return manager.tasks.firstObject.offset == 3; });
        FileTransferManager *restored = Manager(server, directory); assert(restored.tasks.firstObject.state == FileTransferPaused && restored.tasks.firstObject.offset == 3);
        [restored resumeTask:identifier]; Wait(^BOOL { return restored.tasks.firstObject.state == FileTransferCompleted; });
        NSURL *received = restored.tasks.firstObject.localURL; assert([[NSData dataWithContentsOfURL:received] isEqualToData:original]);
        [restored clearHistory]; Wait(^BOOL { return restored.tasks.count == 0; }); assert([NSFileManager.defaultManager fileExistsAtPath:received.path]);

        server = [[FakeFiles alloc] init]; manager = Manager(server, Folder(base)); server.holdDownload = YES;
        [manager enqueueDownload:Entry(@"changed.bin", original.length, @"v1") root:@"docs" path:@"changed.bin"];
        Wait(^BOOL { return server.held != nil; }); identifier = manager.tasks.firstObject.identifier; [manager pauseTask:identifier];
        Wait(^BOOL { return manager.tasks.firstObject.state == FileTransferPaused; }); [server releaseReply]; Wait(^BOOL { return manager.tasks.firstObject.offset == 3; });
        server.version = @"v2"; server.contents = [@"new" dataUsingEncoding:NSUTF8StringEncoding]; [manager resumeTask:identifier];
        Wait(^BOOL { return manager.tasks.firstObject.state == FileTransferFailed; }); assert([manager.tasks.firstObject.error.userInfo[@"reason"] isEqualToString:@"file_changed"]);
        [manager resumeTask:identifier]; Wait(^BOOL { return manager.tasks.firstObject.state == FileTransferCompleted; });
        assert([[NSData dataWithContentsOfURL:manager.tasks.firstObject.localURL] isEqualToData:server.contents]);

        server = [[FakeFiles alloc] init]; server.contents = NSData.data; manager = Manager(server, Folder(base));
        [manager enqueueDownload:Entry(@"empty.bin", 0, @"v1") root:@"docs" path:@"empty.bin"];
        Wait(^BOOL { return manager.tasks.firstObject.state == FileTransferCompleted; }); assert([NSData dataWithContentsOfURL:manager.tasks.firstObject.localURL].length == 0);
        NSURL *empty = [base URLByAppendingPathComponent:@"empty-upload.bin"]; [NSData.data writeToURL:empty atomically:YES];
        [manager enqueueUpload:empty name:nil]; Wait(^BOOL { return manager.tasks.count == 2 && manager.tasks.lastObject.state == FileTransferCompleted; });
        [NSFileManager.defaultManager removeItemAtURL:base error:nil];
        puts("File transfer protocol, binary integrity, pause/resume, lost replies, cancellation and persistence checks passed.");
    }
    return 0;
}
