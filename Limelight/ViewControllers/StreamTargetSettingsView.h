#import <UIKit/UIKit.h>
#import "StreamTargetPreferences.h"
@class StreamModesResponse;

@interface StreamTargetSettingsView : UIControl

@property (nonatomic) StreamTarget selectedTarget;
- (void)updateWithModes:(StreamModesResponse *)modes statusText:(NSString *)statusText;

@end
