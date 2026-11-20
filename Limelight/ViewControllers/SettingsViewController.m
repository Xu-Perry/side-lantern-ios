//
//  SettingsViewController.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/27/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "SettingsViewController.h"
#import "TemporarySettings.h"
#import "DataManager.h"
#import "StreamTargetSettingsView.h"
#import "SWRevealViewController.h"
#import "StreamModesResponse.h"
#import "HttpManager.h"
#import "SettingsChoiceView.h"

#import <VideoToolbox/VideoToolbox.h>
#import <AVFoundation/AVFoundation.h>

@implementation SettingsViewController {
    NSInteger _bitrate;
    NSInteger _lastSelectedResolutionIndex;
    StreamTargetPreferences *_targetPreferences;
    StreamTargetSettingsView *_targetSettingsView;
    NSMapTable<UIView *, NSNumber *> *_originalSettingsY;
    TemporaryHost *_targetHost;
    NSUInteger _targetQueryGeneration;
    NSMutableArray<SettingsChoiceView *> *_settingsChoices;
    NSLayoutConstraint *_settingsLeading;
    NSLayoutConstraint *_settingsTrailing;
    NSLayoutConstraint *_settingsWidth;
    NSLayoutConstraint *_settingsTop;
    NSLayoutConstraint *_settingsBottom;
    BOOL _editingCustomResolution;
    BOOL _manualVideoAvailable;
    BOOL _manualVideoUpdating;
    ManualVideoSettings *_manualVideoSettings;
    NSString *_manualVideoMessage;
    UILabel *_manualVideoNotice;
    NSMutableDictionary<NSString *, UILabel *> *_effectLabels;
    UIStackView *_settingRows;
    NSMutableArray<UIStackView *> *_allSettingRows;
    NSMapTable<UIStackView *, UIControl *> *_rowControls;
    NSArray<UIStackView *> *_visibleSettingRows;
}

@dynamic overrideUserInterfaceStyle;

static const int bitrateTable[] = {
    500,
    1000,
    1500,
    2000,
    2500,
    3000,
    4000,
    5000,
    6000,
    7000,
    8000,
    9000,
    10000,
    12000,
    15000,
    18000,
    20000,
    30000,
    40000,
    50000,
    60000,
    70000,
    80000,
    100000,
    120000,
    150000,
};

const int RESOLUTION_TABLE_SIZE = 7;
const int RESOLUTION_TABLE_CUSTOM_INDEX = RESOLUTION_TABLE_SIZE - 1;
CGSize resolutionTable[RESOLUTION_TABLE_SIZE];

-(int)getSliderValueForBitrate:(NSInteger)bitrate {
    int i;
    
    for (i = 0; i < (sizeof(bitrateTable) / sizeof(*bitrateTable)); i++) {
        if (bitrate <= bitrateTable[i]) {
            return i;
        }
    }
    
    // Return the last entry in the table
    return i - 1;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIEdgeInsets safe = self.view.safeAreaInsets;
    if (self.usesFullBounds) safe = UIEdgeInsetsZero;
    CGFloat left = 16 + safe.left;
    CGFloat right = 16 + safe.right;
    _settingsLeading.constant = left;
    _settingsTrailing.constant = -right;
    _settingsWidth.constant = -(left + right);
    _settingsTop.constant = 20 + safe.top;
    _settingsBottom.constant = -(20 + safe.bottom);
    self.scrollView.scrollIndicatorInsets = UIEdgeInsetsMake(safe.top, 0, safe.bottom, 0);
    [self refreshSettingsChoices];
}

- (void)setUsesFullBounds:(BOOL)usesFullBounds {
    if (_usesFullBounds == usesFullBounds) return;
    _usesFullBounds = usesFullBounds;
    [self.viewIfLoaded setNeedsLayout];
}

- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    [self.view setNeedsLayout];
}

BOOL isCustomResolution(CGSize res) {
    if (res.width == 0 && res.height == 0) {
        return NO;
    }
    
    for (int i = 0; i < RESOLUTION_TABLE_CUSTOM_INDEX; i++) {
        if (res.width == resolutionTable[i].width && res.height == resolutionTable[i].height) {
            return NO;
        }
    }
    
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = NSLocalizedStringFromTable(@"settings.title", @"StreamTarget", nil);
    if (!self.streaming) self.edgesForExtendedLayout = UIRectEdgeNone;

    // Always run settings in dark mode because we want the light fonts
    if (@available(iOS 13.0, tvOS 13.0, *)) {
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    }
    
    DataManager* dataMan = [[DataManager alloc] init];
    TemporarySettings* currentSettings = [dataMan getSettings];

    _originalSettingsY = [NSMapTable strongToStrongObjectsMapTable];
    for (UIView *view in self.scrollView.subviews) {
        if ([view isKindOfClass:[UILabel class]] || [view isKindOfClass:[UISegmentedControl class]] ||
            [view isKindOfClass:[UISlider class]] || view == self.resolutionDisplayView) {
            [_originalSettingsY setObject:@(view.frame.origin.y) forKey:view];
        }
    }
    if (!self.streaming) {
        _targetPreferences = [[StreamTargetPreferences alloc] init];
        _targetSettingsView = [[StreamTargetSettingsView alloc] initWithFrame:CGRectZero];
        _targetSettingsView.selectedTarget = _targetPreferences.selectedTarget;
        [_targetSettingsView addTarget:self action:@selector(streamTargetChanged) forControlEvents:UIControlEventValueChanged];
        [self.scrollView addSubview:_targetSettingsView];
    }
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(streamTargetTextSizeChanged:)
        name:UIContentSizeCategoryDidChangeNotification object:nil];
    
    // Ensure we pick a bitrate that falls exactly onto a slider notch
    _bitrate = bitrateTable[[self getSliderValueForBitrate:[currentSettings.bitrate intValue]]];

    // Get the size of the screen with and without safe area insets
    UIWindow *window = self.view.window ?: self.parentViewController.view.window ?:
        ((AppDelegate *)UIApplication.sharedApplication.delegate).window;
    CGFloat screenScale = window.screen.scale;
    CGFloat safeAreaWidth = (window.frame.size.width - window.safeAreaInsets.left - window.safeAreaInsets.right) * screenScale;
    CGFloat fullScreenWidth = window.frame.size.width * screenScale;
    CGFloat fullScreenHeight = window.frame.size.height * screenScale;
    
    self.resolutionDisplayView.layer.cornerRadius = 10;
    self.resolutionDisplayView.clipsToBounds = YES;
    UITapGestureRecognizer *resolutionDisplayViewTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(resolutionDisplayViewTapped:)];
    [self.resolutionDisplayView addGestureRecognizer:resolutionDisplayViewTap];
    
    resolutionTable[0] = CGSizeMake(640, 360);
    resolutionTable[1] = CGSizeMake(1280, 720);
    resolutionTable[2] = CGSizeMake(1920, 1080);
    resolutionTable[3] = CGSizeMake(3840, 2160);
    resolutionTable[4] = CGSizeMake(safeAreaWidth, fullScreenHeight);
    resolutionTable[5] = CGSizeMake(fullScreenWidth, fullScreenHeight);
    resolutionTable[6] = CGSizeMake([currentSettings.width integerValue], [currentSettings.height integerValue]); // custom initial value
    
    // Don't populate the custom entry unless we have a custom resolution
    if (!isCustomResolution(resolutionTable[6])) {
        resolutionTable[6] = CGSizeMake(0, 0);
    }
    
    NSInteger framerate;
    switch ([currentSettings.framerate integerValue]) {
        case 30:
            framerate = 0;
            break;
        default:
        case 60:
            framerate = 1;
            break;
        case 120:
            framerate = 2;
            break;
    }

    NSInteger resolution = 1;
    for (int i = 0; i < RESOLUTION_TABLE_SIZE; i++) {
        if ((int) resolutionTable[i].height == [currentSettings.height intValue]
            && (int) resolutionTable[i].width == [currentSettings.width intValue]) {
            resolution = i;
            break;
        }
    }

    // Disable codec selector segments for unsupported codecs
#if defined(__IPHONE_16_0) || defined(__TVOS_16_0)
    if (!VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1))
#endif
    {
        [self.codecSelector removeSegmentAtIndex:2 animated:NO];
    }
    if (!VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)) {
        [self.codecSelector removeSegmentAtIndex:1 animated:NO];

        // Only enable the 4K option for "recent" devices. We'll judge that by whether
        // they support HEVC decoding (A9 or later).
        [self.resolutionSelector setEnabled:NO forSegmentAtIndex:3];
    }
    switch (currentSettings.preferredCodec) {
        case CODEC_PREF_AUTO:
            [self.codecSelector setSelectedSegmentIndex:self.codecSelector.numberOfSegments - 1];
            break;
            
        case CODEC_PREF_AV1:
            [self.codecSelector setSelectedSegmentIndex:2];
            break;
            
        case CODEC_PREF_HEVC:
            [self.codecSelector setSelectedSegmentIndex:1];
            break;
            
        case CODEC_PREF_H264:
            [self.codecSelector setSelectedSegmentIndex:0];
            break;
    }
    
    if (!VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC) || !(AVPlayer.availableHDRModes & AVPlayerHDRModeHDR10)) {
        [self.hdrSelector removeAllSegments];
        [self.hdrSelector insertSegmentWithTitle:@"Unsupported on this device" atIndex:0 animated:NO];
        [self.hdrSelector setEnabled:NO];
    }
    else {
        [self.hdrSelector setSelectedSegmentIndex:currentSettings.enableHdr ? 1 : 0];
    }
    
    [self.touchModeSelector setSelectedSegmentIndex:currentSettings.absoluteTouchMode ? 1 : 0];
    [self.touchModeSelector addTarget:self action:@selector(touchModeChanged) forControlEvents:UIControlEventValueChanged];
    [self.statsOverlaySelector setSelectedSegmentIndex:currentSettings.statsOverlay ? 1 : 0];
    [self.btMouseSelector setSelectedSegmentIndex:currentSettings.btMouseSupport ? 1 : 0];
    [self.optimizeSettingsSelector setSelectedSegmentIndex:currentSettings.optimizeGames ? 1 : 0];
    [self.framePacingSelector setSelectedSegmentIndex:currentSettings.useFramePacing ? 1 : 0];
    [self.multiControllerSelector setSelectedSegmentIndex:currentSettings.multiController ? 1 : 0];
    [self.swapABXYButtonsSelector setSelectedSegmentIndex:currentSettings.swapABXYButtons ? 1 : 0];
    [self.audioOnPCSelector setSelectedSegmentIndex:currentSettings.playAudioOnPC ? 1 : 0];
    NSInteger onscreenControls = [currentSettings.onscreenControls integerValue];
    _lastSelectedResolutionIndex = resolution;
    [self.resolutionSelector setSelectedSegmentIndex:resolution];
    [self.resolutionSelector addTarget:self action:@selector(newResolutionChosen) forControlEvents:UIControlEventValueChanged];
    [self.framerateSelector setSelectedSegmentIndex:MIN(framerate, self.framerateSelector.numberOfSegments - 1)];
    [self.framerateSelector addTarget:self action:@selector(updateBitrate) forControlEvents:UIControlEventValueChanged];
    [self.onscreenControlSelector setSelectedSegmentIndex:onscreenControls];
    [self.onscreenControlSelector setEnabled:self.streaming ? self.onScreenControlsAvailable : !currentSettings.absoluteTouchMode];
    [self.bitrateSlider setMinimumValue:0];
    [self.bitrateSlider setMaximumValue:(sizeof(bitrateTable) / sizeof(*bitrateTable)) - 1];
    [self.bitrateSlider setValue:[self getSliderValueForBitrate:_bitrate] animated:YES];
    [self.bitrateSlider addTarget:self action:@selector(bitrateSliderMoved) forControlEvents:UIControlEventValueChanged];
    [self.bitrateSlider addTarget:self action:@selector(settingValueChanged:) forControlEvents:UIControlEventValueChanged];
    [self.bitrateSlider addTarget:self action:@selector(settingValueChanged:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [self updateBitrateText];
    [self updateResolutionDisplayViewText];
    [self buildSettingsLayout];
    if (_manualVideoSettings && !_manualVideoUpdating) [self applyManualVideoControls];
}

- (void)buildSettingsLayout {
    self.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.alwaysBounceHorizontal = NO;
    self.scrollView.directionalLockEnabled = YES;
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    NSArray<UIView *> *legacyViews = [[_originalSettingsY.keyEnumerator allObjects] sortedArrayUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        return [[self->_originalSettingsY objectForKey:a] compare:[self->_originalSettingsY objectForKey:b]];
    }];
    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    _settingsChoices = [[NSMutableArray alloc] init];
    _effectLabels = [[NSMutableDictionary alloc] init];

    UILabel *title = [[UILabel alloc] init];
    title.text = NSLocalizedStringFromTable(@"settings.title", @"StreamTarget", nil);
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
    title.adjustsFontForContentSizeCategory = YES;
    title.textColor = UIColor.labelColor;
    title.accessibilityTraits = UIAccessibilityTraitHeader;
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    close.accessibilityLabel = NSLocalizedStringFromTable(@"settings.close", @"StreamTarget", nil);
    close.accessibilityIdentifier = @"settings-close";
    [close addTarget:self action:@selector(closeSettings) forControlEvents:UIControlEventTouchUpInside];
    [close.widthAnchor constraintEqualToConstant:44].active = YES;
    [close.heightAnchor constraintEqualToConstant:44].active = YES;
    if (!self.streaming && self.navigationController == nil) {
        UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:self.closeHandler ? @[title] : @[title, close]];
        header.alignment = UIStackViewAlignmentCenter;
        [stack addArrangedSubview:header];
    }
    if (!self.streaming) {
        UILabel *notice = [[UILabel alloc] init];
        notice.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        notice.adjustsFontForContentSizeCategory = YES;
        notice.numberOfLines = 0;
        notice.textColor = UIColor.secondaryLabelColor;
        notice.accessibilityIdentifier = @"settings-effect-notice";
        notice.text = NSLocalizedStringFromTable(@"settings.before_stream_notice", @"StreamTarget", nil);
        [stack addArrangedSubview:notice];
    }
    if (self.streaming) {
        _manualVideoNotice = [[UILabel alloc] init];
        _manualVideoNotice.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        _manualVideoNotice.adjustsFontForContentSizeCategory = YES;
        _manualVideoNotice.numberOfLines = 0;
        _manualVideoNotice.textColor = UIColor.secondaryLabelColor;
        _manualVideoNotice.accessibilityIdentifier = @"manual-video-status";
        _manualVideoNotice.text = _manualVideoMessage;
        _manualVideoNotice.hidden = _manualVideoMessage.length == 0;
        [stack addArrangedSubview:_manualVideoNotice];
    }
    if (!self.streaming) {
        [_targetSettingsView removeFromSuperview];
        _targetSettingsView.translatesAutoresizingMaskIntoConstraints = NO;
        [stack addArrangedSubview:_targetSettingsView];
        [stack setCustomSpacing:24 afterView:_targetSettingsView];
    }
    _settingRows = [[UIStackView alloc] init];
    _settingRows.axis = UILayoutConstraintAxisVertical;
    _settingRows.spacing = 20;
    [stack addArrangedSubview:_settingRows];
    _allSettingRows = [[NSMutableArray alloc] init];
    _rowControls = [NSMapTable strongToStrongObjectsMapTable];

    NSDictionary<NSString *, UIControl *> *controls = @{
        @"setting-resolution":self.resolutionSelector, @"setting-framerate":self.framerateSelector,
        @"setting-touch":self.touchModeSelector, @"setting-controls":self.onscreenControlSelector,
        @"setting-optimize":self.optimizeSettingsSelector, @"setting-controllers":self.multiControllerSelector,
        @"setting-swap":self.swapABXYButtonsSelector, @"setting-audio":self.audioOnPCSelector,
        @"setting-codec":self.codecSelector, @"setting-hdr":self.hdrSelector,
        @"setting-pacing":self.framePacingSelector, @"setting-mouse":self.btMouseSelector,
        @"setting-statistics":self.statsOverlaySelector};

    NSDictionary *labels = @{@"Resolution":@"settings.resolution", @"Frame Rate":@"settings.framerate",
        @"Touch Mode":@"settings.touch", @"On-Screen Controls":@"settings.controls", @"Optimize Game Settings":@"settings.optimize",
        @"Multi-Controller Mode":@"settings.controllers", @"Swap A/B and X/Y Buttons":@"settings.swap",
        @"Play Audio on PC":@"settings.audio", @"Preferred Codec":@"settings.codec", @"HDR (Beta)":@"settings.hdr",
        @"Frame Pacing Preference":@"settings.pacing", @"Citrix X1 Mouse Support":@"settings.mouse", @"Statistics Overlay":@"settings.statistics"};
    NSString *rowLabel = @"";
    UILabel *pendingLabel = nil;
    NSDictionary *segmentTitles = @{@"Off":@"settings.off", @"On":@"settings.on", @"No":@"settings.no", @"Yes":@"settings.yes",
        @"Auto":@"settings.auto", @"Simple":@"settings.simple", @"Full":@"settings.full", @"Safe Area":@"settings.safe_area",
        @"Custom":@"settings.custom", @"Touchpad":@"settings.touchpad", @"Touchscreen":@"settings.touchscreen",
        @"Lowest Latency":@"settings.low_latency", @"Smoothest Video":@"settings.smooth",
        @"Unsupported on this device":@"settings.unsupported"};
    for (UIView *view in legacyViews) {
        [view removeFromSuperview];
        view.translatesAutoresizingMaskIntoConstraints = NO;
        if ([view isKindOfClass:UILabel.class]) {
            UILabel *label = (UILabel *)view;
            NSString *key = labels[label.text];
            if (key != nil) {
                label.text = NSLocalizedStringFromTable(key, @"StreamTarget", nil);
            }
            label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
            label.adjustsFontForContentSizeCategory = YES;
            label.numberOfLines = 0;
            label.textColor = UIColor.labelColor;
            rowLabel = label.text;
            pendingLabel = label;
            continue;
        }
        if (view == self.resolutionDisplayView) {
            if (!self.streaming) [_allSettingRows.lastObject addArrangedSubview:view];
            continue;
        }
        UIControl *source = [view isKindOfClass:UIControl.class] ? (UIControl *)view : nil;
        if (source == nil) continue;
        UIView *presented = view;
        NSString *identifier;
        if ([view isKindOfClass:UISegmentedControl.class]) {
            UISegmentedControl *control = (UISegmentedControl *)view;
            for (NSUInteger index = 0; index < control.numberOfSegments; index++) {
                NSString *oldTitle = [control titleForSegmentAtIndex:index];
                NSString *key = segmentTitles[oldTitle];
                if (control == self.resolutionSelector && [oldTitle isEqualToString:@"Full"]) {
                    key = @"settings.fullscreen";
                }
                if (key != nil) {
                    [control setTitle:NSLocalizedStringFromTable(key, @"StreamTarget", nil) forSegmentAtIndex:index];
                }
            }
            identifier = [[controls allKeysForObject:control] firstObject];
            SettingsChoiceView *choice = [[SettingsChoiceView alloc] initWithControl:control label:rowLabel identifier:identifier];
            choice.translatesAutoresizingMaskIntoConstraints = NO;
            [choice addTarget:self action:@selector(refreshSettingsChoices) forControlEvents:UIControlEventValueChanged];
            [choice addTarget:self action:@selector(settingValueChanged:) forControlEvents:UIControlEventValueChanged];
            [_settingsChoices addObject:choice];
            presented = choice;
        }
        else if (source == self.bitrateSlider) {
            identifier = @"setting-bitrate";
            source.accessibilityIdentifier = identifier;
        }
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:pendingLabel ? @[pendingLabel, presented] : @[presented]];
        row.axis = UILayoutConstraintAxisVertical;
        row.spacing = 10;
        if (!self.streaming) [row addArrangedSubview:[self effectLabelForControl:source identifier:identifier]];
        [_allSettingRows addObject:row];
        [_rowControls setObject:source forKey:row];
        pendingLabel = nil;
    }
    [self refreshVisibleSettingRows];
    _originalSettingsY = nil;
    [self.scrollView addSubview:stack];
    _settingsLeading = [stack.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor constant:16];
    _settingsTrailing = [stack.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor constant:-16];
    _settingsWidth = [stack.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor constant:-32];
    _settingsTop = [stack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:20];
    _settingsBottom = [stack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-20];
    [NSLayoutConstraint activateConstraints:@[_settingsLeading, _settingsTrailing, _settingsWidth, _settingsTop, _settingsBottom]];
}

- (void)refreshVisibleSettingRows {
    if (_settingRows == nil) return;
    NSMutableArray<UIStackView *> *visible = [[NSMutableArray alloc] init];
    for (UIStackView *row in _allSettingRows) {
        UIControl *control = [_rowControls objectForKey:row];
        BOOL video = control == self.resolutionSelector || control == self.framerateSelector || control == self.bitrateSlider;
        if (!self.streaming || control == self.statsOverlaySelector ||
            (control == self.onscreenControlSelector && self.onScreenControlsAvailable) || (video && _manualVideoAvailable)) [visible addObject:row];
    }
    if ([_visibleSettingRows isEqualToArray:visible]) return;
    for (UIView *row in _settingRows.arrangedSubviews.copy) {
        [_settingRows removeArrangedSubview:row];
        [row removeFromSuperview];
    }
    for (UIView *row in visible) [_settingRows addArrangedSubview:row];
    _visibleSettingRows = [visible copy];
}

- (void)setOnScreenControlsAvailable:(BOOL)onScreenControlsAvailable {
    _onScreenControlsAvailable = onScreenControlsAvailable;
    [self refreshVisibleSettingRows];
}

- (void)refreshSettingsChoices {
    for (SettingsChoiceView *choice in _settingsChoices) {
        [choice refresh];
    }
}

- (UILabel *)effectLabelForControl:(UIControl *)control identifier:(NSString *)identifier {
    BOOL live = control == self.statsOverlaySelector || control == self.onscreenControlSelector;
    NSString *key = @"settings.effect.restart";
    if (control == self.statsOverlaySelector) key = self.streaming ? @"settings.effect.live" : @"settings.effect.live_available";
    else if (control == self.onscreenControlSelector) key = self.streaming ? @"settings.effect.controls" : @"settings.effect.controls_available";
    else if (control == self.optimizeSettingsSelector) key = @"settings.effect.launch";
    UILabel *label = [[UILabel alloc] init];
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    label.adjustsFontForContentSizeCategory = YES;
    label.numberOfLines = 0;
    label.textColor = live ? UIColor.systemGreenColor : UIColor.secondaryLabelColor;
    label.text = NSLocalizedStringFromTable(key, @"StreamTarget", nil);
    label.accessibilityIdentifier = [identifier stringByAppendingString:@"-effect"];
    _effectLabels[identifier] = label;
    if (control == self.resolutionSelector || control == self.framerateSelector || control == self.bitrateSlider) {
        label.text = NSLocalizedStringFromTable(!self.streaming ? @"manual.effect.before" : (_manualVideoAvailable ? @"manual.effect.live" : @"settings.effect.restart"), @"StreamTarget", nil);
        label.textColor = _manualVideoAvailable ? UIColor.systemGreenColor : UIColor.secondaryLabelColor;
    }
    return label;
}

- (ManualVideoSettings *)chosenVideoSettings {
    return [[ManualVideoSettings alloc] initWithWidth:[self getChosenStreamWidth] height:[self getChosenStreamHeight]
        frameRate:[self getChosenFrameRate] bitrate:_bitrate];
}

- (void)settingValueChanged:(UIControl *)sender {
    if (_editingCustomResolution || (sender == self.bitrateSlider && self.bitrateSlider.tracking)) return;
    UIControl *source = [sender isKindOfClass:SettingsChoiceView.class] ? ((SettingsChoiceView *)sender).control : sender;
    ManualVideoFields fields = source == self.resolutionSelector ? ManualVideoResolution :
        source == self.framerateSelector ? ManualVideoFrameRate : source == self.bitrateSlider ? ManualVideoBitrate : 0;
    [self saveSettings];
    if (self.changeHandler) self.changeHandler();
    if (self.streaming && fields) {
        ManualVideoSettings *settings = [self chosenVideoSettings];
        if (_manualVideoAvailable && self.videoSettingsChanged) self.videoSettingsChanged(settings, fields);
    }
}

- (void)updateManualVideoSettings:(ManualVideoSettings *)settings available:(BOOL)available updating:(BOOL)updating message:(NSString *)message {
    _manualVideoSettings = settings;
    _manualVideoAvailable = available;
    _manualVideoUpdating = updating;
    _manualVideoMessage = [message copy];
    if (!self.isViewLoaded) return;
    _manualVideoNotice.text = message;
    _manualVideoNotice.hidden = message.length == 0;
    [self refreshVisibleSettingRows];
    if (settings && !updating && !_editingCustomResolution && !self.bitrateSlider.tracking) [self applyManualVideoControls];
}

- (void)applyManualVideoControls {
    ManualVideoSettings *settings = _manualVideoSettings;
    if (!settings.valid) return;
    resolutionTable[RESOLUTION_TABLE_CUSTOM_INDEX] = CGSizeMake(settings.width, settings.height);
    NSInteger resolution = RESOLUTION_TABLE_CUSTOM_INDEX;
    for (NSInteger index = 0; index < RESOLUTION_TABLE_CUSTOM_INDEX; index++) {
        if (resolutionTable[index].width == settings.width && resolutionTable[index].height == settings.height) { resolution = index; break; }
    }
    self.resolutionSelector.selectedSegmentIndex = resolution;
    _lastSelectedResolutionIndex = resolution;
    NSInteger frameIndex = NSNotFound;
    for (NSInteger index = 0; index < self.framerateSelector.numberOfSegments; index++) {
        if ([[self.framerateSelector titleForSegmentAtIndex:index] integerValue] == settings.frameRate) { frameIndex = index; break; }
    }
    if (frameIndex == NSNotFound) {
        frameIndex = self.framerateSelector.numberOfSegments;
        [self.framerateSelector insertSegmentWithTitle:[NSString stringWithFormat:@"%ld FPS", (long)settings.frameRate] atIndex:frameIndex animated:NO];
    }
    self.framerateSelector.selectedSegmentIndex = frameIndex;
    _bitrate = settings.bitrate;
    [self.bitrateSlider setValue:[self getSliderValueForBitrate:_bitrate] animated:NO];
    [self updateBitrateText];
    [self updateResolutionDisplayViewText];
}

- (void)closeSettings {
    [self saveSettings];
    if (self.closeHandler) {
        self.closeHandler();
        return;
    }
    if (self.navigationController.topViewController == self && self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
    }
    else if (self.presentingViewController != nil) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
    else {
        [self.revealViewController revealToggleAnimated:YES];
    }
}

- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
    [self saveSettings];
}

- (void) touchModeChanged {
    // Disable on-screen controls in absolute touch mode
    [self.onscreenControlSelector setEnabled:[self.touchModeSelector selectedSegmentIndex] == 0];
}

- (void)streamTargetChanged {
    _targetPreferences.selectedTarget = _targetSettingsView.selectedTarget;
    [_targetPreferences save];
    if (self.changeHandler) self.changeHandler();
}

- (void)streamTargetTextSizeChanged:(NSNotification *)notification {
    [self.view setNeedsLayout];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!self.streaming) [self.navigationController setNavigationBarHidden:NO animated:animated];
    [self configureStreamTargetsForHost:_targetHost];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self saveSettings];
}

- (void)configureStreamTargetsForHost:(TemporaryHost *)host {
    if (self.streaming) return;
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self configureStreamTargetsForHost:host]; });
        return;
    }
    _targetHost = host;
    if (!self.isViewLoaded) return;
    NSUInteger generation = ++_targetQueryGeneration;
    if (host == nil || host.pairState != PairStatePaired || host.serverCert.length == 0) {
        [_targetSettingsView updateWithModes:nil statusText:NSLocalizedStringFromTable(@"target.choose_host", @"StreamTarget", nil)];
        [self.view setNeedsLayout];
        return;
    }
    NSString *loading = [NSString stringWithFormat:NSLocalizedStringFromTable(@"target.loading", @"StreamTarget", nil), host.name];
    [_targetSettingsView updateWithModes:nil statusText:loading];
    [self.view setNeedsLayout];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        HttpManager *manager = [[HttpManager alloc] initWithHost:host];
        StreamModesResponse *modes = [[StreamModesResponse alloc] init];
        [manager executeRequestSynchronously:[HttpRequest requestForResponse:modes withUrlRequest:[manager newStreamModesRequest]]];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self->_targetQueryGeneration) {
                return;
            }
            NSString *key = modes.supportsDisplayModes ? @"target.ready" : (modes.isLegacyHost ? @"target.legacy" : @"target.error.discovery");
            NSString *status = [NSString stringWithFormat:@"%@\n%@", host.name, NSLocalizedStringFromTable(key, @"StreamTarget", nil)];
            [self->_targetSettingsView updateWithModes:modes statusText:status];
            [self.view setNeedsLayout];
        });
    });
}

- (void) updateBitrate {
    if (self.streaming && _manualVideoAvailable) return;
    NSInteger fps = [self getChosenFrameRate];
    NSInteger width = [self getChosenStreamWidth];
    NSInteger height = [self getChosenStreamHeight];
    NSInteger defaultBitrate;
    
    // This logic is shamelessly stolen from Moonlight Qt:
    // https://github.com/moonlight-stream/moonlight-qt/blob/master/app/settings/streamingpreferences.cpp
    
    // Don't scale bitrate linearly beyond 60 FPS. It's definitely not a linear
    // bitrate increase for frame rate once we get to values that high.
    float frameRateFactor = (fps <= 60 ? fps : (sqrtf(fps / 60.f) * 60.f)) / 30.f;

    // TODO: Collect some empirical data to see if these defaults make sense.
    // We're just using the values that the Shield used, as we have for years.
    struct {
        NSInteger pixels;
        int factor;
    } resTable[] = {
        { 640 * 360, 1 },
        { 854 * 480, 2 },
        { 1280 * 720, 5 },
        { 1920 * 1080, 10 },
        { 2560 * 1440, 20 },
        { 3840 * 2160, 40 },
        { -1, -1 }
    };

    // Calculate the resolution factor by linear interpolation of the resolution table
    float resolutionFactor;
    NSInteger pixels = width * height;
    for (int i = 0;; i++) {
        if (pixels == resTable[i].pixels) {
            // We can bail immediately for exact matches
            resolutionFactor = resTable[i].factor;
            break;
        }
        else if (pixels < resTable[i].pixels) {
            if (i == 0) {
                // Never go below the lowest resolution entry
                resolutionFactor = resTable[i].factor;
            }
            else {
                // Interpolate between the entry greater than the chosen resolution (i) and the entry less than the chosen resolution (i-1)
                resolutionFactor = ((float)(pixels - resTable[i-1].pixels) / (resTable[i].pixels - resTable[i-1].pixels)) * (resTable[i].factor - resTable[i-1].factor) + resTable[i-1].factor;
            }
            break;
        }
        else if (resTable[i].pixels == -1) {
            // Never go above the highest resolution entry
            resolutionFactor = resTable[i-1].factor;
            break;
        }
    }

    defaultBitrate = round(resolutionFactor * frameRateFactor) * 1000;
    _bitrate = MIN(defaultBitrate, 100000);
    [self.bitrateSlider setValue:[self getSliderValueForBitrate:_bitrate] animated:YES];
    
    [self updateBitrateText];
}

- (void) newResolutionChosen {
    BOOL lastSegmentSelected = [self.resolutionSelector selectedSegmentIndex] + 1 == [self.resolutionSelector numberOfSegments];
    if (lastSegmentSelected) {
        [self promptCustomResolutionDialog];
    }
    else {
        [self updateBitrate];
        [self updateResolutionDisplayViewText];
        _lastSelectedResolutionIndex = [self.resolutionSelector selectedSegmentIndex];
    }
}

- (void) promptCustomResolutionDialog {
    _editingCustomResolution = YES;
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Enter Custom Resolution" message:nil preferredStyle:UIAlertControllerStyleAlert];

    [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Video Width";
        textField.clearButtonMode = UITextFieldViewModeAlways;
        textField.borderStyle = UITextBorderStyleRoundedRect;
        textField.keyboardType = UIKeyboardTypeNumberPad;
        
        if (resolutionTable[RESOLUTION_TABLE_CUSTOM_INDEX].width == 0) {
            textField.text = @"";
        }
        else {
            textField.text = [NSString stringWithFormat:@"%d", (int) resolutionTable[RESOLUTION_TABLE_CUSTOM_INDEX].width];
        }
    }];

    [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Video Height";
        textField.clearButtonMode = UITextFieldViewModeAlways;
        textField.borderStyle = UITextBorderStyleRoundedRect;
        textField.keyboardType = UIKeyboardTypeNumberPad;
        
        if (resolutionTable[RESOLUTION_TABLE_CUSTOM_INDEX].height == 0) {
            textField.text = @"";
        }
        else {
            textField.text = [NSString stringWithFormat:@"%d", (int) resolutionTable[RESOLUTION_TABLE_CUSTOM_INDEX].height];
        }
    }];

    [alertController addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSArray * textfields = alertController.textFields;
        UITextField *widthField = textfields[0];
        UITextField *heightField = textfields[1];
        
        long width = [widthField.text integerValue];
        long height = [heightField.text integerValue];
        self->_editingCustomResolution = NO;
        if (width <= 0 || height <= 0) {
            // Restore the previous selection
            [self.resolutionSelector setSelectedSegmentIndex:self->_lastSelectedResolutionIndex];
            [self refreshSettingsChoices];
            [self saveSettings];
            return;
        }
        
        // H.264 maximum
        int maxResolutionDimension = 4096;
        if (@available(iOS 11.0, tvOS 11.0, *)) {
            if (VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)) {
                // HEVC maximum
                maxResolutionDimension = 8192;
            }
        }
        
        // Cap to maximum valid dimensions
        width = MIN(width, maxResolutionDimension);
        height = MIN(height, maxResolutionDimension);
        
        // Cap to minimum valid dimensions
        width = MAX(width, 256);
        height = MAX(height, 256);

        resolutionTable[RESOLUTION_TABLE_CUSTOM_INDEX] = CGSizeMake(width, height);
        [self updateBitrate];
        [self updateResolutionDisplayViewText];
        self->_lastSelectedResolutionIndex = [self.resolutionSelector selectedSegmentIndex];
        [self settingValueChanged:self.resolutionSelector];
        if (self.streaming && self->_manualVideoAvailable) return;
        
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Custom Resolution Selected" message: @"Custom resolutions are not officially supported by GeForce Experience, so it will not set your host display resolution. You will need to set it manually while in game.\n\nResolutions that are not supported by your client or host PC may cause streaming errors." preferredStyle:UIAlertControllerStyleAlert];
        [alertController addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alertController animated:YES completion:nil];
    }]];

    [alertController addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        self->_editingCustomResolution = NO;
        // Restore the previous selection
        [self.resolutionSelector setSelectedSegmentIndex:self->_lastSelectedResolutionIndex];
        [self refreshSettingsChoices];
        [self saveSettings];
    }]];

    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)resolutionDisplayViewTapped:(UITapGestureRecognizer *)sender {
    NSURL *url = [NSURL URLWithString:@"https://moonlight-stream.org/custom-resolution"];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

- (void)updateResolutionDisplayViewText {
    for (UIView *view in self.resolutionDisplayView.subviews) {
        [view removeFromSuperview];
    }
    UILabel *summary = [[UILabel alloc] init];
    summary.translatesAutoresizingMaskIntoConstraints = NO;
    summary.text = [NSString stringWithFormat:NSLocalizedStringFromTable(@"settings.host_resolution", @"StreamTarget", nil),
        (long)[self getChosenStreamWidth], (long)[self getChosenStreamHeight]];
    summary.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    summary.adjustsFontForContentSizeCategory = YES;
    summary.numberOfLines = 0;
    summary.textColor = [UIColor colorWithWhite:0.78 alpha:1];
    [self.resolutionDisplayView addSubview:summary];
    [NSLayoutConstraint activateConstraints:@[
        [summary.leadingAnchor constraintEqualToAnchor:self.resolutionDisplayView.leadingAnchor constant:12],
        [summary.trailingAnchor constraintEqualToAnchor:self.resolutionDisplayView.trailingAnchor constant:-12],
        [summary.topAnchor constraintEqualToAnchor:self.resolutionDisplayView.topAnchor constant:10],
        [summary.bottomAnchor constraintEqualToAnchor:self.resolutionDisplayView.bottomAnchor constant:-10],
    ]];
    [self refreshSettingsChoices];
}

- (void) bitrateSliderMoved {
    assert(self.bitrateSlider.value < (sizeof(bitrateTable) / sizeof(*bitrateTable)));
    _bitrate = bitrateTable[(int)self.bitrateSlider.value];
    [self updateBitrateText];
}

- (void) updateBitrateText {
    // Display bitrate in Mbps
    [self.bitrateLabel setText:[NSString stringWithFormat:NSLocalizedStringFromTable(@"settings.bitrate_format", @"StreamTarget", nil), _bitrate / 1000.]];
}

- (NSInteger) getChosenFrameRate {
    return [[self.framerateSelector titleForSegmentAtIndex:self.framerateSelector.selectedSegmentIndex] integerValue];
}

- (uint32_t) getChosenCodecPreference {
    // Auto is always the last segment
    if (self.codecSelector.selectedSegmentIndex == self.codecSelector.numberOfSegments - 1) {
        return CODEC_PREF_AUTO;
    }
    else {
        switch (self.codecSelector.selectedSegmentIndex) {
            case 0:
                return CODEC_PREF_H264;
                
            case 1:
                return CODEC_PREF_HEVC;
                
            case 2:
                return CODEC_PREF_AV1;
                
            default:
                abort();
        }
    }
}

- (NSInteger) getChosenStreamHeight {
    // because the 4k resolution can be removed
    BOOL lastSegmentSelected = [self.resolutionSelector selectedSegmentIndex] + 1 == [self.resolutionSelector numberOfSegments];
    if (lastSegmentSelected) {
        return resolutionTable[RESOLUTION_TABLE_CUSTOM_INDEX].height;
    }

    return resolutionTable[[self.resolutionSelector selectedSegmentIndex]].height;
}

- (NSInteger) getChosenStreamWidth {
    // because the 4k resolution can be removed
    BOOL lastSegmentSelected = [self.resolutionSelector selectedSegmentIndex] + 1 == [self.resolutionSelector numberOfSegments];
    if (lastSegmentSelected) {
        return resolutionTable[RESOLUTION_TABLE_CUSTOM_INDEX].width;
    }

    return resolutionTable[[self.resolutionSelector selectedSegmentIndex]].width;
}

- (void) saveSettings {
    if (_editingCustomResolution) return;
    DataManager* dataMan = [[DataManager alloc] init];
    if (self.streaming) {
        [dataMan saveLiveControls:self.onScreenControlsAvailable ? @(self.onscreenControlSelector.selectedSegmentIndex) : nil
            statistics:@(self.statsOverlaySelector.selectedSegmentIndex == 1)];
        return;
    }
    NSInteger framerate = [self getChosenFrameRate];
    NSInteger height = [self getChosenStreamHeight];
    NSInteger width = [self getChosenStreamWidth];
    NSInteger bitrate = _bitrate;
    NSInteger onscreenControls = [self.onscreenControlSelector selectedSegmentIndex];
    BOOL optimizeGames = [self.optimizeSettingsSelector selectedSegmentIndex] == 1;
    BOOL multiController = [self.multiControllerSelector selectedSegmentIndex] == 1;
    BOOL swapABXYButtons = [self.swapABXYButtonsSelector selectedSegmentIndex] == 1;
    BOOL audioOnPC = [self.audioOnPCSelector selectedSegmentIndex] == 1;
    uint32_t preferredCodec = [self getChosenCodecPreference];
    BOOL btMouseSupport = [self.btMouseSelector selectedSegmentIndex] == 1;
    BOOL useFramePacing = [self.framePacingSelector selectedSegmentIndex] == 1;
    BOOL absoluteTouchMode = [self.touchModeSelector selectedSegmentIndex] == 1;
    BOOL statsOverlay = [self.statsOverlaySelector selectedSegmentIndex] == 1;
    BOOL enableHdr = [self.hdrSelector selectedSegmentIndex] == 1;
    [dataMan saveSettingsWithBitrate:bitrate
                           framerate:framerate
                              height:height
                               width:width
                         audioConfig:2 // Stereo
                    onscreenControls:onscreenControls
                       optimizeGames:optimizeGames
                     multiController:multiController
                     swapABXYButtons:swapABXYButtons
                           audioOnPC:audioOnPC
                      preferredCodec:preferredCodec
                      useFramePacing:useFramePacing
                           enableHdr:enableHdr
                      btMouseSupport:btMouseSupport
                   absoluteTouchMode:absoluteTouchMode
                        statsOverlay:statsOverlay];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


#pragma mark - Navigation

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
}


@end
