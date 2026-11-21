#import "HttpResponse.h"

typedef NS_OPTIONS(NSUInteger, ManualVideoFields) {
    ManualVideoResolution = 1 << 0,
    ManualVideoFrameRate = 1 << 1,
    ManualVideoBitrate = 1 << 2,
    ManualVideoAll = ManualVideoResolution | ManualVideoFrameRate | ManualVideoBitrate,
};

@interface ManualVideoSettings : NSObject <NSCopying>
@property (nonatomic, readonly) NSInteger width;
@property (nonatomic, readonly) NSInteger height;
@property (nonatomic, readonly) NSInteger frameRate;
@property (nonatomic, readonly) NSInteger bitrate;
@property (nonatomic, readonly) BOOL valid;
- (instancetype)initWithWidth:(NSInteger)width height:(NSInteger)height frameRate:(NSInteger)frameRate bitrate:(NSInteger)bitrate;
- (ManualVideoSettings *)replacingFields:(ManualVideoFields)fields withSettings:(ManualVideoSettings *)settings;
@end

// Converts Moonlight's configured bandwidth budget to the encoder-only API value.
@interface ManualVideoBitrateBudget : NSObject
- (instancetype)initWithBudget:(NSInteger)budget encoderBitrate:(NSInteger)encoderBitrate audioChannels:(NSInteger)audioChannels;
- (NSInteger)encoderBitrateForBudget:(NSInteger)budget;
@end

@interface ManualVideoResponse : HttpResponse <NSXMLParserDelegate>
@property (nonatomic, readonly) BOOL validSession;
@property (nonatomic, readonly) NSString *sessionIdentifier;
@property (nonatomic, readonly) NSString *state;
@property (nonatomic, readonly) NSString *reason;
@property (nonatomic, readonly) ManualVideoSettings *settings;
@end

NSURLRequest *ManualVideoRequest(NSURL *baseURL, NSString *sessionIdentifier, ManualVideoSettings *settings);
NSString *ManualVideoErrorText(NSString *reason);
