#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, StreamTarget) {
    StreamTargetPrimaryDisplay,
    StreamTargetSecondaryDisplay,
    StreamTargetWirelessDisplay,
};

// These are local preferences, independent of the host's API representation.
@interface StreamTargetPreferences : NSObject

@property (nonatomic) StreamTarget selectedTarget;

- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults;
- (void)save;

@end
