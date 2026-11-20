#import "StreamModesResponse.h"

NSString *StreamModeIdentifierForTarget(StreamTarget target) {
    switch (target) {
        case StreamTargetPrimaryDisplay: return @"primary";
        case StreamTargetSecondaryDisplay: return @"secondary";
        case StreamTargetWirelessDisplay: return @"extend";
    }
    return @"primary";
}

NSString *StreamModeFailureMessage(NSString *reason) {
    NSSet *knownReasons = [NSSet setWithArray:@[@"unknown_mode", @"capture_busy", @"primary_display_unavailable",
        @"secondary_display_unavailable", @"other_displays_active", @"display_preparation_failed", @"unsupported_platform"]];
    NSString *key = [knownReasons containsObject:reason] ? [@"target.error." stringByAppendingString:reason] : @"target.error.unavailable";
    return NSLocalizedStringFromTable(key, @"StreamTarget", nil);
}

@implementation StreamModesResponse {
    NSMutableDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *_modes;
    NSUInteger _depth;
    BOOL _validDocument;
    BOOL _versionSupported;
    BOOL _successStatus;
    BOOL _manualVideoSupported;
}

- (void)parseData {
    _modes = [[NSMutableDictionary alloc] init];
    _depth = 0;
    _validDocument = YES;
    _versionSupported = NO;
    _successStatus = NO;
    _manualVideoSupported = NO;
    self.statusCode = 0;
    self.statusMessage = NSLocalizedStringFromTable(@"target.error.discovery", @"StreamTarget", nil);
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:self.data ?: [NSData data]];
    parser.delegate = self;
    parser.shouldResolveExternalEntities = NO;
    if (![parser parse]) {
        _validDocument = NO;
    }
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI
    qualifiedName:(NSString *)qualifiedName attributes:(NSDictionary<NSString *, NSString *> *)attributes {
    _depth++;
    if (_depth == 1) {
        _validDocument = [elementName isEqualToString:@"root"];
        self.statusCode = [attributes[@"status_code"] integerValue];
        _successStatus = [attributes[@"status_code"] isEqualToString:@"200"];
        _versionSupported = [attributes[@"version"] isEqualToString:@"1"];
        _manualVideoSupported = [attributes[@"manual_video_version"] isEqualToString:@"1"];
        if (attributes[@"status_message"].length > 0) {
            self.statusMessage = attributes[@"status_message"];
        }
    }
    else if (_depth == 2 && [elementName isEqualToString:@"mode"]) {
        NSString *mode = attributes[@"id"];
        if (mode == nil || ![@[@"primary", @"secondary", @"extend"] containsObject:mode]) {
            return;
        }
        NSString *available = attributes[@"available"];
        if (_modes[mode] != nil || (![@"1" isEqualToString:available] && ![@"0" isEqualToString:available]) ||
            attributes[@"reason"] == nil || ([@"1" isEqualToString:available] && attributes[@"reason"].length != 0)) {
            _validDocument = NO;
            return;
        }
        _modes[mode] = attributes;
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI
    qualifiedName:(NSString *)qualifiedName {
    _depth--;
}

- (BOOL)supportsDisplayModes {
    return _validDocument && _versionSupported && _successStatus && self.statusCode == 200 && _modes.count == 3;
}

- (BOOL)isLegacyHost {
    return self.httpStatusCode == 404 || self.httpStatusCode == 501 || self.statusCode == 404 || self.statusCode == 501;
}

- (BOOL)supportsManualVideo { return self.supportsDisplayModes && _manualVideoSupported; }

- (BOOL)isModeAvailable:(NSString *)mode {
    return self.supportsDisplayModes && [_modes[mode][@"available"] isEqualToString:@"1"];
}

- (NSString *)reasonForMode:(NSString *)mode {
    return self.supportsDisplayModes ? _modes[mode][@"reason"] : nil;
}

@end
