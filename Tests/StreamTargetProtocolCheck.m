#import <Foundation/Foundation.h>
#import "StreamTargetPreferences.h"
#import "StreamModesResponse.h"
#include <assert.h>

static StreamModesResponse *Modes(NSString *xml) {
    StreamModesResponse *response = [[StreamModesResponse alloc] init];
    [response populateWithData:[xml dataUsingEncoding:NSUTF8StringEncoding]];
    return response;
}

int main(void) {
    @autoreleasepool {
        NSString *suite = [@"SideLantern.ProtocolCheck." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        StreamTargetPreferences *preferences = [[StreamTargetPreferences alloc] initWithUserDefaults:defaults];
        assert(preferences.selectedTarget == StreamTargetPrimaryDisplay);
        for (NSInteger target = StreamTargetPrimaryDisplay; target <= StreamTargetWirelessDisplay; target++) {
            preferences.selectedTarget = target;
            [preferences save];
            assert([[[StreamTargetPreferences alloc] initWithUserDefaults:defaults] selectedTarget] == target);
        }
        [defaults setObject:@"future_unknown_mode" forKey:@"SideLantern.StreamTarget"];
        assert([[[StreamTargetPreferences alloc] initWithUserDefaults:defaults] selectedTarget] == StreamTargetPrimaryDisplay);
        [defaults setObject:@{} forKey:@"SideLantern.StreamTarget"];
        assert([[[StreamTargetPreferences alloc] initWithUserDefaults:defaults] selectedTarget] == StreamTargetPrimaryDisplay);
        preferences.selectedTarget = -1;
        [preferences save];
        assert([[[StreamTargetPreferences alloc] initWithUserDefaults:defaults] selectedTarget] == StreamTargetPrimaryDisplay);
        [defaults removePersistentDomainForName:suite];

        assert([StreamModeIdentifierForTarget(StreamTargetPrimaryDisplay) isEqualToString:@"primary"]);
        assert([StreamModeIdentifierForTarget(StreamTargetSecondaryDisplay) isEqualToString:@"secondary"]);
        assert([StreamModeIdentifierForTarget(StreamTargetWirelessDisplay) isEqualToString:@"extend"]);

        NSString *available = @"<root status_code=\"200\" version=\"1\">"
            "<mode id=\"primary\" available=\"1\" reason=\"\"/>"
            "<mode id=\"secondary\" available=\"0\" reason=\"other_displays_active\"/>"
            "<mode id=\"extend\" available=\"1\" reason=\"\"/></root>";
        StreamModesResponse *response = Modes(available);
        assert(response.supportsDisplayModes);
        assert([response isModeAvailable:@"primary"]);
        assert(![response isModeAvailable:@"secondary"]);
        assert([response isModeAvailable:@"extend"]);
        assert([[response reasonForMode:@"secondary"] isEqualToString:@"other_displays_active"]);
        assert(![response isModeAvailable:@"unknown"]);

        assert(!Modes([available stringByReplacingOccurrencesOfString:@"version=\"1\"" withString:@"version=\"2\""]).supportsDisplayModes);
        assert(!Modes([available stringByReplacingOccurrencesOfString:@"status_code=\"200\"" withString:@"status_code=\"200bad\""]).supportsDisplayModes);
        assert(!Modes([available stringByReplacingOccurrencesOfString:@"id=\"extend\"" withString:@"id=\"primary\""]).supportsDisplayModes);
        assert(!Modes([available stringByReplacingOccurrencesOfString:@"available=\"1\"" withString:@"available=\"true\""]).supportsDisplayModes);
        assert(!Modes(@"<root status_code=\"200\" version=\"1\"><mode id=\"primary\" available=\"1\" reason=\"\"/></root>").supportsDisplayModes);
        assert(!Modes(@"<root status_code=\"200\" version=\"1\"><mode/></root>").supportsDisplayModes);
        assert(!Modes(@"<root").supportsDisplayModes);

        StreamModesResponse *legacy = Modes(@"<html><body>Not found</body></html>");
        legacy.httpStatusCode = 404;
        assert(legacy.isLegacyHost && !legacy.supportsDisplayModes);
        legacy.httpStatusCode = 403;
        assert(!legacy.isLegacyHost);
        assert(!Modes(@"<root status_code=\"401\"/>").isLegacyHost);

        NSString *busy = [available stringByReplacingOccurrencesOfString:@"available=\"1\" reason=\"\"" withString:@"available=\"0\" reason=\"capture_busy\""];
        assert(![Modes(busy) isModeAvailable:@"primary"]);
        assert([[Modes(busy) reasonForMode:@"primary"] isEqualToString:@"capture_busy"]);

        HttpResponse *rejection = [[HttpResponse alloc] init];
        [rejection populateWithData:[@"<root status_code=\"409\"><sidelantern_reason>capture_busy</sidelantern_reason><gamesession>0</gamesession></root>" dataUsingEncoding:NSUTF8StringEncoding]];
        assert(!rejection.isStatusOk);
        assert([[rejection getStringTag:@"sidelantern_reason"] isEqualToString:@"capture_busy"]);
        puts("Stream target preferences and API protocol checks passed.");
    }
    return 0;
}
