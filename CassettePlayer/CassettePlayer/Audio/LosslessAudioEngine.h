#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

typedef NS_ENUM(NSInteger, AudioEngineState) {
    AudioEngineStateStopped = 0,
    AudioEngineStatePlaying,
    AudioEngineStatePaused
};

@class LosslessAudioEngine;

@protocol LosslessAudioEngineDelegate <NSObject>
@optional
- (void)audioEngineDidFinishPlayingTrack:(LosslessAudioEngine *)engine;
- (void)audioEngine:(LosslessAudioEngine *)engine didUpdatePosition:(NSTimeInterval)position duration:(NSTimeInterval)duration;
- (void)audioEngine:(LosslessAudioEngine *)engine didEncounterError:(NSError *)error;
@end

@interface LosslessAudioEngine : NSObject

@property (nonatomic, weak) id<LosslessAudioEngineDelegate> delegate;
@property (nonatomic, readonly) AudioEngineState state;
@property (nonatomic, readonly) NSTimeInterval currentTime;
@property (nonatomic, readonly) NSTimeInterval duration;
@property (nonatomic, readonly) double sampleRate;
@property (nonatomic, readonly) UInt32 bitsPerSample;
@property (nonatomic, readonly) UInt32 channels;
@property (nonatomic, readonly, copy) NSString *codecName;

// Real-time audio levels (0.0 to 1.0) for Cassette VU Meters
@property (nonatomic, readonly) float leftLevel;
@property (nonatomic, readonly) float rightLevel;

// 10-band EQ gains in dB (-12.0 to +12.0)
@property (nonatomic, assign) BOOL eqEnabled;
@property (nonatomic, strong, readonly) NSArray<NSNumber *> *eqBandFrequencies;

- (BOOL)loadURL:(NSURL *)url error:(NSError **)error;
- (void)play;
- (void)pause;
- (void)stop;
- (void)seekToTime:(NSTimeInterval)time;

- (void)setEQGain:(float)gainDb forBand:(NSUInteger)bandIndex;
- (float)eqGainForBand:(NSUInteger)bandIndex;
- (void)applyEQPreset:(NSString *)presetName;
+ (NSArray<NSString *> *)availableEQPresets;

@end
