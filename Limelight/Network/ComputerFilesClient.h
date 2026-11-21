#import <Foundation/Foundation.h>

@class TemporaryHost;

FOUNDATION_EXPORT NSString* const ComputerFilesErrorDomain;
FOUNDATION_EXPORT BOOL ComputerFilesIsValidEntryName(id value);

typedef NS_ENUM(NSInteger, ComputerFilesError) {
    ComputerFilesErrorInvalidResponse = 1,
    ComputerFilesErrorCannotStore,
};

typedef void (^ComputerFilesJSONCompletion)(NSDictionary* response, NSError* error);
typedef void (^ComputerFilesDownloadCompletion)(NSURL* fileURL, NSError* error);

@interface ComputerFilesClient : NSObject

- (instancetype)initWithHost:(TemporaryHost*)host;

// Each client runs one operation at a time. Callbacks are delivered on the main queue.
- (void)loadDrives:(ComputerFilesJSONCompletion)completion;
- (void)listRoot:(NSString*)root path:(NSString*)path offset:(NSNumber*)offset completion:(ComputerFilesJSONCompletion)completion;
- (void)downloadRoot:(NSString*)root
                path:(NSString*)path
            fileName:(NSString*)fileName
                size:(uint64_t)size
             version:(NSString*)version
           chunkSize:(NSUInteger)chunkSize
            progress:(void (^)(double fraction))progress
          completion:(ComputerFilesDownloadCompletion)completion;
- (void)cancel;

// The caller owns a successful download until it finishes exporting the file.
+ (void)removeDownloadAtURL:(NSURL*)fileURL;

@end
