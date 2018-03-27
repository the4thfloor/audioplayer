#import "AudioplayerPlugin.h"
#import <AVKit/AVKit.h>

static NSString *const CHANNEL_NAME = @"bz.rxla.flutter/audio";

@interface AudioplayerPlugin ()
- (void)play:(NSString *)playerId url:(NSString *)url isLocal:(int)isLocal volume:(float)volume;
- (void)pause:(NSString *)playerId;
- (void)stop:(NSString *)playerId;
- (void)seek:(NSString *)playerId time:(CMTime)time;
- (void)onSoundComplete:(NSString *)playerId;
- (void)updateDuration:(NSString *)playerId;
- (void)onTimeInterval:(NSString *)playerId time:(CMTime)time;
- (void)interruption:(NSNotification *)notification;
- (void)routeChange:(NSNotification *)notification;
@end


@implementation AudioplayerPlugin
{
    NSMutableDictionary *players;
    AVAudioSession *audioSession;
}

NSMutableSet *timeobservers;
FlutterMethodChannel *_channel;


+ (void)registerWithRegistrar:(NSObject <FlutterPluginRegistrar> *)registrar
{
    FlutterMethodChannel *channel = [FlutterMethodChannel methodChannelWithName:CHANNEL_NAME binaryMessenger:[registrar messenger]];
    AudioplayerPlugin *instance = [[AudioplayerPlugin alloc] init];
    [registrar addMethodCallDelegate:instance channel:channel];
    _channel = channel;
}

- (id)init
{
    self = [super init];
    if (self)
    {
        players = [[NSMutableDictionary alloc] init];

        audioSession = [AVAudioSession sharedInstance];
        NSError *audioSessionError = nil;
        [audioSession setCategory:AVAudioSessionCategoryPlayback error:&audioSessionError];
        if (audioSessionError)
        {
            NSLog(@"Setting AVAudioSessionCategoryPlayback failed. %@", audioSessionError);
        }

        [[NSNotificationCenter defaultCenter]
                               addObserver:self
                                  selector:@selector(interruption:)
                                      name:AVAudioSessionInterruptionNotification
                                    object:nil];
        [[NSNotificationCenter defaultCenter]
                               addObserver:self
                                  selector:@selector(routeChange:)
                                      name:AVAudioSessionRouteChangeNotification
                                    object:nil];
    }
    return self;
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result
{
    NSLog(@"iOS => call %@", call.method);

    typedef void (^CaseBlock)();

    NSString *playerId = call.arguments[@"playerId"];

  // Squint and this looks like a proper switch!
  NSDictionary *methods = @{
                            @"play":
                              ^{
                                NSString *url = call.arguments[@"url"];
                                  if (url == nil)
                                  {
                                      result(0);
                                  }
                                  if (call.arguments[@"isLocal"] == nil)
                                  {
                                      result(0);
                                  }
                                  if (call.arguments[@"volume"] == nil)
                                  {
                                      result(0);
                                  }
                                  int isLocal = [call.arguments[@"isLocal"] intValue];
                                  float volume = (float) [call.arguments[@"volume"] doubleValue];
                                  [self play:playerId url:url isLocal:isLocal volume:volume];
                              },
                            @"pause":
                              ^{
                                [self pause:playerId];
                              },
                            @"stop":
                              ^{
                                [self stop:playerId];
                              },
                            @"seek":
                              ^{
                                if(!call.arguments[@"position"]){
                                  result(0);
                                } else {
                                  double seconds = [call.arguments[@"position"] doubleValue];
                                  [self seek:playerId time:CMTimeMakeWithSeconds(seconds,1)];
                                }
                              },
                            @"volume":
                            ^{
                                if(!call.arguments[@"volume"]){
                                    result(0);
                                } else {
                                    float volume = (float) [call.arguments[@"volume"] doubleValue];
                                    [self volume:playerId volume:volume];
                                }
                            }
                            };

    CaseBlock c = methods[call.method];
    if (c)
    {
        c();
    }
    else
    {
        NSLog(@"not implemented");
        result(FlutterMethodNotImplemented);
    }
    result(@(1));
}

- (void)play:(NSString *)playerId url:(NSString *)url isLocal:(int)isLocal volume:(float)volume
{
    NSLog(@"play %@", url);

    NSMutableDictionary *playerInfo = players[playerId];
    AVPlayer *player = playerInfo[@"player"];
    NSMutableSet *observers = playerInfo[@"observers"];
    AVPlayerItem *playerItem;

    if (!playerInfo || ![url isEqualToString:playerInfo[@"url"]])
    {
        if (isLocal)
        {
            playerItem = [[AVPlayerItem alloc] initWithURL:[NSURL fileURLWithPath:url]];
        }
        else
        {
            playerItem = [[AVPlayerItem alloc] initWithURL:[NSURL URLWithString:url]];
        }

        if (observers)
        {
            for (id ob in observers)
            {
                [[NSNotificationCenter defaultCenter] removeObserver:ob];
            }
            [observers removeAllObjects];
        }

        if (player)
        {
            [player pause];
        }

        player = [[AVPlayer alloc] initWithPlayerItem:playerItem];
        observers = [[NSMutableSet alloc] init];
        playerInfo = [@{@"player"   : player,
                        @"url"      : url,
                        @"observers": observers} mutableCopy];
        players[playerId] = playerInfo;

        // stream player position
        CMTime interval = CMTimeMakeWithSeconds(0.2, NSEC_PER_SEC);
        id timeObserver = [player addPeriodicTimeObserverForInterval:interval
                                                               queue:nil
                                                          usingBlock:^(CMTime time)
                                                          {
                                                              [self onTimeInterval:playerId time:time];
                                                          }];
        [timeobservers addObject:@{@"player": player, @"observer": timeObserver}];

        [observers addObject:[[NSNotificationCenter defaultCenter]
                                                    addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                                                                object:playerItem
                                                                 queue:nil
                                                            usingBlock:^(NSNotification *note)
                                                            {
                                                                [self onSoundComplete:playerId];
                                                            }]];

        // is sound ready
        [[player currentItem]
                 addObserver:self
                  forKeyPath:@"player.currentItem.status"
                     options:0
                     context:(__bridge void *) playerId];
    }

    [self updateDuration:playerId];
    [player setVolume:volume];
    [player play];
}

- (void)pause:(NSString *)playerId
{
    NSLog(@"pause player %@", playerId);
    NSMutableDictionary *playerInfo = players[playerId];
    AVPlayer *player = playerInfo[@"player"];
    [player pause];
}

- (void)stop:(NSString *)playerId
{
    NSLog(@"stop player %@", playerId);
    [self pause:playerId];
    [self seek:playerId time:CMTimeMake(0, 1)];
}

- (void)seek:(NSString *)playerId time:(CMTime)time
{
    NSMutableDictionary *playerInfo = players[playerId];
    AVPlayer *player = playerInfo[@"player"];

    [_channel invokeMethod:@"audio.seekToFinished" arguments:@{@"playerId": playerId, @"value": @(NO)}];
    [[player currentItem] seekToTime:time completionHandler:^(BOOL finished)
    {
        CMTime currentTime = [player currentTime];
        int mseconds = CMTimeGetSeconds(currentTime) * 1000;
        [_channel invokeMethod:@"audio.onCurrentPosition" arguments:@{@"playerId": playerId, @"value": @(mseconds)}];
        [_channel invokeMethod:@"audio.seekToFinished" arguments:@{@"playerId": playerId, @"value": @(finished)}];
    }];
}

- (void)volume:(NSString *)playerId volume:(float)volume
{
    NSMutableDictionary *playerInfo = players[playerId];
    AVPlayer *player = playerInfo[@"player"];
    [player setVolume:volume];
}

- (void)updateDuration:(NSString *)playerId
{
    NSMutableDictionary *playerInfo = players[playerId];
    AVPlayer *player = playerInfo[@"player"];

    CMTime duration = [[player currentItem] duration];
    NSLog(@"updateDuration %f - %@", CMTimeGetSeconds(duration), playerId);

    if (CMTimeGetSeconds(duration) > 0)
    {
        int mseconds = CMTimeGetSeconds(duration) * 1000;
        [_channel invokeMethod:@"audio.onDuration"
                     arguments:@{@"playerId": playerId, @"value": @(mseconds)}];
    }
}

- (void)onTimeInterval:(NSString *)playerId time:(CMTime)time
{
    int mseconds = CMTimeGetSeconds(time) * 1000;
    [_channel invokeMethod:@"audio.onCurrentPosition"
                 arguments:@{@"playerId": playerId, @"value": @(mseconds)}];
}

- (void)onSoundComplete:(NSString *)playerId
{
    NSLog(@"onSoundComplete %@", playerId);
    [self pause:playerId];
    [self seek:playerId time:CMTimeMakeWithSeconds(0, 1)];
    [_channel invokeMethod:@"audio.onComplete" arguments:@{@"playerId": playerId}];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath isEqualToString:@"player.currentItem.status"])
    {
        NSString *playerId = (__bridge NSString *) context;
        NSMutableDictionary *playerInfo = players[playerId];
        AVPlayer *player = playerInfo[@"player"];

        NSLog(@"player status: %ld", (long) [[player currentItem] status]);

        // Do something with the status…
        if ([[player currentItem] status] == AVPlayerItemStatusReadyToPlay)
        {
            [self updateDuration:playerId];
        }
        else if ([[player currentItem] status] == AVPlayerItemStatusFailed)
        {
            [_channel invokeMethod:@"audio.onError"
                         arguments:@{@"playerId": playerId,
                                     @"value"   : @"AVPlayerItemStatus.failed"}];
        }
    }
    else
    {
        // Any unrecognized context must belong to super
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)interruption:(NSNotification *)notification
{
    // get the user info dictionary
    NSDictionary *interuptionDict = notification.userInfo;
    // get the AVAudioSessionInterruptionTypeKey enum from the dictionary
    NSInteger interuptionType = [[interuptionDict valueForKey:AVAudioSessionInterruptionTypeKey] integerValue];
    // decide what to do based on interruption type here...
    switch (interuptionType)
    {
        case AVAudioSessionInterruptionTypeBegan:
            NSLog(@"Audio Session Interruption case started.");
            // fork to handling method here...
            // EG:[self handleInterruptionStarted];
            break;

        case AVAudioSessionInterruptionTypeEnded:
            NSLog(@"Audio Session Interruption case ended.");
            // fork to handling method here...
            // EG:[self handleInterruptionEnded];
            break;

        default:
            NSLog(@"Audio Session Interruption Notification case default.");
            break;
    }
}

- (void)routeChange:(NSNotification *)notification
{
    NSDictionary *interuptionDict = notification.userInfo;
    NSInteger routeChangeReason = [[interuptionDict valueForKey:AVAudioSessionRouteChangeReasonKey] integerValue];

    NSLog(@"routeChange: %@", @(routeChangeReason));

    // called at start - also when other audio wants to play
    if (routeChangeReason == AVAudioSessionRouteChangeReasonCategoryChange)
    {
        bool isPlaying = false;

        for (NSMutableDictionary *playerInfo in players)
        {
            AVPlayer *player = playerInfo[@"player"];
            if (player.rate == 1.0)
            {
                isPlaying = true;
                break;
            }
        }

        NSError *error = nil;
        [audioSession setActive:isPlaying error:&error];
        if (error)
        {
            NSLog(@"failed to change audioSession: %@", error);
        }
        else
        {
            NSLog(@"audioSession setActive: %d successful", isPlaying);
        }
    }
}

- (void)dealloc
{
    for (id value in timeobservers)
    {
        [value[@"player"] removeTimeObserver:value[@"observer"]];
    }
    timeobservers = nil;

    for (NSString *playerId in players)
    {
        NSMutableDictionary *playerInfo = players[playerId];
        NSMutableSet *observers = playerInfo[@"observers"];
        for (id ob in observers)
        {
            [[NSNotificationCenter defaultCenter] removeObserver:ob];
        }
    }
    players = nil;
}

@end
