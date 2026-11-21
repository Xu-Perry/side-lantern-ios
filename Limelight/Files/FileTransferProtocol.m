#import "FileTransferProtocol.h"
#import <CoreFoundation/CoreFoundation.h>
#include <math.h>

NSString *const FileTransferErrorDomain = @"SideLantern.FileTransfer";

NSNumber *FileTransferUnsigned(id value, uint64_t maximum) {
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return nil;
    double number = [value doubleValue];
    if (!isfinite(number) || number < 0 || floor(number) != number || number > maximum || [value unsignedLongLongValue] > maximum) return nil;
    return value;
}
BOOL FileTransferValidName(NSString *name) {
    return [name isKindOfClass:NSString.class] && name.length > 0 && name.length <= 255 &&
        ![name isEqualToString:@"."] && ![name isEqualToString:@".."] &&
        [name rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/\\\0"]].location == NSNotFound;
}
NSError *FileTransferError(NSString *code, NSInteger status) {
    return [NSError errorWithDomain:FileTransferErrorDomain code:status userInfo:@{NSLocalizedDescriptionKey:code, @"reason":code}];
}
static NSDictionary *Document(NSData *data) {
    if (data.length == 0 || data.length > 1024 * 1024) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [json isKindOfClass:NSDictionary.class] ? json : nil;
}
static BOOL FileTransferBool(id value) { return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID(); }

NSError *FileTransferResponseError(NSData *data, NSHTTPURLResponse *response, NSError *error) {
    if (error) return error;
    if (!response) return FileTransferError(@"invalid_response", 0);
    if (response.statusCode >= 200 && response.statusCode < 300) return nil;
    id reason = Document(data)[@"error"];
    if (![reason isKindOfClass:NSString.class] || [reason length] == 0) {
        reason = response.statusCode == 401 ? @"device_not_paired" : response.statusCode == 403 ? @"device_forbidden" :
            response.statusCode == 404 ? @"not_supported" : @"request_failed";
    }
    return FileTransferError(reason, response.statusCode);
}

NSURLRequest *FileTransferRequest(NSURL *baseURL, NSString *method, NSString *route, NSDictionary<NSString *,NSString *> *query, NSData *body, NSString *contentType) {
    if (![baseURL.scheme isEqualToString:@"https"] || baseURL.host.length == 0 ||
        ![@[@"", @"/list", @"/download", @"/uploads", @"/uploads/complete"] containsObject:route] ||
        ![@[@"GET", @"POST", @"PUT", @"DELETE"] containsObject:method]) return nil;
    NSURLComponents *url = [NSURLComponents componentsWithURL:baseURL resolvingAgainstBaseURL:NO];
    url.path = [@"/sidelantern/v1/files" stringByAppendingString:route];
    url.query = nil; url.fragment = nil; url.user = nil; url.password = nil;
    NSCharacterSet *unreserved = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSString *key in [query.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        if (![query[key] isKindOfClass:NSString.class]) return nil;
        [pairs addObject:[NSString stringWithFormat:@"%@=%@", [key stringByAddingPercentEncodingWithAllowedCharacters:unreserved],
            [query[key] stringByAddingPercentEncodingWithAllowedCharacters:unreserved]]];
    }
    if (pairs.count) url.percentEncodedQuery = [pairs componentsJoinedByString:@"&"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url.URL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15];
    request.HTTPMethod = method; request.HTTPBody = body;
    if (contentType) [request setValue:contentType forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"no-store" forHTTPHeaderField:@"Cache-Control"];
    return request;
}

@implementation FileTransferRoot
- (instancetype)initWithIdentifier:(NSString *)identifier label:(NSString *)label {
    if ((self = [super init])) { _identifier = identifier.copy; _label = label.copy; } return self;
}
@end

@implementation FileTransferCapabilities
+ (instancetype)parse:(NSData *)data {
    NSDictionary *json = Document(data);
    NSNumber *version = FileTransferUnsigned(json[@"version"], 1);
    NSNumber *uploadChunk = FileTransferUnsigned(json[@"upload_chunk_bytes"], 48 * 1024);
    NSNumber *downloadChunk = FileTransferUnsigned(json[@"download_chunk_bytes"], 1024 * 1024);
    NSNumber *maxUpload = FileTransferUnsigned(json[@"max_upload_bytes"], 8ULL * 1024 * 1024 * 1024);
    if (version.integerValue != 1 || !FileTransferBool(json[@"enabled"]) || !FileTransferBool(json[@"upload"]) ||
        uploadChunk.unsignedIntegerValue == 0 || downloadChunk.unsignedIntegerValue == 0 || !maxUpload ||
        !FileTransferUnsigned(json[@"upload_idle_seconds"], UINT32_MAX) || ![json[@"roots"] isKindOfClass:NSArray.class]) return nil;
    NSMutableArray *roots = [NSMutableArray array]; NSMutableSet *identifiers = [NSMutableSet set];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"];
    for (id root in json[@"roots"]) {
        if (![root isKindOfClass:NSDictionary.class]) return nil;
        NSString *identifier = root[@"id"], *label = root[@"label"];
        if (![identifier isKindOfClass:NSString.class] || identifier.length == 0 || identifier.length > 64 ||
            [identifier rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound || [identifiers containsObject:identifier] ||
            ![label isKindOfClass:NSString.class] || label.length == 0 || label.length > 256) return nil;
        [identifiers addObject:identifier]; [roots addObject:[[FileTransferRoot alloc] initWithIdentifier:identifier label:label]];
    }
    FileTransferCapabilities *result = [[self alloc] init];
    result->_enabled = [json[@"enabled"] boolValue]; result->_upload = [json[@"upload"] boolValue]; result->_roots = roots.copy;
    result->_uploadChunkBytes = uploadChunk.unsignedIntegerValue; result->_downloadChunkBytes = downloadChunk.unsignedIntegerValue;
    result->_maxUploadBytes = maxUpload.unsignedLongLongValue;
    return result;
}
@end

@implementation FileTransferEntry
- (instancetype)initWithDocument:(NSDictionary *)json {
    if ((self = [super init])) {
        _name = [json[@"name"] copy]; _directory = [json[@"kind"] isEqualToString:@"directory"];
        _size = [json[@"size"] unsignedLongLongValue]; _version = [json[@"version"] copy];
        _modified = [NSDate dateWithTimeIntervalSince1970:[json[@"modified_unix_ms"] doubleValue] / 1000];
    } return self;
}
@end

@implementation FileTransferListing
+ (instancetype)parse:(NSData *)data {
    NSDictionary *json = Document(data);
    if (![json[@"entries"] isKindOfClass:NSArray.class] || !FileTransferBool(json[@"truncated"]) ||
        (json[@"next_offset"] != NSNull.null && !FileTransferUnsigned(json[@"next_offset"], 100000))) return nil;
    NSMutableArray *entries = [NSMutableArray array]; NSMutableSet *names = [NSMutableSet set];
    for (id entry in json[@"entries"]) {
        if (![entry isKindOfClass:NSDictionary.class] || !FileTransferValidName(entry[@"name"]) || [names containsObject:entry[@"name"]] ||
            ![@[@"file", @"directory"] containsObject:entry[@"kind"]] || !FileTransferUnsigned(entry[@"size"], INT64_MAX) ||
            !FileTransferUnsigned(entry[@"modified_unix_ms"], INT64_MAX) || ![entry[@"version"] isKindOfClass:NSString.class]) return nil;
        [names addObject:entry[@"name"]]; [entries addObject:[[FileTransferEntry alloc] initWithDocument:entry]];
    }
    FileTransferListing *result = [[self alloc] init]; result->_entries = entries.copy;
    result->_nextOffset = json[@"next_offset"] == NSNull.null ? nil : json[@"next_offset"]; result->_truncated = [json[@"truncated"] boolValue];
    return result;
}
@end

@implementation FileTransferUploadStatus
+ (instancetype)parse:(NSData *)data {
    NSDictionary *json = Document(data);
    NSString *identifier = json[@"id"];
    NSNumber *size = FileTransferUnsigned(json[@"size"], 8ULL * 1024 * 1024 * 1024), *offset = FileTransferUnsigned(json[@"offset"], 8ULL * 1024 * 1024 * 1024);
    if (![identifier isKindOfClass:NSString.class] || identifier.length == 0 || identifier.length > 128 || !FileTransferValidName(json[@"name"]) ||
        !size || !offset || offset.unsignedLongLongValue > size.unsignedLongLongValue || !FileTransferBool(json[@"complete"]) ||
        ([json[@"complete"] boolValue] && offset.unsignedLongLongValue != size.unsignedLongLongValue)) return nil;
    FileTransferUploadStatus *result = [[self alloc] init]; result->_identifier = identifier.copy; result->_name = [json[@"name"] copy];
    result->_size = size.unsignedLongLongValue; result->_offset = offset.unsignedLongLongValue; result->_complete = [json[@"complete"] boolValue]; return result;
}
@end
