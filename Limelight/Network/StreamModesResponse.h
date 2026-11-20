#import "HttpResponse.h"
#import "StreamTargetPreferences.h"

NSString *StreamModeIdentifierForTarget(StreamTarget target);
NSString *StreamModeFailureMessage(NSString *reason);

@interface StreamModesResponse : HttpResponse <NSXMLParserDelegate>

@property (nonatomic, readonly) BOOL supportsDisplayModes;
@property (nonatomic, readonly) BOOL supportsManualVideo;
@property (nonatomic, readonly) BOOL isLegacyHost;

- (BOOL)isModeAvailable:(NSString *)mode;
- (NSString *)reasonForMode:(NSString *)mode;

@end
