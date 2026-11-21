#import "ManualVideoController.h"

@implementation ManualVideoController {
    ManualVideoTransport _transport;
    ManualVideoSchedule _schedule;
    NSString *_identifier;
    ManualVideoSettings *_queued;
    ManualVideoFields _queuedFields;
    ManualVideoSettings *_sent;
    ManualVideoFields _sentFields;
    NSUInteger _generation;
    NSUInteger _polls;
    BOOL _busy;
    BOOL _cancelled;
    NSInteger _initialBitrateBudget;
    NSInteger _audioChannels;
    ManualVideoBitrateBudget *_bitrateBudget;
    NSString *_error;
    NSTimeInterval _deadline;
}
- (instancetype)initWithTransport:(ManualVideoTransport)transport schedule:(ManualVideoSchedule)schedule {
    if ((self = [super init])) {
        _transport = [transport copy];
        if (schedule) _schedule = [schedule copy];
        else _schedule = ^(NSTimeInterval delay, void (^operation)(void)) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), operation);
        };
    }
    return self;
}
- (BOOL)available { return !_cancelled && self.response.validSession && self.state != ManualVideoUnavailable; }
- (NSString *)statusText {
    if (_error) return _error;
    NSString *key = self.state == ManualVideoLoading ? @"manual.loading" : self.state == ManualVideoApplying ? @"manual.applying" : @"manual.ready";
    return NSLocalizedStringFromTable(key, @"StreamTarget", nil);
}
- (void)notify {
    if (self.stateChanged) self.stateChanged(self);
    _appliedFields = 0;
}
- (void)refresh {
    if (_cancelled || _busy) return;
    _busy = YES; _polls = 0; _error = nil; _state = ManualVideoLoading;
    _deadline = NSDate.timeIntervalSinceReferenceDate + 15;
    [self notify];
    [self query:_generation];
}
- (void)refreshWithBitrateBudget:(NSInteger)bitrate audioChannels:(NSInteger)audioChannels {
    if (_cancelled || _busy) return;
    _initialBitrateBudget = bitrate;
    _audioChannels = audioChannels;
    _bitrateBudget = nil;
    [self refresh];
}
- (void)requestSettings:(ManualVideoSettings *)settings fields:(ManualVideoFields)fields bitrateBudget:(NSInteger)bitrateBudget {
    if (!self.available || fields == 0) return;
    if (fields & ManualVideoBitrate) {
        NSInteger bitrate = [_bitrateBudget encoderBitrateForBudget:bitrateBudget];
        if (bitrate < 500 || bitrate > 250000) { [self fail:@"invalid_video_settings" unavailable:NO]; return; }
        settings = [[ManualVideoSettings alloc] initWithWidth:settings.width height:settings.height frameRate:settings.frameRate bitrate:bitrate];
    }
    [self requestSettings:settings fields:fields];
}
- (void)requestSettings:(ManualVideoSettings *)settings fields:(ManualVideoFields)fields {
    if (!self.available || fields == 0) return;
    ManualVideoSettings *base = self.response.settings;
    if (_sent) base = [base replacingFields:_sentFields withSettings:_sent];
    if (_queued) base = [base replacingFields:_queuedFields withSettings:_queued];
    ManualVideoSettings *desired = [base replacingFields:fields withSettings:settings];
    if ([desired isEqual:base]) return;
    _queued = desired;
    _queuedFields |= fields;
    _error = nil;
    if (!_busy) {
        _busy = YES; _polls = 0;
        _deadline = NSDate.timeIntervalSinceReferenceDate + 15;
        _state = ManualVideoApplying;
        [self notify];
        [self query:_generation];
    }
}
- (void)cancel {
    _generation++; _cancelled = YES; _busy = NO;
    _queued = _sent = nil; _queuedFields = 0; _sentFields = 0;
}
- (void)fail:(NSString *)reason unavailable:(BOOL)unavailable {
    _busy = NO; _queued = _sent = nil; _queuedFields = _sentFields = 0;
    _state = unavailable ? ManualVideoUnavailable : ManualVideoFailed;
    _error = ManualVideoErrorText(reason);
    [self notify];
}
- (BOOL)acceptResponse:(ManualVideoResponse *)response {
    if (response.httpStatusCode == 404 || response.httpStatusCode == 501) {
        [self fail:@"unavailable" unavailable:YES]; return NO;
    }
    if (response.httpStatusCode != 0 && (response.httpStatusCode < 200 || response.httpStatusCode >= 300)) {
        [self fail:nil unavailable:NO]; return NO;
    }
    if (response.statusCode == 404 || response.statusCode == 501) {
        [self fail:@"unavailable" unavailable:YES]; return NO;
    }
    if (!response.validSession) { [self fail:nil unavailable:NO]; return NO; }
    if (_identifier && ![_identifier isEqualToString:response.sessionIdentifier]) {
        [self fail:@"stale_session" unavailable:YES]; return NO;
    }
    _identifier = response.sessionIdentifier;
    _response = response;
    if (!_bitrateBudget && _initialBitrateBudget > 0 && response.statusCode == 200) {
        _bitrateBudget = [[ManualVideoBitrateBudget alloc] initWithBudget:_initialBitrateBudget
            encoderBitrate:response.settings.bitrate audioChannels:_audioChannels];
    }
    return YES;
}
- (void)query:(NSUInteger)generation {
    _transport(nil, nil, ^(ManualVideoResponse *response) {
        if (self->_cancelled || generation != self->_generation || ![self acceptResponse:response]) return;
        if (response.statusCode != 200) { [self fail:response.reason unavailable:[response.reason isEqualToString:@"stale_session"]]; return; }
        if ([response.state isEqualToString:@"pending"]) { [self poll:generation]; return; }
        if (self->_sent) {
            if ([response.state isEqualToString:@"rejected"]) { [self fail:@"encoder_rejected" unavailable:NO]; return; }
            if (![response.state isEqualToString:@"applied"] || ![response.settings isEqual:self->_sent]) { [self poll:generation]; return; }
            self->_appliedFields = self->_sentFields;
            self->_sent = nil; self->_sentFields = 0;
            self->_state = self->_queuedFields ? ManualVideoApplying : ManualVideoReady;
            [self notify];
        }
        if (self->_queuedFields) [self send:generation];
        else { self->_busy = NO; self->_state = ManualVideoReady; [self notify]; }
    });
}
- (void)poll:(NSUInteger)generation {
    if (++_polls > 40 || NSDate.timeIntervalSinceReferenceDate >= _deadline) { [self fail:@"unconfirmed" unavailable:YES]; return; }
    _state = ManualVideoApplying;
    [self notify];
    __weak typeof(self) weakSelf = self;
    _schedule(0.25, ^{
        ManualVideoController *controller = weakSelf;
        if (controller && !controller->_cancelled && generation == controller->_generation) [controller query:generation];
    });
}
- (void)send:(NSUInteger)generation {
    _sent = [self.response.settings replacingFields:_queuedFields withSettings:_queued];
    _sentFields = _queuedFields;
    _queued = nil; _queuedFields = 0;
    _polls = 0;
    _deadline = NSDate.timeIntervalSinceReferenceDate + 15;
    if (!_sent.valid) { [self fail:@"invalid_video_settings" unavailable:NO]; return; }
    _state = ManualVideoApplying;
    [self notify];
    _transport(_identifier, _sent, ^(ManualVideoResponse *response) {
        if (self->_cancelled || generation != self->_generation || ![self acceptResponse:response]) return;
        if (response.statusCode != 202) { [self fail:response.reason unavailable:[response.reason isEqualToString:@"stale_session"]]; return; }
        [self poll:generation];
    });
}
@end
