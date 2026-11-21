#import "FileTransferManager.h"

NSNotificationName const FileTransferManagerDidChange = @"SideLantern.FileTransfersChanged";

@interface FileTransferTask ()
@property (nonatomic, copy) NSString *identifier, *name, *root, *path, *version, *uploadIdentifier;
@property (nonatomic) BOOL upload, needsStatus;
@property (nonatomic) NSUInteger recoveries;
@property (nonatomic) FileTransferState state;
@property (nonatomic) uint64_t size, offset;
@property (nonatomic, strong) NSDate *date;
@property (nonatomic, strong) NSError *error;
@property (nonatomic, strong) NSURL *localURL;
@end
@implementation FileTransferTask
- (id)copyWithZone:(NSZone *)zone {
    FileTransferTask *copy = [[FileTransferTask alloc] init];
    copy.identifier = self.identifier; copy.name = self.name; copy.upload = self.upload; copy.state = self.state;
    copy.size = self.size; copy.offset = self.offset; copy.date = self.date; copy.error = self.error; copy.localURL = self.localURL;
    return copy;
}
@end

@interface FileTransferManager ()
@property (atomic, copy) NSArray<FileTransferTask *> *tasks;
@property (atomic, strong) FileTransferCapabilities *capabilities;
@property (atomic, strong) NSError *capabilityError;
@property (atomic) BOOL capabilitiesProbed;
@end

@implementation FileTransferManager {
    id<FileTransferTransport> _transport;
    NSURL *_directory;
    dispatch_queue_t _queue;
    NSMutableArray<FileTransferTask *> *_records;
    BOOL _busy, _probing;
    NSMutableArray<void (^)(void)> *_probeCompletions;
}
- (instancetype)initWithTransport:(id<FileTransferTransport>)transport directory:(NSURL *)directory {
    if ((self = [super init])) {
        _transport = transport; _directory = directory; _queue = dispatch_queue_create("SideLantern.FileTransfers", DISPATCH_QUEUE_SERIAL);
        _records = [NSMutableArray array]; _probeCompletions = [NSMutableArray array]; _tasks = @[];
        [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
        [directory setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
        NSData *saved = [NSData dataWithContentsOfURL:[directory URLByAppendingPathComponent:@"tasks.json"]];
        id json = saved ? [NSJSONSerialization JSONObjectWithData:saved options:0 error:nil] : nil;
        if ([json isKindOfClass:NSArray.class]) for (id row in json) {
            if (![row isKindOfClass:NSDictionary.class] || ![row[@"id"] isKindOfClass:NSString.class] || ![[NSUUID alloc] initWithUUIDString:row[@"id"]] || !FileTransferValidName(row[@"name"]) ||
                !FileTransferUnsigned(row[@"size"], INT64_MAX) || !FileTransferUnsigned(row[@"offset"], INT64_MAX) ||
                ![row[@"upload"] isKindOfClass:NSNumber.class] || ![row[@"date"] isKindOfClass:NSNumber.class] ||
                !FileTransferUnsigned(row[@"state"], FileTransferCancelled) || [row[@"offset"] unsignedLongLongValue] > [row[@"size"] unsignedLongLongValue]) continue;
            FileTransferTask *task = [[FileTransferTask alloc] init]; task.identifier = row[@"id"]; task.name = row[@"name"];
            task.upload = [row[@"upload"] boolValue]; task.size = [row[@"size"] unsignedLongLongValue]; task.offset = [row[@"offset"] unsignedLongLongValue];
            task.date = [NSDate dateWithTimeIntervalSince1970:[row[@"date"] doubleValue]];
            task.root = [row[@"root"] isKindOfClass:NSString.class] ? row[@"root"] : @"";
            task.path = [row[@"path"] isKindOfClass:NSString.class] ? row[@"path"] : @"";
            task.version = [row[@"version"] isKindOfClass:NSString.class] ? row[@"version"] : @"";
            task.uploadIdentifier = [row[@"upload_id"] isKindOfClass:NSString.class] ? row[@"upload_id"] : nil;
            task.localURL = [self fileURLForTask:task];
            NSInteger state = [row[@"state"] integerValue];
            task.state = state == FileTransferCompleted || state == FileTransferCancelled ? state : FileTransferPaused;
            task.needsStatus = YES;
            if (!task.upload && task.state != FileTransferCompleted) {
                task.offset = [[NSFileManager.defaultManager attributesOfItemAtPath:task.localURL.path error:nil][NSFileSize] unsignedLongLongValue];
                if (task.offset > task.size || (task.offset > 0 && task.version.length == 0)) task.offset = 0;
            }
            [_records addObject:task];
        }
        [self publish];
    } return self;
}
- (NSURL *)fileURLForTask:(FileTransferTask *)task {
    return [[[_directory URLByAppendingPathComponent:@"data" isDirectory:YES] URLByAppendingPathComponent:task.identifier isDirectory:YES] URLByAppendingPathComponent:task.name];
}
- (void)publish {
    NSMutableArray *snapshots = [NSMutableArray array], *saved = [NSMutableArray array];
    for (FileTransferTask *task in _records) {
        [snapshots addObject:task.copy];
        [saved addObject:@{@"id":task.identifier, @"name":task.name, @"upload":@(task.upload), @"state":@(task.state),
            @"size":@(task.size), @"offset":@(task.offset), @"date":@(task.date.timeIntervalSince1970),
            @"root":task.root ?: @"", @"path":task.path ?: @"", @"version":task.version ?: @"", @"upload_id":task.uploadIdentifier ?: @""}];
    }
    self.tasks = snapshots;
    NSData *data = [NSJSONSerialization dataWithJSONObject:saved options:0 error:nil];
    [data writeToURL:[_directory URLByAppendingPathComponent:@"tasks.json"] options:NSDataWritingAtomic error:nil];
    dispatch_async(dispatch_get_main_queue(), ^{ [NSNotificationCenter.defaultCenter postNotificationName:FileTransferManagerDidChange object:self]; });
}
- (void)refreshCapabilities:(void (^)(void))completion {
    dispatch_async(_queue, ^{
        if (completion) [self->_probeCompletions addObject:[completion copy]];
        if (self->_probing) return;
        self->_probing = YES;
        [self->_transport performMethod:@"GET" route:@"" query:@{} body:nil contentType:nil completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
            dispatch_async(self->_queue, ^{
                NSError *failure = FileTransferResponseError(data, response, error);
                FileTransferCapabilities *capabilities = !failure ? [FileTransferCapabilities parse:data] : nil;
                self.capabilityError = failure ?: (capabilities ? nil : FileTransferError(@"not_supported", 0));
                if (capabilities) self.capabilities = capabilities;
                self.capabilitiesProbed = YES; self->_probing = NO;
                NSArray *callbacks = self->_probeCompletions.copy; [self->_probeCompletions removeAllObjects];
                [self publish]; [self schedule];
                dispatch_async(dispatch_get_main_queue(), ^{ for (void (^callback)(void) in callbacks) callback(); });
            });
        }];
    });
}
- (void)listRoot:(NSString *)root path:(NSString *)path offset:(NSNumber *)offset completion:(void (^)(FileTransferListing *, NSError *))completion {
    NSMutableDictionary *query = [@{@"root":root, @"path":path} mutableCopy]; if (offset) query[@"offset"] = offset.stringValue;
    [_transport performMethod:@"GET" route:@"/list" query:query body:nil contentType:nil completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        NSError *failure = FileTransferResponseError(data, response, error);
        FileTransferListing *listing = failure ? nil : [FileTransferListing parse:data];
        if (!failure && !listing) failure = FileTransferError(@"invalid_response", 0);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(listing, failure); });
    }];
}
- (FileTransferTask *)newTaskNamed:(NSString *)name upload:(BOOL)upload {
    FileTransferTask *task = [[FileTransferTask alloc] init]; task.identifier = NSUUID.UUID.UUIDString; task.name = name;
    task.upload = upload; task.date = NSDate.date; task.localURL = [self fileURLForTask:task]; [_records addObject:task]; return task;
}
- (void)enqueueUpload:(NSURL *)file name:(NSString *)name {
    [self enqueueUpload:file name:name completion:nil];
}
- (void)enqueueUpload:(NSURL *)file name:(NSString *)name completion:(void (^)(NSError *))completion {
    NSString *filename = FileTransferValidName(name) ? name : file.lastPathComponent;
    if (!FileTransferValidName(filename)) {
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(FileTransferError(@"invalid_path", 0)); });
        return;
    }
    dispatch_async(_queue, ^{
        FileTransferTask *task = [self newTaskNamed:filename upload:YES]; task.state = FileTransferPreparing; [self publish];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            BOOL scoped = [file startAccessingSecurityScopedResource];
            __block NSError *copyError;
            __block uint64_t size = 0;
            NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
            NSError *coordinationError;
            [coordinator coordinateReadingItemAtURL:file options:0 error:&coordinationError byAccessor:^(NSURL *source) {
                NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:source.path error:&copyError];
                size = [attributes[NSFileSize] unsignedLongLongValue];
                if (![attributes[NSFileType] isEqualToString:NSFileTypeRegular]) copyError = FileTransferError(@"local_file_unavailable", 0);
                else if (size > (self.capabilities ? self.capabilities.maxUploadBytes : 8ULL * 1024 * 1024 * 1024)) copyError = FileTransferError(@"file_too_large", 413);
                if (!copyError) {
                    [NSFileManager.defaultManager createDirectoryAtURL:task.localURL.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&copyError];
                    if (!copyError) [NSFileManager.defaultManager copyItemAtURL:source toURL:task.localURL error:&copyError];
                }
            }];
            if (scoped) [file stopAccessingSecurityScopedResource];
            dispatch_async(self->_queue, ^{
                task.size = size;
                if (task.state != FileTransferCancelled) { task.error = copyError ?: coordinationError; task.state = task.error ? FileTransferFailed : FileTransferQueued; }
                else [NSFileManager.defaultManager removeItemAtURL:task.localURL.URLByDeletingLastPathComponent error:nil];
                [self publish]; [self schedule];
                if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(copyError ?: coordinationError); });
            });
        });
    });
}
- (void)enqueueDownload:(FileTransferEntry *)entry root:(NSString *)root path:(NSString *)path {
    if (entry.directory) return;
    dispatch_async(_queue, ^{
        FileTransferTask *task = [self newTaskNamed:entry.name upload:NO]; task.root = root; task.path = path;
        task.version = entry.version; task.size = entry.size; task.state = FileTransferQueued; [self publish]; [self schedule];
    });
}
- (FileTransferTask *)findTask:(NSString *)identifier {
    for (FileTransferTask *task in _records) if ([task.identifier isEqualToString:identifier]) return task;
    return nil;
}
- (void)pauseTask:(NSString *)identifier {
    dispatch_async(_queue, ^{ FileTransferTask *task = [self findTask:identifier];
        if (task && (task.state == FileTransferRunning || task.state == FileTransferQueued)) { task.state = FileTransferPaused; task.needsStatus = YES; [self publish]; [self schedule]; }
    });
}
- (void)resumeTask:(NSString *)identifier {
    dispatch_async(_queue, ^{
        FileTransferTask *task = [self findTask:identifier];
        if (!task || (task.state != FileTransferPaused && task.state != FileTransferFailed)) return;
        if ([task.error.userInfo[@"reason"] isEqualToString:@"file_changed"]) { task.offset = 0; task.version = @""; }
        task.error = nil; task.recoveries = 0; task.needsStatus = YES; task.state = FileTransferQueued;
        [self publish]; [self schedule];
    });
}
- (void)cancelTask:(NSString *)identifier {
    dispatch_async(_queue, ^{
        FileTransferTask *task = [self findTask:identifier];
        if (!task || task.state == FileTransferCompleted || task.state == FileTransferCancelled) return;
        task.state = FileTransferCancelled;
        [NSFileManager.defaultManager removeItemAtURL:task.localURL.URLByDeletingLastPathComponent error:nil];
        if (task.uploadIdentifier.length) [self cancelRemote:task];
        [self publish]; [self schedule];
    });
}
- (void)cancelRemote:(FileTransferTask *)task {
    [_transport performMethod:@"DELETE" route:@"/uploads" query:@{@"id":task.uploadIdentifier} body:nil contentType:nil completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        dispatch_async(self->_queue, ^{
            NSError *failure = FileTransferResponseError(data, response, error);
            if ([failure.userInfo[@"reason"] isEqualToString:@"upload_already_complete"]) { task.offset = task.size; task.state = FileTransferCompleted; [self publish]; }
        });
    }];
}
- (void)clearHistory {
    dispatch_async(_queue, ^{
        NSIndexSet *finished = [self->_records indexesOfObjectsPassingTest:^BOOL(FileTransferTask *task, NSUInteger index, BOOL *stop) {
            return task.state == FileTransferCompleted || task.state == FileTransferCancelled;
        }];
        [self->_records removeObjectsAtIndexes:finished]; [self publish];
    });
}
- (void)schedule {
    if (_busy || !self.capabilities) return;
    for (FileTransferTask *task in _records) if (task.state == FileTransferQueued) {
        task.state = FileTransferRunning; _busy = YES; [self publish];
        if (task.upload) [self uploadStep:task]; else [self downloadStep:task];
        return;
    }
}
- (void)failTask:(FileTransferTask *)task error:(NSError *)error {
    if (task.state != FileTransferCancelled && task.state != FileTransferPaused) { task.error = error; task.state = FileTransferFailed; }
}
- (void)requestTask:(FileTransferTask *)task method:(NSString *)method route:(NSString *)route query:(NSDictionary *)query body:(NSData *)body
    contentType:(NSString *)type handler:(void (^)(NSData *, NSHTTPURLResponse *, NSError *))handler {
    [_transport performMethod:method route:route query:query body:body contentType:type completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        dispatch_async(self->_queue, ^{
            NSError *failure = FileTransferResponseError(data, response, error);
            handler(data, response, failure);
            self->_busy = NO;
            if (task.state == FileTransferRunning) task.state = FileTransferQueued;
            [self publish]; [self schedule];
        });
    }];
}
- (void)uploadStep:(FileTransferTask *)task {
    if (!self.capabilities.upload) { [self failTask:task error:FileTransferError(@"upload_disabled", 403)]; _busy = NO; [self publish]; [self schedule]; return; }
    NSString *method, *route = @"/uploads"; NSDictionary *query = @{}; NSData *body = nil; NSString *type = nil;
    BOOL querying = task.uploadIdentifier.length > 0 && task.needsStatus;
    if (task.uploadIdentifier.length == 0) {
        method = @"POST"; type = @"application/json";
        body = [NSJSONSerialization dataWithJSONObject:@{@"name":task.name, @"size":@(task.size)} options:0 error:nil];
    } else {
        query = @{@"id":task.uploadIdentifier};
        if (querying) method = @"GET";
        else if (task.offset == task.size) { method = @"POST"; route = @"/uploads/complete"; }
        else {
            method = @"PUT"; query = @{@"id":task.uploadIdentifier, @"offset":@(task.offset).stringValue}; type = @"application/octet-stream";
            NSError *error; NSFileHandle *file = [NSFileHandle fileHandleForReadingFromURL:task.localURL error:&error];
            if (file && [file seekToOffset:task.offset error:&error]) body = [file readDataUpToLength:(NSUInteger)MIN(self.capabilities.uploadChunkBytes, task.size - task.offset) error:&error];
            [file closeAndReturnError:nil];
            if (error || body.length == 0) { [self failTask:task error:error ?: FileTransferError(@"local_file_unavailable", 0)]; _busy = NO; [self publish]; [self schedule]; return; }
        }
    }
    uint64_t expectedOffset = task.offset + ([method isEqualToString:@"PUT"] ? body.length : 0);
    [self requestTask:task method:method route:route query:query body:body contentType:type handler:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        if (error) {
            if (querying && error.code == 404) { task.uploadIdentifier = nil; task.offset = 0; task.needsStatus = NO; return; }
            if (task.uploadIdentifier.length && !querying && ([error.userInfo[@"reason"] isEqualToString:@"offset_mismatch"] || [error.domain isEqualToString:NSURLErrorDomain]) && task.recoveries++ < 2) { task.needsStatus = YES; return; }
            [self failTask:task error:error]; return;
        }
        FileTransferUploadStatus *status = [FileTransferUploadStatus parse:data];
        if (!status || ![status.name isEqualToString:task.name] || status.size != task.size ||
            ([route isEqualToString:@"/uploads/complete"] && !status.complete) ||
            (task.uploadIdentifier.length && ![task.uploadIdentifier isEqualToString:status.identifier]) ||
            ([method isEqualToString:@"PUT"] && status.offset != expectedOffset)) { [self failTask:task error:FileTransferError(@"invalid_response", 0)]; return; }
        task.uploadIdentifier = status.identifier; task.offset = status.offset; task.needsStatus = NO;
        if (status.complete) {
            task.state = FileTransferCompleted; task.date = NSDate.date;
            [NSFileManager.defaultManager removeItemAtURL:task.localURL.URLByDeletingLastPathComponent error:nil];
        }
        else if (task.state == FileTransferCancelled) [self cancelRemote:task];
    }];
}
- (void)downloadStep:(FileTransferTask *)task {
    NSMutableDictionary *query = [@{@"root":task.root, @"path":task.path, @"offset":@(task.offset).stringValue,
        @"length":@(self.capabilities.downloadChunkBytes).stringValue} mutableCopy];
    if (task.version.length) query[@"version"] = task.version;
    [self requestTask:task method:@"GET" route:@"/download" query:query body:nil contentType:nil handler:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        if (task.state == FileTransferCancelled) return;
        if (error) { [self failTask:task error:error]; return; }
        NSString *sizeText = [response valueForHTTPHeaderField:@"X-SideLantern-File-Size"], *version = [response valueForHTTPHeaderField:@"X-SideLantern-File-Version"];
        unsigned long long size = 0; NSScanner *scanner = [NSScanner scannerWithString:sizeText ?: @""]; scanner.charactersToBeSkipped = nil;
        if (![scanner scanUnsignedLongLong:&size] || !scanner.isAtEnd || size > INT64_MAX || task.offset > size || version.length == 0 ||
            ![response.MIMEType isEqualToString:@"application/octet-stream"] || (task.version.length && task.size != size) ||
            data.length > self.capabilities.downloadChunkBytes || data.length > size - task.offset ||
            (task.version.length && ![version isEqualToString:task.version]) || (data.length == 0 && task.offset < size)) {
            [self failTask:task error:FileTransferError(@"invalid_response", 0)]; return;
        }
        NSError *writeError;
        [NSFileManager.defaultManager createDirectoryAtURL:task.localURL.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&writeError];
        if (!writeError && ![NSFileManager.defaultManager fileExistsAtPath:task.localURL.path]) [NSFileManager.defaultManager createFileAtPath:task.localURL.path contents:nil attributes:nil];
        NSFileHandle *file = writeError ? nil : [NSFileHandle fileHandleForWritingToURL:task.localURL error:&writeError];
        if (file && [file seekToOffset:task.offset error:&writeError]) [file writeData:data error:&writeError];
        if (!writeError && task.offset + data.length == size) [file truncateAtOffset:size error:&writeError];
        [file closeAndReturnError:nil];
        if (writeError || !file) { [self failTask:task error:writeError ?: FileTransferError(@"file_io_error", 0)]; return; }
        task.size = size; task.offset += data.length; task.version = version;
        if (task.offset == size) { task.state = FileTransferCompleted; task.date = NSDate.date; }
    }];
}
@end
