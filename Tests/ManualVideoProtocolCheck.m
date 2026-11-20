#import <Foundation/Foundation.h>
#import "ManualVideoController.h"
#import "StreamModesResponse.h"
#include <assert.h>

static ManualVideoSettings *Settings(NSInteger width, NSInteger height, NSInteger fps, NSInteger bitrate) {
    return [[ManualVideoSettings alloc] initWithWidth:width height:height frameRate:fps bitrate:bitrate];
}
static ManualVideoResponse *Parse(NSString *xml) {
    ManualVideoResponse *response = [[ManualVideoResponse alloc] init];
    [response populateWithData:[xml dataUsingEncoding:NSUTF8StringEncoding]];
    response.httpStatusCode = 200;
    return response;
}
static ManualVideoResponse *Response(NSInteger code, NSString *state, NSString *identifier, ManualVideoSettings *settings) {
    return Parse([NSString stringWithFormat:@"<root version=\"1\" status_code=\"%ld\"><session_id>%@</session_id><width>%ld</width><height>%ld</height><fps>%ld</fps><bitrate_kbps>%ld</bitrate_kbps><status>%@</status></root>",
        (long)code, identifier, (long)settings.width, (long)settings.height, (long)settings.frameRate, (long)settings.bitrate, state]);
}
static void Drain(NSMutableArray *scheduled) {
    NSUInteger iterations = 0;
    while (scheduled.count) {
        assert(++iterations < 100);
        void (^operation)(void) = scheduled.firstObject;
        [scheduled removeObjectAtIndex:0];
        operation();
    }
}
int main(void) {
    @autoreleasepool {
        ManualVideoSettings *original = Settings(1920, 1080, 60, 9000);
        NSString *xml = @"<root version=\"1\" status_code=\"200\"><session_id>42</session_id><width>1920</width><height>1080</height><fps>60</fps><bitrate_kbps>9000</bitrate_kbps><status>idle</status></root>";
        assert(Parse(xml).validSession);
        assert([Parse(xml).settings isEqual:original]);
        assert(!Parse([xml stringByReplacingOccurrencesOfString:@"version=\"1\"" withString:@"version=\"2\""]).validSession);
        assert(!Parse([xml stringByReplacingOccurrencesOfString:@"<width>1920</width>" withString:@"<width>1920</width><width>1280</width>"]).validSession);
        assert(!Parse([xml stringByReplacingOccurrencesOfString:@"<fps>60</fps>" withString:@"<fps>60abc</fps>"]).validSession);
        assert(!Parse([xml stringByReplacingOccurrencesOfString:@"<session_id>42</session_id>" withString:@"<session_id>4294967296</session_id>"]).validSession);
        assert(!Parse([xml stringByReplacingOccurrencesOfString:@"<session_id>42</session_id>" withString:@"<session_id>٤٢</session_id>"]).validSession);
        assert(!Parse([xml substringToIndex:xml.length - 3]).validSession);
        assert(!Response(200, @"future", @"42", original).validSession);
        assert(!Response(200, @"idle", @"42", Settings(1921,1080,60,9000)).validSession);
        assert(!Settings(7680,7680,60,9000).valid);
        assert(!Settings(1920,1080,241,9000).valid);
        assert(!Settings(1920,1080,60,499).valid);
        assert(Settings(7680,4320,240,250000).valid);
        assert(Response(202, @"pending", @"4294967295", original).validSession);

        NSURLRequest *post = ManualVideoRequest([NSURL URLWithString:@"https://[::1]:47984/?uniqueid=legacy"], @"42", original);
        assert([post.HTTPMethod isEqualToString:@"POST"]);
        NSURLComponents *url = [NSURLComponents componentsWithURL:post.URL resolvingAgainstBaseURL:NO];
        assert([url.path isEqualToString:@"/sidelantern/v1/manual-video"]);
        assert(url.queryItems.count == 5);
        assert([ManualVideoRequest([NSURL URLWithString:@"https://host:47984"], nil, nil).HTTPMethod isEqualToString:@"GET"]);
        assert(!ManualVideoRequest([NSURL URLWithString:@"http://host"], @"42", original));
        assert(!ManualVideoRequest([NSURL URLWithString:@"https://host"], @"-1", original));

        NSString *modesXML = @"<root status_code=\"200\" version=\"1\" manual_video_version=\"1\"><mode id=\"primary\" available=\"0\" reason=\"capture_busy\"/><mode id=\"secondary\" available=\"0\" reason=\"capture_busy\"/><mode id=\"extend\" available=\"0\" reason=\"capture_busy\"/></root>";
        StreamModesResponse *modes = [[StreamModesResponse alloc] init];
        [modes populateWithData:[modesXML dataUsingEncoding:NSUTF8StringEncoding]];
        assert(modes.supportsManualVideo);
        [modes populateWithData:[[modesXML stringByReplacingOccurrencesOfString:@"manual_video_version=\"1\"" withString:@"manual_video_version=\"2\""] dataUsingEncoding:NSUTF8StringEncoding]];
        assert(modes.supportsDisplayModes && !modes.supportsManualVideo);

        NSMutableArray *scheduled = [[NSMutableArray alloc] init];
        NSMutableArray<ManualVideoSettings *> *posts = [[NSMutableArray alloc] init];
        __block ManualVideoSettings *current = original;
        __block ManualVideoSettings *pending = nil;
        __block NSUInteger pendingReads = 0;
        __block ManualVideoFields committed = 0;
        ManualVideoController *controller = [[ManualVideoController alloc] initWithTransport:^(NSString *identifier, ManualVideoSettings *settings, void (^done)(ManualVideoResponse *)) {
            if (settings) {
                assert([identifier isEqualToString:@"42"]);
                [posts addObject:settings]; pending = settings; pendingReads = 0;
                done(Response(202, @"pending", @"42", current));
            } else if (pending && pendingReads++ == 0) done(Response(200, @"pending", @"42", current));
            else {
                if (pending) { current = pending; pending = nil; }
                done(Response(200, posts.count ? @"applied" : @"idle", @"42", current));
            }
        } schedule:^(NSTimeInterval delay, void (^operation)(void)) { [scheduled addObject:[operation copy]]; }];
        controller.stateChanged = ^(ManualVideoController *state) { committed |= state.appliedFields; };
        [controller refresh]; assert(controller.available);
        [controller requestSettings:Settings(640,360,30,5500) fields:ManualVideoBitrate];
        assert(posts.count == 1 && posts[0].width == 1920 && posts[0].frameRate == 60);
        [controller requestSettings:Settings(640,360,30,5500) fields:ManualVideoBitrate];
        [controller requestSettings:Settings(1280,720,60,10000) fields:ManualVideoResolution];
        [controller requestSettings:Settings(1280,720,30,10000) fields:ManualVideoFrameRate];
        assert(controller.state == ManualVideoApplying && controller.response.settings.bitrate == 9000);
        Drain(scheduled);
        assert(posts.count == 2);
        assert([posts[1] isEqual:Settings(1280,720,30,5500)]);
        assert(controller.state == ManualVideoReady && committed == ManualVideoAll);

        __block BOOL submitted = NO;
        ManualVideoController *rejected = [[ManualVideoController alloc] initWithTransport:^(NSString *identifier, ManualVideoSettings *settings, void (^done)(ManualVideoResponse *)) {
            if (settings) { submitted = YES; done(Response(202,@"pending",@"42",original)); }
            else done(Response(200, submitted ? @"rejected" : @"idle", @"42", original));
        } schedule:^(NSTimeInterval delay, void (^operation)(void)) { [scheduled addObject:[operation copy]]; }];
        [rejected refresh];
        [rejected requestSettings:Settings(1920,1080,60,5000) fields:ManualVideoBitrate];
        Drain(scheduled);
        assert(rejected.state == ManualVideoFailed && rejected.available && [rejected.response.settings isEqual:original]);

        __block NSUInteger reads = 0, stalePosts = 0;
        ManualVideoController *stale = [[ManualVideoController alloc] initWithTransport:^(NSString *identifier, ManualVideoSettings *settings, void (^done)(ManualVideoResponse *)) {
            if (settings) stalePosts++;
            done(Response(200,@"idle", ++reads == 1 ? @"42" : @"43", original));
        } schedule:nil];
        [stale refresh]; [stale requestSettings:Settings(1920,1080,60,5000) fields:ManualVideoBitrate];
        assert(stale.state == ManualVideoUnavailable && stalePosts == 0);

        __block NSUInteger polls = 0;
        ManualVideoController *cancelled = [[ManualVideoController alloc] initWithTransport:^(NSString *identifier, ManualVideoSettings *settings, void (^done)(ManualVideoResponse *)) {
            polls++;
            done(Response(settings ? 202 : 200, settings ? @"pending" : @"idle", @"42", original));
        } schedule:^(NSTimeInterval delay, void (^operation)(void)) { [scheduled addObject:[operation copy]]; }];
        [cancelled refresh]; [cancelled requestSettings:Settings(1920,1080,60,5000) fields:ManualVideoBitrate];
        NSUInteger beforeCancel = polls;
        [cancelled cancel]; Drain(scheduled);
        assert(polls == beforeCancel && !cancelled.available);

        __block void (^lateReply)(ManualVideoResponse *);
        __block NSUInteger notifications = 0;
        ManualVideoController *inFlight = [[ManualVideoController alloc] initWithTransport:^(NSString *identifier, ManualVideoSettings *settings, void (^done)(ManualVideoResponse *)) {
            if (settings) lateReply = [done copy];
            else done(Response(200,@"idle",@"42",original));
        } schedule:nil];
        inFlight.stateChanged = ^(ManualVideoController *state) { notifications++; };
        [inFlight refresh]; [inFlight requestSettings:Settings(1920,1080,60,5000) fields:ManualVideoBitrate];
        NSUInteger beforeReply = notifications;
        [inFlight cancel]; lateReply(Response(202,@"pending",@"42",original));
        assert(notifications == beforeReply && !inFlight.available);
        lateReply = nil;

        ManualVideoController *limit = [[ManualVideoController alloc] initWithTransport:^(NSString *identifier, ManualVideoSettings *settings, void (^done)(ManualVideoResponse *)) {
            ManualVideoResponse *response = Response(settings ? 400 : 200,@"idle",@"42",original);
            if (settings) response = Parse([[[NSString alloc] initWithData:response.data encoding:NSUTF8StringEncoding]
                stringByReplacingOccurrencesOfString:@"</root>" withString:@"<reason>host_video_limit</reason></root>"]);
            done(response);
        } schedule:nil];
        [limit refresh]; [limit requestSettings:Settings(1920,1080,60,5000) fields:ManualVideoBitrate];
        assert(limit.state == ManualVideoFailed && limit.appliedFields == 0 && [limit.response.settings isEqual:original]);

        ManualVideoController *unsupported = [[ManualVideoController alloc] initWithTransport:^(NSString *identifier, ManualVideoSettings *settings, void (^done)(ManualVideoResponse *)) {
            done(Parse(@"<root version=\"1\" status_code=\"404\"><status>no_manual_video_session</status></root>"));
        } schedule:nil];
        [unsupported refresh]; assert(unsupported.state == ManualVideoUnavailable && !unsupported.available);

        __block BOOL accepted = NO;
        ManualVideoController *timeout = [[ManualVideoController alloc] initWithTransport:^(NSString *identifier, ManualVideoSettings *settings, void (^done)(ManualVideoResponse *)) {
            if (settings) accepted = YES;
            done(Response(settings ? 202 : 200, accepted ? @"pending" : @"idle", @"42", original));
        } schedule:^(NSTimeInterval delay, void (^operation)(void)) { [scheduled addObject:[operation copy]]; }];
        [timeout refresh]; [timeout requestSettings:Settings(1920,1080,60,5000) fields:ManualVideoBitrate];
        Drain(scheduled);
        assert(timeout.state == ManualVideoUnavailable);
        puts("Manual video protocol and update-state checks passed");
    }
    return 0;
}
