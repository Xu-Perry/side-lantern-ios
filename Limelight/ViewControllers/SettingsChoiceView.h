#import <UIKit/UIKit.h>

// Keeps the existing segmented control as the value and event source.
@interface SettingsChoiceView : UIControl
@property (nonatomic, readonly) UISegmentedControl *control;

- (instancetype)initWithControl:(UISegmentedControl *)control label:(NSString *)label identifier:(NSString *)identifier;
- (void)refresh;

@end
