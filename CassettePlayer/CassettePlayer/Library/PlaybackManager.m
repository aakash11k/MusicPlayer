#import "PlaybackManager.h"
#import "MusicLibrary.h"
#import <MediaPlayer/MediaPlayer.h>

NSString * const PlaybackDidChangeTrackNotification = @"PlaybackDidChangeTrackNotification";
NSString * const PlaybackDidChangeStateNotification = @"PlaybackDidChangeStateNotification";
NSString * const PlaybackDidUpdateQueueNotification = @"PlaybackDidUpdateQueueNotification";

@interface PlaybackManager ()
@property (nonatomic, strong, readwrite) LosslessAudioEngine *engine;
@property (nonatomic, strong, readwrite) TrackItem *currentTrack;
@property (nonatomic, strong) NSMutableArray<TrackItem *> *mutableQueue;
@property (nonatomic, strong) NSArray<TrackItem *> *originalQueue;
@property (nonatomic, assign, readwrite) NSInteger currentIndex;
@end

@implementation PlaybackManager

+ (instancetype)sharedManager {
    static PlaybackManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[PlaybackManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _engine = [[LosslessAudioEngine alloc] init];
        _engine.delegate = self;
        _mutableQueue = [NSMutableArray array];
        _currentIndex = -1;
        [self setupRemoteCommands];
    }
    return self;
}

- (NSArray<TrackItem *> *)queue {
    return [self.mutableQueue copy];
}

#pragma mark - Playback Control

- (void)playTrack:(TrackItem *)track inQueue:(NSArray<TrackItem *> *)tracks {
    if (!track) return;
    self.originalQueue = tracks.count > 0 ? [tracks copy] : @[track];
    self.mutableQueue = [self.originalQueue mutableCopy];

    if (self.shuffleEnabled && self.mutableQueue.count > 1) {
        [self applyShuffleKeepingTrack:track];
    }

    NSInteger idx = [self.mutableQueue indexOfObject:track];
    self.currentIndex = (idx != NSNotFound) ? idx : 0;
    [self loadAndPlayCurrentIndex];
}

- (void)playQueueIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.mutableQueue.count) return;
    self.currentIndex = index;
    [self loadAndPlayCurrentIndex];
}

- (void)loadAndPlayCurrentIndex {
    if (self.currentIndex < 0 || self.currentIndex >= (NSInteger)self.mutableQueue.count) return;
    TrackItem *track = self.mutableQueue[self.currentIndex];
    self.currentTrack = track;

    NSError *err = nil;
    if ([self.engine loadURL:track.fileURL error:&err]) {
        [self.engine play];
        [[MusicLibrary sharedLibrary] recordPlayForTrack:track];
        [self updateNowPlayingInfo];
    } else {
        NSLog(@"Failed to load track %@: %@", track.title, err);
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:PlaybackDidChangeTrackNotification object:self];
    [[NSNotificationCenter defaultCenter] postNotificationName:PlaybackDidChangeStateNotification object:self];
    [[NSNotificationCenter defaultCenter] postNotificationName:PlaybackDidUpdateQueueNotification object:self];
}

- (void)togglePlayPause {
    if (self.engine.state == AudioEngineStatePlaying) {
        [self pause];
    } else if (self.engine.state == AudioEngineStatePaused) {
        [self play];
    } else if (self.currentTrack) {
        [self loadAndPlayCurrentIndex];
    }
}

- (void)play {
    [self.engine play];
    [self updateNowPlayingInfo];
    [[NSNotificationCenter defaultCenter] postNotificationName:PlaybackDidChangeStateNotification object:self];
}

- (void)pause {
    [self.engine pause];
    [self updateNowPlayingInfo];
    [[NSNotificationCenter defaultCenter] postNotificationName:PlaybackDidChangeStateNotification object:self];
}

- (void)nextTrack {
    if (self.mutableQueue.count == 0) return;
    if (self.repeatMode == RepeatModeOne) {
        [self seekToTime:0];
        [self play];
        return;
    }

    NSInteger nextIdx = self.currentIndex + 1;
    if (nextIdx >= (NSInteger)self.mutableQueue.count) {
        if (self.repeatMode == RepeatModeAll) {
            nextIdx = 0;
        } else {
            [self.engine stop];
            [[NSNotificationCenter defaultCenter] postNotificationName:PlaybackDidChangeStateNotification object:self];
            return;
        }
    }
    self.currentIndex = nextIdx;
    [self loadAndPlayCurrentIndex];
}

- (void)previousTrack {
    if (self.mutableQueue.count == 0) return;
    if (self.engine.currentTime > 3.0) {
        [self seekToTime:0];
        return;
    }

    NSInteger prevIdx = self.currentIndex - 1;
    if (prevIdx < 0) {
        prevIdx = (self.repeatMode == RepeatModeAll) ? ((NSInteger)self.mutableQueue.count - 1) : 0;
    }
    self.currentIndex = prevIdx;
    [self loadAndPlayCurrentIndex];
}

- (void)seekToTime:(NSTimeInterval)time {
    [self.engine seekToTime:time];
    [self updateNowPlayingInfo];
}

- (void)seekByDelta:(NSTimeInterval)delta {
    NSTimeInterval target = MAX(0.0, MIN(self.engine.duration, self.engine.currentTime + delta));
    [self seekToTime:target];
}

#pragma mark - Shuffle & Queue

- (void)setShuffleEnabled:(BOOL)shuffleEnabled {
    _shuffleEnabled = shuffleEnabled;
    if (self.mutableQueue.count <= 1) return;

    TrackItem *current = self.currentTrack;
    if (shuffleEnabled) {
        [self applyShuffleKeepingTrack:current];
    } else if (self.originalQueue.count > 0) {
        self.mutableQueue = [self.originalQueue mutableCopy];
    }
    if (current) {
        NSInteger idx = [self.mutableQueue indexOfObject:current];
        if (idx != NSNotFound) self.currentIndex = idx;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:PlaybackDidUpdateQueueNotification object:self];
}

- (void)applyShuffleKeepingTrack:(TrackItem *)track {
    NSMutableArray *rest = [self.mutableQueue mutableCopy];
    if (track) [rest removeObject:track];
    for (NSUInteger i = rest.count; i > 1; i--) {
        NSUInteger j = arc4random_uniform((uint32_t)i);
        [rest exchangeObjectAtIndex:i - 1 withObjectAtIndex:j];
    }
    [self.mutableQueue removeAllObjects];
    if (track) [self.mutableQueue addObject:track];
    [self.mutableQueue addObjectsFromArray:rest];
}

- (void)playNextInQueue:(TrackItem *)track {
    if (!track) return;
    if (self.mutableQueue.count == 0) {
        [self playTrack:track inQueue:@[track]];
        return;
    }
    NSInteger insertIdx = MIN((NSInteger)self.mutableQueue.count, self.currentIndex + 1);
    [self.mutableQueue insertObject:track atIndex:insertIdx];
    [[NSNotificationCenter defaultCenter] postNotificationName:PlaybackDidUpdateQueueNotification object:self];
}

- (void)addToQueue:(TrackItem *)track {
    if (!track) return;
    if (self.mutableQueue.count == 0) {
        [self playTrack:track inQueue:@[track]];
        return;
    }
    [self.mutableQueue addObject:track];
    [[NSNotificationCenter defaultCenter] postNotificationName:PlaybackDidUpdateQueueNotification object:self];
}

- (void)removeTrackFromQueueAtIndex:(NSUInteger)index {
    if (index >= self.mutableQueue.count || (NSInteger)index == self.currentIndex) return;
    [self.mutableQueue removeObjectAtIndex:index];
    if ((NSInteger)index < self.currentIndex) {
        self.currentIndex -= 1;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:PlaybackDidUpdateQueueNotification object:self];
}

#pragma mark - LosslessAudioEngineDelegate

- (void)audioEngineDidFinishPlayingTrack:(LosslessAudioEngine *)engine {
    [self nextTrack];
}

#pragma mark - Lock Screen & Control Center (iOS 9)

- (void)setupRemoteCommands {
    MPRemoteCommandCenter *rcc = [MPRemoteCommandCenter sharedCommandCenter];
    [rcc.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        [self play];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [rcc.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        [self pause];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [rcc.togglePlayPauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        [self togglePlayPause];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [rcc.nextTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        [self nextTrack];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [rcc.previousTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        [self previousTrack];
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    // iOS 9.1+ Lock Screen scrubbing
    if ([rcc respondsToSelector:@selector(changePlaybackPositionCommand)]) {
        [rcc.changePlaybackPositionCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
            MPChangePlaybackPositionCommandEvent *posEvent = (MPChangePlaybackPositionCommandEvent *)event;
            [self seekToTime:posEvent.positionTime];
            return MPRemoteCommandHandlerStatusSuccess;
        }];
    }
}

- (void)updateNowPlayingInfo {
    if (!self.currentTrack) return;
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[MPMediaItemPropertyTitle] = self.currentTrack.title ?: @"Unknown";
    info[MPMediaItemPropertyArtist] = self.currentTrack.artist ?: @"Unknown Artist";
    info[MPMediaItemPropertyAlbumTitle] = self.currentTrack.album ?: @"";
    info[MPMediaItemPropertyPlaybackDuration] = @(self.engine.duration);
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(self.engine.currentTime);
    info[MPNowPlayingInfoPropertyPlaybackRate] = @(self.engine.state == AudioEngineStatePlaying ? 1.0 : 0.0);

    if (self.currentTrack.artwork) {
        MPMediaItemArtwork *art = [[MPMediaItemArtwork alloc] initWithImage:self.currentTrack.artwork];
        info[MPMediaItemPropertyArtwork] = art;
    }

    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = info;
}

@end
