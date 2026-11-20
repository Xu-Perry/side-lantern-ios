#import "StreamTargetSettingsView.h"
#import "StreamModesResponse.h"

static NSString *TargetText(NSString *key) {
    return NSLocalizedStringFromTable(key, @"StreamTarget", nil);
}

@interface StreamTargetOptionControl : UIControl
- (instancetype)initWithTitle:(NSString *)title symbol:(NSString *)symbol;
- (void)showUnavailableReason:(NSString *)reason;
@end

@implementation StreamTargetOptionControl {
    UIImageView *_icon;
    UIImageView *_selectionIndicator;
}

- (instancetype)initWithTitle:(NSString *)title symbol:(NSString *)symbol {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.layer.cornerRadius = 10;
        self.layer.borderWidth = 1;
        self.isAccessibilityElement = YES;
        self.accessibilityLabel = title;

        _icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
        _icon.contentMode = UIViewContentModeScaleAspectFit;
        _selectionIndicator = [[UIImageView alloc] init];
        _selectionIndicator.contentMode = UIViewContentModeScaleAspectFit;

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.text = title;
        titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        titleLabel.textColor = UIColor.whiteColor;
        titleLabel.numberOfLines = 0;
        titleLabel.adjustsFontForContentSizeCategory = YES;

        UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:@[_icon, titleLabel, _selectionIndicator]];
        content.translatesAutoresizingMaskIntoConstraints = NO;
        content.alignment = UIStackViewAlignmentCenter;
        content.spacing = 12;
        content.userInteractionEnabled = NO;
        [self addSubview:content];

        [NSLayoutConstraint activateConstraints:@[
            [content.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
            [content.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
            [content.topAnchor constraintEqualToAnchor:self.topAnchor constant:14],
            [content.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-14],
            [_icon.widthAnchor constraintEqualToConstant:24],
            [_icon.heightAnchor constraintEqualToConstant:24],
            [_selectionIndicator.widthAnchor constraintEqualToConstant:22],
            [_selectionIndicator.heightAnchor constraintEqualToConstant:22],
            [self.heightAnchor constraintGreaterThanOrEqualToConstant:56],
        ]];
        [self updateAppearance];
    }
    return self;
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    [self updateAppearance];
}

- (BOOL)accessibilityActivate {
    [self sendActionsForControlEvents:UIControlEventTouchUpInside];
    return YES;
}

- (void)showUnavailableReason:(NSString *)reason {
    self.accessibilityValue = reason.length > 0 ? StreamModeFailureMessage(reason) : nil;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [self updateAppearance];
}

- (void)updateAppearance {
    UIColor *accent = [UIColor colorWithRed:0.672 green:0.617 blue:0.999 alpha:1];
    self.backgroundColor = self.selected ? [accent colorWithAlphaComponent:self.highlighted ? 0.26 : 0.14]
        : [UIColor colorWithWhite:1 alpha:self.highlighted ? 0.13 : 0.05];
    self.layer.borderColor = (self.selected ? accent : [UIColor colorWithWhite:1 alpha:0.12]).CGColor;
    _icon.tintColor = self.selected ? accent : [UIColor colorWithWhite:0.78 alpha:1];
    _selectionIndicator.tintColor = _icon.tintColor;
    _selectionIndicator.image = [UIImage systemImageNamed:self.selected ? @"checkmark.circle.fill" : @"circle"];
    self.accessibilityTraits = UIAccessibilityTraitButton | (self.selected ? UIAccessibilityTraitSelected : 0);
}

@end

@implementation StreamTargetSettingsView {
    NSArray<StreamTargetOptionControl *> *_options;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        UILabel *heading = [[UILabel alloc] init];
        heading.text = TargetText(@"target.title");
        heading.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        heading.textColor = UIColor.whiteColor;
        heading.numberOfLines = 0;
        heading.adjustsFontForContentSizeCategory = YES;
        heading.accessibilityTraits = UIAccessibilityTraitHeader;

        _options = @[
            [[StreamTargetOptionControl alloc] initWithTitle:TargetText(@"target.primary.title")
                symbol:@"display"],
            [[StreamTargetOptionControl alloc] initWithTitle:TargetText(@"target.secondary.title")
                symbol:@"display.2"],
            [[StreamTargetOptionControl alloc] initWithTitle:TargetText(@"target.wireless.title")
                symbol:@"ipad.and.iphone"],
        ];
        for (NSUInteger index = 0; index < _options.count; index++) {
            _options[index].tag = index;
            _options[index].accessibilityIdentifier = [NSString stringWithFormat:@"stream-target-%lu", (unsigned long)index];
            [_options[index] addTarget:self action:@selector(targetSelected:) forControlEvents:UIControlEventTouchUpInside];
        }

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[heading, _options[0], _options[1], _options[2]]];
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 10;
        [self addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
        self.selectedTarget = StreamTargetPrimaryDisplay;
    }
    return self;
}

- (void)setSelectedTarget:(StreamTarget)selectedTarget {
    _selectedTarget = selectedTarget >= StreamTargetPrimaryDisplay && selectedTarget <= StreamTargetWirelessDisplay
        ? selectedTarget : StreamTargetPrimaryDisplay;
    for (StreamTargetOptionControl *option in _options) {
        option.selected = option.tag == _selectedTarget;
    }
}

- (void)updateWithModes:(StreamModesResponse *)modes statusText:(NSString *)statusText {
    for (StreamTargetOptionControl *option in _options) {
        NSString *mode = StreamModeIdentifierForTarget((StreamTarget)option.tag);
        [option showUnavailableReason:modes.supportsDisplayModes && ![modes isModeAvailable:mode] ? [modes reasonForMode:mode] : nil];
        option.accessibilityHint = statusText;
    }
    [self setNeedsLayout];
}

- (void)targetSelected:(StreamTargetOptionControl *)sender {
    self.selectedTarget = (StreamTarget)sender.tag;
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

- (CGSize)sizeThatFits:(CGSize)size {
    return [self systemLayoutSizeFittingSize:CGSizeMake(size.width, UILayoutFittingCompressedSize.height)
        withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
}

@end
