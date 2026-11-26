#import <Foundation/Foundation.h>
#import "TrackItem.h"
#import "LosslessAudioEngine.h"

typedef NS_ENUM(NSInteger, RepeatMode) {
    RepeatModeOff = 0,
    RepeatModeAll,
    RepeatModeOne
};

extern NSString * const PlaybackDidChangeTrackNotification;
extern NSString * const PlaybackDidChangeStateNotification;
extern NSString * const PlaybackDidUpdateQueueNotification;

@interface PlaybackManager : NSObject <LosslessAudioEngineDelegate>

@property (nonatomic, strong, readonly) LosslessAudioEngine *engine;
@property (nonatomic, strong, readonly) TrackItem *currentTrack;
@property (nonatomic, strong, readonly) NSArray<TrackItem *> *queue;
@property (nonatomic, assign, readonly) NSInteger currentIndex;
@property (nonatomic, assign) BOOL shuffleEnabled;
@property (nonatomic, assign) RepeatMode repeatMode;

+ (instancetype)sharedManager;

- (void)playTrack:(TrackItem *)track inQueue:(NSArray<TrackItem *> *)tracks;
- (void)togglePlayPause;
- (void)play;
- (void)pause;
- (void)nextTrack;
- (void)previousTrack;
- (void)seekToTime:(NSTimeInterval)time;
- (void)seekByDelta:(NSTimeInterval)delta;

// Queue management (Spotify-style)
- (void)playNextInQueue:(TrackItem *)track;
- (void)addToQueue:(TrackItem *)track;
- (void)removeTrackFromQueueAtIndex:(NSUInteger)index;
- (void)playQueueIndex:(NSInteger)index;

@end
