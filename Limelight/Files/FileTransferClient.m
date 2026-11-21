#import "FileTransferClient.h"
#import "FileTransferManager.h"
#import "HttpManager.h"

@implementation FileTransferClient {
    TemporaryHost *_host;
    HttpManager *_http;
    NSURLSession *_session;
    NSURL *_baseURL;
    dispatch_queue_t _queue;
    NSString *_address;
    NSData *_certificate;
}
- (instancetype)initWithHost:(TemporaryHost *)host {
    if ((self = [super init])) { _host = host; _queue = dispatch_queue_create("SideLantern.FileConnection", DISPATCH_QUEUE_SERIAL); }
    return self;
}
- (void)updateHost:(TemporaryHost *)host { dispatch_async(_queue, ^{ self->_host = host; }); }
- (void)performMethod:(NSString *)method route:(NSString *)route query:(NSDictionary<NSString *,NSString *> *)query
    body:(NSData *)body contentType:(NSString *)contentType completion:(FileTransferReply)completion {
    dispatch_async(_queue, ^{
        NSString *address = self->_host.activeAddress; NSData *certificate = self->_host.serverCert;
        if (address.length == 0 || certificate.length == 0) { completion(nil, nil, FileTransferError(@"connection_unavailable", 0)); return; }
        if (!self->_session || ![self->_address isEqualToString:address] || ![self->_certificate isEqualToData:certificate]) {
            [self->_session finishTasksAndInvalidate];
            self->_http = [[HttpManager alloc] initWithAddress:address httpsPort:self->_host.httpsPort serverCert:certificate];
            self->_baseURL = [self->_http fileTransferBaseURL];
            self->_address = address.copy; self->_certificate = certificate.copy;
            self->_session = self->_baseURL ? [self->_http newFileTransferSession] : nil;
        }
        NSURLRequest *request = self->_baseURL ? FileTransferRequest(self->_baseURL, method, route, query, body, contentType) : nil;
        if (!request) { completion(nil, nil, FileTransferError(@"connection_unavailable", 0)); return; }
        [[self->_session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            completion(data, [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil, error);
        }] resume];
    });
}
- (void)dealloc { [_session invalidateAndCancel]; }
@end

FileTransferManager *FileTransferManagerForHost(TemporaryHost *host) {
    static NSMutableDictionary<NSString *, NSDictionary *> *managers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ managers = [NSMutableDictionary dictionary]; });
    @synchronized(managers) {
        NSDictionary *record = managers[host.uuid];
        FileTransferManager *manager = record[@"manager"];
        if (!manager) {
            NSURL *base = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
            NSMutableString *key = [NSMutableString string];
            NSData *identity = [host.uuid dataUsingEncoding:NSUTF8StringEncoding];
            const unsigned char *bytes = identity.bytes;
            for (NSUInteger i = 0; i < identity.length; i++) [key appendFormat:@"%02x", bytes[i]];
            NSURL *directory = [[base URLByAppendingPathComponent:@"SideLanternTransfers" isDirectory:YES] URLByAppendingPathComponent:key isDirectory:YES];
            FileTransferClient *client = [[FileTransferClient alloc] initWithHost:host];
            manager = [[FileTransferManager alloc] initWithTransport:client directory:directory];
            managers[host.uuid] = @{@"manager":manager, @"client":client};
        } else [(FileTransferClient *)record[@"client"] updateHost:host];
        return manager;
    }
}
