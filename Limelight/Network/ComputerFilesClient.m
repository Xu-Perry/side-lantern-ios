#import "ComputerFilesClient.h"
#import "HttpManager.h"

#include <libxml2/libxml/xmlreader.h>

NSString* const ComputerFilesErrorDomain = @"ComputerFilesError";
static const NSUInteger ComputerFilesMaximumChunkSize = 1024 * 1024;

BOOL ComputerFilesIsValidEntryName(id value) {
    if (![value isKindOfClass:[NSString class]]) {
        return NO;
    }
    NSString* name = value;
    return name.length > 0 && ![name isEqualToString:@"."] && ![name isEqualToString:@".."] &&
           ![name containsString:@"/"] && ![name containsString:@"\\"] &&
           [name rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location == NSNotFound;
}

static NSError* ComputerFilesErrorWithCode(NSInteger code) {
    return [NSError errorWithDomain:ComputerFilesErrorDomain code:code userInfo:nil];
}

static NSInteger legacyGameStreamStatus(NSData* data) {
    if (data.length == 0 || data.length > 4096) {
        return ComputerFilesErrorInvalidResponse;
    }
    // Legacy GameStream error documents may declare UTF-16 while sending UTF-8.
    xmlTextReaderPtr reader = xmlReaderForMemory(data.bytes, (int)data.length, NULL, "UTF-8",
                                                XML_PARSE_NONET | XML_PARSE_NOERROR | XML_PARSE_NOWARNING);
    NSInteger status = ComputerFilesErrorInvalidResponse;
    if (reader) {
        while (xmlTextReaderRead(reader) == 1) {
            if (xmlTextReaderNodeType(reader) == XML_READER_TYPE_ELEMENT) {
                if (xmlStrEqual(xmlTextReaderConstName(reader), BAD_CAST "root")) {
                    xmlChar* attribute = xmlTextReaderGetAttribute(reader, BAD_CAST "status_code");
                    if (attribute) {
                        NSInteger code = [[NSString stringWithUTF8String:(const char*)attribute] integerValue];
                        if (code == 401 || code == 403 || code == 404) {
                            status = code;
                        }
                        xmlFree(attribute);
                    }
                }
                break;
            }
        }
        xmlFreeTextReader(reader);
    }
    return status;
}

@interface ComputerFileDownload : NSObject
@property (nonatomic, copy) NSString* root;
@property (nonatomic, copy) NSString* path;
@property (nonatomic, copy) NSString* version;
@property (nonatomic) uint64_t size;
@property (nonatomic) uint64_t offset;
@property (nonatomic) NSUInteger chunkSize;
@property (nonatomic, strong) NSURL* fileURL;
@property (nonatomic, strong) NSFileHandle* handle;
@property (nonatomic, copy) void (^progress)(double);
@property (nonatomic, copy) ComputerFilesDownloadCompletion completion;
@end

@implementation ComputerFileDownload
@end

@implementation ComputerFilesClient {
    TemporaryHost* _host;
    HttpManager* _manager;
    NSURLSession* _session;
    dispatch_queue_t _queue;
    NSURLSessionDownloadTask* _task;
    NSUUID* _requestID;
    ComputerFileDownload* _download;
}

- (instancetype)initWithHost:(TemporaryHost*)host {
    self = [super init];
    if (self) {
        _host = host;
        _queue = dispatch_queue_create("org.sidelantern.computer-files", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)dealloc {
    [_session invalidateAndCancel];
}

- (void)getEndpoint:(NSString*)endpoint
               query:(NSArray<NSURLQueryItem*>*)query
           byteLimit:(NSUInteger)byteLimit
          completion:(void (^)(NSData*, NSHTTPURLResponse*, NSError*))completion {
    if (_manager == nil) {
        _manager = [[HttpManager alloc] initWithHost:_host];
        _session = [_manager newComputerFilesSession];
    }
    NSURLRequest* request = [_manager newComputerFilesRequest:endpoint queryItems:query];
    if (request == nil) {
        // Rebuild the connection on retry using the host's current address and port.
        [_session invalidateAndCancel];
        _session = nil;
        _manager = nil;
        completion(nil, nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotConnectToHost userInfo:nil]);
        return;
    }

    NSUUID* requestID = [NSUUID UUID];
    _requestID = requestID;
    _task = [_session downloadTaskWithRequest:request completionHandler:^(NSURL* location, NSURLResponse* response, NSError* error) {
        // The temporary URL remains valid only until this callback returns.
        dispatch_sync(self->_queue, ^{
            if (self->_requestID != requestID) {
                return;
            }
            self->_requestID = nil;
            self->_task = nil;

            if (error) {
                [self->_session invalidateAndCancel];
                self->_session = nil;
                self->_manager = nil;
                completion(nil, nil, error);
                return;
            }
            NSHTTPURLResponse* http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse*)response : nil;
            if (http.statusCode != 200) {
                completion(nil, http, ComputerFilesErrorWithCode(http ? http.statusCode : ComputerFilesErrorInvalidResponse));
                return;
            }
            NSNumber* receivedSize = nil;
            if (![location getResourceValue:&receivedSize forKey:NSURLFileSizeKey error:nil] ||
                receivedSize == nil || receivedSize.unsignedLongLongValue > byteLimit) {
                completion(nil, http, ComputerFilesErrorWithCode(ComputerFilesErrorInvalidResponse));
                return;
            }
            NSData* data = [NSData dataWithContentsOfURL:location];
            if (data == nil) {
                completion(nil, http, ComputerFilesErrorWithCode(ComputerFilesErrorCannotStore));
                return;
            }
            completion(data, http, nil);
        });
    }];
    [_task resume];
}

- (void)getJSON:(NSString*)endpoint query:(NSArray<NSURLQueryItem*>*)query completion:(ComputerFilesJSONCompletion)completion {
    dispatch_async(_queue, ^{
        [self cancelOnQueue];
        [self getEndpoint:endpoint query:query byteLimit:ComputerFilesMaximumChunkSize completion:^(NSData* data, NSHTTPURLResponse* response, NSError* error) {
            id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            if (error == nil && ![json isKindOfClass:[NSDictionary class]]) {
                error = ComputerFilesErrorWithCode(legacyGameStreamStatus(data));
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(error ? nil : json, error);
            });
        }];
    });
}

- (void)loadDrives:(ComputerFilesJSONCompletion)completion {
    [self getJSON:@"" query:@[] completion:completion];
}

- (void)listRoot:(NSString*)root path:(NSString*)path offset:(NSNumber*)offset completion:(ComputerFilesJSONCompletion)completion {
    [self getJSON:@"/list" query:@[
        [NSURLQueryItem queryItemWithName:@"root" value:root],
        [NSURLQueryItem queryItemWithName:@"path" value:path],
        [NSURLQueryItem queryItemWithName:@"offset" value:offset.stringValue],
    ] completion:completion];
}

- (void)downloadRoot:(NSString*)root
                path:(NSString*)path
            fileName:(NSString*)fileName
                size:(uint64_t)size
             version:(NSString*)version
           chunkSize:(NSUInteger)chunkSize
            progress:(void (^)(double))progress
          completion:(ComputerFilesDownloadCompletion)completion {
    dispatch_async(_queue, ^{
        [self cancelOnQueue];

        if (!ComputerFilesIsValidEntryName(fileName)) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, ComputerFilesErrorWithCode(ComputerFilesErrorInvalidResponse));
            });
            return;
        }
        NSFileManager* fileManager = [NSFileManager defaultManager];
        NSURL* directory = [fileManager.temporaryDirectory URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
        NSURL* fileURL = [directory URLByAppendingPathComponent:fileName isDirectory:NO];
        BOOL createdDirectory = [fileManager createDirectoryAtURL:directory withIntermediateDirectories:NO attributes:nil error:nil];
        BOOL createdFile = createdDirectory && [fileManager createFileAtPath:fileURL.path contents:nil attributes:nil];
        NSFileHandle* handle = createdFile ? [NSFileHandle fileHandleForWritingToURL:fileURL error:nil] : nil;
        if (handle == nil) {
            if (createdDirectory) {
                [fileManager removeItemAtURL:directory error:nil];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, ComputerFilesErrorWithCode(ComputerFilesErrorCannotStore));
            });
            return;
        }

        self->_download = [[ComputerFileDownload alloc] init];
        self->_download.root = root;
        self->_download.path = path;
        self->_download.version = version;
        self->_download.size = size;
        self->_download.chunkSize = MIN(MAX(chunkSize, 1), ComputerFilesMaximumChunkSize);
        self->_download.fileURL = fileURL;
        self->_download.handle = handle;
        self->_download.progress = progress;
        self->_download.completion = completion;
        [self downloadNextChunk];
    });
}

- (void)downloadNextChunk {
    ComputerFileDownload* download = _download;
    NSUInteger expected = (NSUInteger)MIN(download.size - download.offset, download.chunkSize);
    // The server requires a positive length, including when checking an empty file.
    NSArray<NSURLQueryItem*>* query = @[
        [NSURLQueryItem queryItemWithName:@"root" value:download.root],
        [NSURLQueryItem queryItemWithName:@"path" value:download.path],
        [NSURLQueryItem queryItemWithName:@"offset" value:@(download.offset).stringValue],
        [NSURLQueryItem queryItemWithName:@"length" value:@(MAX(expected, 1)).stringValue],
        [NSURLQueryItem queryItemWithName:@"version" value:download.version],
    ];
    [self getEndpoint:@"/download" query:query byteLimit:expected completion:^(NSData* data, NSHTTPURLResponse* response, NSError* error) {
        if (error) {
            [self finishDownloadWithError:error];
            return;
        }
        NSString* version = [response valueForHTTPHeaderField:@"X-SideLantern-File-Version"];
        NSString* size = [response valueForHTTPHeaderField:@"X-SideLantern-File-Size"];
        if (![download.version isEqualToString:version] || ![@(download.size).stringValue isEqualToString:size]) {
            [self finishDownloadWithError:ComputerFilesErrorWithCode(409)];
            return;
        }
        if (data.length != expected) {
            [self finishDownloadWithError:ComputerFilesErrorWithCode(ComputerFilesErrorInvalidResponse)];
            return;
        }
        if (![download.handle writeData:data error:nil]) {
            [self finishDownloadWithError:ComputerFilesErrorWithCode(ComputerFilesErrorCannotStore)];
            return;
        }
        download.offset += data.length;
        double fraction = download.size ? (double)download.offset / download.size : 1.0;
        dispatch_async(dispatch_get_main_queue(), ^{
            download.progress(fraction);
        });
        if (download.offset == download.size) {
            [self finishDownloadWithError:nil];
        } else {
            [self downloadNextChunk];
        }
    }];
}

- (void)finishDownloadWithError:(NSError*)error {
    ComputerFileDownload* download = _download;
    _download = nil;
    if (![download.handle closeAndReturnError:nil] && error == nil) {
        error = ComputerFilesErrorWithCode(ComputerFilesErrorCannotStore);
    }
    if (error) {
        [ComputerFilesClient removeDownloadAtURL:download.fileURL];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        download.completion(error ? nil : download.fileURL, error);
    });
}

- (void)cancelOnQueue {
    _requestID = nil;
    [_task cancel];
    _task = nil;
    if (_download) {
        [_download.handle closeAndReturnError:nil];
        [ComputerFilesClient removeDownloadAtURL:_download.fileURL];
        _download = nil;
    }
}

- (void)cancel {
    dispatch_async(_queue, ^{
        [self cancelOnQueue];
    });
}

+ (void)removeDownloadAtURL:(NSURL*)fileURL {
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSURL* directory = fileURL.URLByDeletingLastPathComponent;
    NSString* parentPath = directory.URLByDeletingLastPathComponent.URLByStandardizingPath.path;
    if ([parentPath isEqualToString:fileManager.temporaryDirectory.URLByStandardizingPath.path] &&
        [[NSUUID alloc] initWithUUIDString:directory.lastPathComponent] != nil) {
        [fileManager removeItemAtURL:directory error:nil];
    }
}

@end
