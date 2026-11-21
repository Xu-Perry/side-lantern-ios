#import "ManualVideoSettings.h"

typedef NS_ENUM(NSUInteger, ManualVideoState) {
    ManualVideoUnavailable, ManualVideoLoading, ManualVideoReady, ManualVideoApplying, ManualVideoFailed,
};
typedef void (^ManualVideoTransport)(NSString *sessionIdentifier, ManualVideoSettings *settings, void (^completion)(ManualVideoResponse *response));
typedef void (^ManualVideoSchedule)(NSTimeInterval delay, void (^operation)(void));

@interface ManualVideoController : NSObject
@property (nonatomic, readonly) ManualVideoState state;
@property (nonatomic, readonly) BOOL available;
@property (nonatomic, readonly) ManualVideoResponse *response;
@property (nonatomic, readonly) ManualVideoFields appliedFields;
@property (nonatomic, readonly) NSString *statusText;
@property (nonatomic, copy) void (^stateChanged)(ManualVideoController *controller);
- (instancetype)initWithTransport:(ManualVideoTransport)transport schedule:(ManualVideoSchedule)schedule;
- (void)refresh;
// Discover the session without changing Moonlight's configured bandwidth budget.
- (void)refreshWithBitrateBudget:(NSInteger)bitrate audioChannels:(NSInteger)audioChannels;
- (void)requestSettings:(ManualVideoSettings *)settings fields:(ManualVideoFields)fields;
- (void)requestSettings:(ManualVideoSettings *)settings fields:(ManualVideoFields)fields bitrateBudget:(NSInteger)bitrateBudget;
- (void)cancel;
@end
