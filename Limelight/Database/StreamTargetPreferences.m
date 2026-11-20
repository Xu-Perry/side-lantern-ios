#import "StreamTargetPreferences.h"

static NSString * const StreamTargetPreferenceKey = @"SideLantern.StreamTarget";

@implementation StreamTargetPreferences {
    NSUserDefaults *_userDefaults;
}

- (instancetype)init {
    return [self initWithUserDefaults:NSUserDefaults.standardUserDefaults];
}

- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults {
    self = [super init];
    if (self) {
        _userDefaults = userDefaults;
        id savedTarget = [userDefaults objectForKey:StreamTargetPreferenceKey];
        if ([savedTarget isEqual:@"secondary_display"]) {
            _selectedTarget = StreamTargetSecondaryDisplay;
        }
        else if ([savedTarget isEqual:@"wireless_display"]) {
            _selectedTarget = StreamTargetWirelessDisplay;
        }
        else {
            _selectedTarget = StreamTargetPrimaryDisplay;
        }
    }
    return self;
}

- (void)setSelectedTarget:(StreamTarget)selectedTarget {
    _selectedTarget = selectedTarget >= StreamTargetPrimaryDisplay && selectedTarget <= StreamTargetWirelessDisplay
        ? selectedTarget : StreamTargetPrimaryDisplay;
}

- (void)save {
    NSArray<NSString *> *values = @[@"primary_display", @"secondary_display", @"wireless_display"];
    [_userDefaults setObject:values[self.selectedTarget] forKey:StreamTargetPreferenceKey];
}

@end
