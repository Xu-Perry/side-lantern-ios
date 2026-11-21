#import "ManualVideoSettings.h"

@implementation ManualVideoSettings
- (instancetype)initWithWidth:(NSInteger)width height:(NSInteger)height frameRate:(NSInteger)frameRate bitrate:(NSInteger)bitrate {
    if ((self = [super init])) { _width = width; _height = height; _frameRate = frameRate; _bitrate = bitrate; }
    return self;
}
- (BOOL)valid {
    return self.width >= 64 && self.width <= 7680 && self.height >= 64 && self.height <= 7680 &&
        self.width % 2 == 0 && self.height % 2 == 0 && self.width * self.height <= 7680 * 4320 &&
        self.frameRate >= 1 && self.frameRate <= 240 && self.bitrate >= 500 && self.bitrate <= 250000;
}
- (id)copyWithZone:(NSZone *)zone { return self; }
- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:ManualVideoSettings.class]) return NO;
    ManualVideoSettings *other = object;
    return self.width == other.width && self.height == other.height && self.frameRate == other.frameRate && self.bitrate == other.bitrate;
}
- (NSUInteger)hash { return (NSUInteger)self.width ^ ((NSUInteger)self.height << 1) ^ ((NSUInteger)self.frameRate << 2) ^ ((NSUInteger)self.bitrate << 3); }
- (ManualVideoSettings *)replacingFields:(ManualVideoFields)fields withSettings:(ManualVideoSettings *)settings {
    return [[ManualVideoSettings alloc] initWithWidth:fields & ManualVideoResolution ? settings.width : self.width
        height:fields & ManualVideoResolution ? settings.height : self.height
        frameRate:fields & ManualVideoFrameRate ? settings.frameRate : self.frameRate
        bitrate:fields & ManualVideoBitrate ? settings.bitrate : self.bitrate];
}
@end

static NSInteger EncoderBitrateForBudget(NSInteger budget, NSInteger fec, NSInteger audioOverhead) {
    NSInteger video = budget / (100.f / (100 - fec));
    video -= MIN(audioOverhead, video / 5);
    video -= MIN(500, video / 10);
    return video;
}

@implementation ManualVideoBitrateBudget {
    NSInteger _initialBudget;
    NSInteger _initialEncoderBitrate;
    NSInteger _fec;
    NSInteger _audioOverhead;
    double _fraction;
}
- (instancetype)initWithBudget:(NSInteger)budget encoderBitrate:(NSInteger)encoderBitrate audioChannels:(NSInteger)audioChannels {
    if (budget <= 0 || encoderBitrate <= 0) return nil;
    if ((self = [super init])) {
        _initialBudget = budget;
        _initialEncoderBitrate = encoderBitrate;
        _fec = -1;
        NSInteger channels = MAX(1, MIN(8, audioChannels));
        // Sunshine adjusts configured bitrate for its FEC percentage, negotiated
        // audio quality and packet overhead. Learn these from the startup pair
        // instead of assuming that every host uses 20% FEC or high-quality audio.
        for (NSInteger fec = 0; fec <= 80; fec++) {
            for (NSNumber *rate in @[@96, @256]) {
                NSInteger audio = channels * rate.integerValue;
                if (EncoderBitrateForBudget(budget, fec, audio) == encoderBitrate) {
                    _fec = MAX(_fec, fec);
                    _audioOverhead = MAX(_audioOverhead, audio);
                }
            }
        }
        if (_fec < 0) {
            // A host limit can hide the original FEC adjustment. Use a
            // conservative allowance based on the negotiated encoder value.
            _fraction = MIN(1, (double)encoderBitrate / budget);
            _audioOverhead = channels * 256;
        }
    }
    return self;
}
- (NSInteger)encoderBitrateForBudget:(NSInteger)budget {
    if (budget < 500 || budget > 250000) return 0;
    if (budget == _initialBudget) return _initialEncoderBitrate;
    if (_fec >= 0) return EncoderBitrateForBudget(budget, _fec, _audioOverhead);
    NSInteger video = budget * _fraction;
    video -= MIN(_audioOverhead, video / 5);
    video -= MIN(500, video / 10);
    return video;
}
@end

static NSNumber *ManualVideoInteger(NSString *text) {
    NSCharacterSet *digits = [NSCharacterSet characterSetWithCharactersInString:@"0123456789"];
    if (text.length == 0 || text.length > 10 || [text rangeOfCharacterFromSet:digits.invertedSet].location != NSNotFound) return nil;
    unsigned long long value = text.longLongValue;
    return value <= UINT32_MAX ? @(value) : nil;
}

@implementation ManualVideoResponse {
    NSMutableDictionary<NSString *, NSString *> *_values;
    NSMutableString *_text;
    NSString *_field;
    NSUInteger _depth;
    BOOL _valid;
}
- (void)parseData {
    _values = [[NSMutableDictionary alloc] init];
    _depth = 0; _valid = YES; _field = nil; _text = nil;
    _sessionIdentifier = nil; _settings = nil; _state = nil; _reason = nil;
    self.statusCode = 0;
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:self.data ?: NSData.data];
    parser.shouldResolveExternalEntities = NO;
    parser.delegate = self;
    if (![parser parse]) _valid = NO;
    _state = _values[@"status"];
    _reason = _values[@"reason"];
    NSNumber *identifier = ManualVideoInteger(_values[@"session_id"]);
    NSNumber *width = ManualVideoInteger(_values[@"width"]), *height = ManualVideoInteger(_values[@"height"]);
    NSNumber *fps = ManualVideoInteger(_values[@"fps"]), *bitrate = ManualVideoInteger(_values[@"bitrate_kbps"]);
    if (identifier && width && height && fps && bitrate) {
        _sessionIdentifier = identifier.stringValue;
        _settings = [[ManualVideoSettings alloc] initWithWidth:width.integerValue height:height.integerValue
            frameRate:fps.integerValue bitrate:bitrate.integerValue];
    }
}
- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)element namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qualifiedName attributes:(NSDictionary<NSString *,NSString *> *)attributes {
    _depth++;
    if (_depth == 1) {
        _valid = [element isEqualToString:@"root"] && [attributes[@"version"] isEqualToString:@"1"];
        NSNumber *status = ManualVideoInteger(attributes[@"status_code"]);
        if (status == nil) _valid = NO;
        self.statusCode = status.integerValue;
    }
    else if (_depth == 2 && [@[@"session_id", @"width", @"height", @"fps", @"bitrate_kbps", @"status", @"reason"] containsObject:element]) {
        if (_values[element] != nil) _valid = NO;
        _field = element;
        _text = [[NSMutableString alloc] init];
    }
    else if (_field != nil) _valid = NO;
}
- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string { if (_field) [_text appendString:string]; }
- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)element namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qualifiedName {
    if (_depth == 2 && _field) { _values[_field] = _text; _field = nil; _text = nil; }
    _depth--;
}
- (BOOL)validSession {
    return _valid && self.sessionIdentifier != nil && self.settings.valid &&
        [@[@200, @202, @400, @409] containsObject:@(self.statusCode)] &&
        [@[@"idle", @"pending", @"applied", @"rejected"] containsObject:self.state];
}
@end

NSURLRequest *ManualVideoRequest(NSURL *baseURL, NSString *sessionIdentifier, ManualVideoSettings *settings) {
    if (![baseURL.scheme isEqualToString:@"https"] || baseURL.host.length == 0) return nil;
    NSURLComponents *url = [NSURLComponents componentsWithURL:baseURL resolvingAgainstBaseURL:NO];
    url.path = @"/sidelantern/v1/manual-video";
    url.queryItems = nil;
    url.fragment = nil;
    if (settings) {
        NSNumber *identifier = ManualVideoInteger(sessionIdentifier);
        if (identifier == nil || !settings.valid) return nil;
        url.queryItems = @[
            [NSURLQueryItem queryItemWithName:@"session_id" value:identifier.stringValue],
            [NSURLQueryItem queryItemWithName:@"width" value:@(settings.width).stringValue],
            [NSURLQueryItem queryItemWithName:@"height" value:@(settings.height).stringValue],
            [NSURLQueryItem queryItemWithName:@"fps" value:@(settings.frameRate).stringValue],
            [NSURLQueryItem queryItemWithName:@"bitrate_kbps" value:@(settings.bitrate).stringValue]];
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url.URL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10];
    request.HTTPMethod = settings ? @"POST" : @"GET";
    return request;
}

NSString *ManualVideoErrorText(NSString *reason) {
    NSSet *known = [NSSet setWithArray:@[@"invalid_video_settings", @"host_video_limit", @"stale_session", @"video_change_pending", @"encoder_rejected", @"unconfirmed", @"unavailable"]];
    NSString *key = [known containsObject:reason] ? [@"manual.error." stringByAppendingString:reason] : @"manual.error.connection";
    return NSLocalizedStringFromTable(key, @"StreamTarget", nil);
}
