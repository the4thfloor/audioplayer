#import "AudioplayerPlugin.h"
#import <AVKit/AVKit.h>

//#import <audioplayer/audioplayer-Swift.h>
static NSString *const CHANNEL_NAME = @"bz.rxla.flutter/audio";
static FlutterMethodChannel *channel;

static NSMutableDictionary * players;

@interface AudioplayerPlugin()
-(void) pause: (NSString *) playerId;
-(void) stop: (NSString *) playerId;
-(void) seek: (NSString *) playerId time: (CMTime) time;
-(void) onSoundComplete: (NSString *) playerId;
-(void) updateDuration: (NSString *) playerId;
-(void) onTimeInterval: (NSString *) playerId time: (CMTime) time;


@end


@implementation AudioplayerPlugin {
  FlutterResult _result;
  
}
NSMutableSet *timeobservers;
FlutterMethodChannel *_channel;


+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel = [FlutterMethodChannel
                                   methodChannelWithName:CHANNEL_NAME
                                   binaryMessenger:[registrar messenger]];
  AudioplayerPlugin* instance = [[AudioplayerPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
  _channel = channel;
}


- (id)init {
  self = [super init];
  if (self) {
      players = [[NSMutableDictionary alloc] init];
  }
  return self;
}


- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  NSLog(@"iOS => call %@",call.method);
  
  typedef void (^CaseBlock)();
  
  NSString * playerId = call.arguments[@"playerId"];
  NSLog(@"iOS => playerId %@", playerId);
    
  // Squint and this looks like a proper switch!
  NSDictionary *methods = @{
                            @"play":
                              ^{
                                NSLog(@"play!");
                                NSString *url = call.arguments[@"url"];
                                if (url == nil)
                                  result(0);
                                if (call.arguments[@"isLocal"]==nil)
                                  result(0);
                                if (call.arguments[@"volume"]==nil)
                                  result(0);
                                int isLocal = [call.arguments[@"isLocal"]intValue] ;
                                float volume = (float)[call.arguments[@"volume"] doubleValue] ;
                                NSLog(@"isLocal: %d %@",isLocal, call.arguments[@"isLocal"] );
                                NSLog(@"volume: %f %@",volume, call.arguments[@"volume"] );
                                  [self play:playerId url:url isLocal:isLocal volume:volume];
                              },
                            @"pause":
                              ^{
                                NSLog(@"pause");
                                [self pause:playerId];
                              },
                            @"stop":
                              ^{
                                NSLog(@"stop");
                                [self stop:playerId];
                              },
                            @"seek":
                              ^{
                                NSLog(@"seek");
                                if(!call.arguments[@"position"]){
                                  result(0);
                                } else {
                                  double seconds = [call.arguments[@"position"] doubleValue];
                                  NSLog(@"Seeking to: %f seconds", seconds);
                                  [self seek:playerId time:CMTimeMakeWithSeconds(seconds,1)];
                                }
                              }
                            };
  
  CaseBlock c = methods[call.method];
  if (c) c(); else {
    NSLog(@"not implemented");
    result(FlutterMethodNotImplemented);
  }
  result(@(1));
}


- (void)play:(NSString *)playerId url:(NSString *)url isLocal:(int)isLocal volume:(float)volume
{
    NSMutableDictionary *playerInfo = players[playerId];
    AVPlayer *player = playerInfo[@"player"];
    NSMutableSet *observers = playerInfo[@"observers"];
    AVPlayerItem *playerItem;

    NSLog(@"togglePlay %@", url);

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
                        @"isPlaying": @false,
                        @"observers": observers} mutableCopy];
        players[playerId] = playerInfo;

        // stream player position
        CMTime interval = CMTimeMakeWithSeconds(0.2, NSEC_PER_SEC);
        id timeObserver = [player addPeriodicTimeObserverForInterval:interval
                                                               queue:nil
                                                          usingBlock:^(CMTime time)
                                                          {
                                                              //NSLog(@"time interval: %f",CMTimeGetSeconds(time));
                                                              [self onTimeInterval:playerId
                                                                              time:time];
                                                          }];
        [timeobservers addObject:@{@"player": player, @"observer": timeObserver}];


        id anobserver = [[NSNotificationCenter defaultCenter]
                                               addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                                                           object:playerItem
                                                            queue:nil
                                                       usingBlock:^(NSNotification *note)
                                                       {
                                                           [self onSoundComplete:playerId];
                                                       }];
        [observers addObject:anobserver];

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
    [playerInfo setObject:@true forKey:@"isPlaying"];
}



-(void) updateDuration: (NSString *) playerId
{
  NSMutableDictionary * playerInfo = players[playerId];
  AVPlayer *player = playerInfo[@"player"];

  CMTime duration = [[player currentItem] duration ];
  NSLog(@"ios -> updateDuration...%f", CMTimeGetSeconds(duration));
  if(CMTimeGetSeconds(duration)>0){
    NSLog(@"ios -> invokechannel");
   int mseconds= CMTimeGetSeconds(duration)*1000;
    [_channel invokeMethod:@"audio.onDuration" arguments:@{@"playerId": playerId, @"value": @(mseconds)}];
  }
}



-(void) onTimeInterval: (NSString *) playerId
                  time: (CMTime) time {
  int mseconds =  CMTimeGetSeconds(time)*1000;
  [_channel invokeMethod:@"audio.onCurrentPosition" arguments:@{@"playerId": playerId, @"value": @(mseconds)}];
}


-(void) pause: (NSString *) playerId {
  NSMutableDictionary * playerInfo = players[playerId];
  AVPlayer *player = playerInfo[@"player"];

  [ player pause ];
  [playerInfo setObject:@false forKey:@"isPlaying"];
}


-(void) stop: (NSString *) playerId {
  NSMutableDictionary * playerInfo = players[playerId];

  if([playerInfo[@"isPlaying"] boolValue]){
    [ self pause:playerId ];
    [ self seek:playerId time:CMTimeMake(0, 1) ];
    [playerInfo setObject:@false forKey:@"isPlaying"];
    NSLog(@"stop");
  }
}


-(void) seek: (NSString *) playerId
        time: (CMTime) time {
  NSMutableDictionary * playerInfo = players[playerId];
  AVPlayer *player = playerInfo[@"player"];
  [[player currentItem] seekToTime:time];
}


-(void) onSoundComplete: (NSString *) playerId {
  NSLog(@"ios -> onSoundComplete...");
  NSMutableDictionary * playerInfo = players[playerId];
  [playerInfo setObject:@false forKey:@"isPlaying"];
  [ self pause:playerId ];
  [ self seek:playerId time:CMTimeMakeWithSeconds(0,1)];
  [ _channel invokeMethod:@"audio.onComplete" arguments:@{@"playerId": playerId}];
}


-(void)observeValueForKeyPath:(NSString *)keyPath
                     ofObject:(id)object
                       change:(NSDictionary *)change
                      context:(void *)context {
    
  if ([keyPath isEqualToString: @"player.currentItem.status"]) {
    NSString *playerId = (__bridge NSString*)context;
    NSMutableDictionary * playerInfo = players[playerId];
    AVPlayer *player = playerInfo[@"player"];
      
    NSLog(@"player status: %ld",(long)[[player currentItem] status ]);
      
    // Do something with the status…
    if ([[player currentItem] status ] == AVPlayerItemStatusReadyToPlay) {
      [self updateDuration:playerId];
    } else if ([[player currentItem] status ] == AVPlayerItemStatusFailed) {
        [_channel invokeMethod:@"audio.onError" arguments:@{@"playerId": playerId, @"value": @"AVPlayerItemStatus.failed"}];
    }
  } else {
    // Any unrecognized context must belong to super
    [super observeValueForKeyPath:keyPath
                         ofObject:object
                           change:change
                          context:context];
  }
}


- (void)dealloc {
  for (id value in timeobservers)
    [value[@"player"] removeTimeObserver:value[@"observer"]];
  timeobservers = nil;
  
  for (NSString* playerId in players) {
      NSMutableDictionary * playerInfo = players[playerId];
      NSMutableSet * observers = playerInfo[@"observers"];
      for (id ob in observers)
        [[NSNotificationCenter defaultCenter] removeObserver:ob];
  }
  players = nil;
}



@end

