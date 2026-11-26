#import "LosslessAudioEngine.h"
#import <AVFoundation/AVFoundation.h>
#import <libkern/OSAtomic.h>
#import <pthread.h>
#import <math.h>
#include "dr_flac.h"

#define RING_BUFFER_FRAMES 65536
#define DECODE_CHUNK_FRAMES 4096

typedef NS_ENUM(NSInteger, DecoderType) {
    DecoderTypeNone = 0,
    DecoderTypeFLAC,
    DecoderTypeCoreAudio
};

@interface LosslessAudioEngine () {
    AUGraph _auGraph;
    AUNode _eqNode;
    AUNode _ioNode;
    AudioUnit _eqUnit;
    AudioUnit _ioUnit;
    BOOL _graphInitialized;

    DecoderType _decoderType;
    drflac *_flac;
    ExtAudioFileRef _extAudioFile;

    double _fileSampleRate;
    UInt32 _fileChannels;
    UInt32 _fileBitsPerSample;
    SInt64 _totalFrames;
    SInt64 _decodedFrameCursor;
    SInt64 _playedFrameCursor;

    // Interleaved stereo Float32 ring buffer
    float *_ringBuffer;
    volatile uint32_t _ringReadIdx;
    volatile uint32_t _ringWriteIdx;
    volatile uint32_t _ringAvailableFrames;
    pthread_mutex_t _decodeMutex;
    BOOL _eofReached;
    BOOL _eofNotified;

    dispatch_source_t _decodeTimer;
    dispatch_queue_t _decodeQueue;
    NSTimer *_progressTimer;

    float _leftLevel;
    float _rightLevel;
    float _eqGains[10];
}

@property (nonatomic, readwrite) AudioEngineState state;
@property (nonatomic, readwrite, copy) NSString *codecName;

@end

@implementation LosslessAudioEngine

- (instancetype)init {
    self = [super init];
    if (self) {
        _ringBuffer = (float *)calloc(RING_BUFFER_FRAMES * 2, sizeof(float));
        pthread_mutex_init(&_decodeMutex, NULL);
        _decodeQueue = dispatch_queue_create("com.cassetteplayer.decode", DISPATCH_QUEUE_SERIAL);
        _eqEnabled = YES;
        _eqBandFrequencies = @[@32, @64, @125, @250, @500, @1000, @2000, @4000, @8000, @16000];
        for (int i = 0; i < 10; i++) {
            _eqGains[i] = 0.0f;
        }
        [self setupNotifications];
    }
    return self;
}

- (void)dealloc {
    [self stop];
    [self teardownAUGraph];
    [self closeDecoders];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    pthread_mutex_destroy(&_decodeMutex);
    if (_ringBuffer) {
        free(_ringBuffer);
        _ringBuffer = NULL;
    }
}

- (void)setupNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleAudioInterruption:)
                                                 name:AVAudioSessionInterruptionNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleRouteChange:)
                                                 name:AVAudioSessionRouteChangeNotification
                                               object:nil];
}

- (void)handleAudioInterruption:(NSNotification *)notification {
    AVAudioSessionInterruptionType type = [notification.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    if (type == AVAudioSessionInterruptionTypeBegan) {
        if (self.state == AudioEngineStatePlaying) {
            [self pause];
        }
    } else if (type == AVAudioSessionInterruptionTypeEnded) {
        AVAudioSessionInterruptionOptions opts = [notification.userInfo[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue];
        if (opts & AVAudioSessionInterruptionOptionShouldResume) {
            [self play];
        }
    }
}

- (void)handleRouteChange:(NSNotification *)notification {
    AVAudioSessionRouteChangeReason reason = [notification.userInfo[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue];
    if (reason == AVAudioSessionRouteChangeReasonOldDeviceUnavailable) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.state == AudioEngineStatePlaying) {
                [self pause];
            }
        });
    }
}

#pragma mark - AUGraph Setup

- (BOOL)setupAUGraphWithSampleRate:(double)sampleRate error:(NSError **)error {
    [self teardownAUGraph];

    OSStatus status = NewAUGraph(&_auGraph);
    if (status != noErr) {
        if (error) *error = [NSError errorWithDomain:@"LosslessAudioEngine" code:status userInfo:@{NSLocalizedDescriptionKey: @"Failed to create AUGraph"}];
        return NO;
    }

    AudioComponentDescription ioDesc = {0};
    ioDesc.componentType = kAudioUnitType_Output;
    ioDesc.componentSubType = kAudioUnitSubType_RemoteIO;
    ioDesc.componentManufacturer = kAudioUnitManufacturer_Apple;

    AudioComponentDescription eqDesc = {0};
    eqDesc.componentType = kAudioUnitType_Effect;
    eqDesc.componentSubType = kAudioUnitSubType_NBandEQ;
    eqDesc.componentManufacturer = kAudioUnitManufacturer_Apple;

    status = AUGraphAddNode(_auGraph, &eqDesc, &_eqNode);
    if (status != noErr) return NO;
    status = AUGraphAddNode(_auGraph, &ioDesc, &_ioNode);
    if (status != noErr) return NO;

    status = AUGraphOpen(_auGraph);
    if (status != noErr) return NO;

    status = AUGraphNodeInfo(_auGraph, _eqNode, NULL, &_eqUnit);
    if (status != noErr) return NO;
    status = AUGraphNodeInfo(_auGraph, _ioNode, NULL, &_ioUnit);
    if (status != noErr) return NO;

    // Stream format: 32-bit Float Stereo Interleaved (native to CoreAudio & optimal for lossless headroom)
    AudioStreamBasicDescription asbd = {0};
    asbd.mSampleRate = sampleRate;
    asbd.mFormatID = kAudioFormatLinearPCM;
    asbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    asbd.mBitsPerChannel = 32;
    asbd.mChannelsPerFrame = 2;
    asbd.mFramesPerPacket = 1;
    asbd.mBytesPerFrame = sizeof(float) * 2;
    asbd.mBytesPerPacket = sizeof(float) * 2;

    // Configure NBandEQ (10 bands)
    UInt32 numBands = 10;
    AudioUnitSetProperty(_eqUnit, kAUNBandEQProperty_NumberOfBands, kAudioUnitScope_Global, 0, &numBands, sizeof(numBands));
    AudioUnitSetProperty(_eqUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &asbd, sizeof(asbd));
    AudioUnitSetProperty(_eqUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &asbd, sizeof(asbd));

    for (UInt32 i = 0; i < numBands; i++) {
        float freq = [self.eqBandFrequencies[i] floatValue];
        AudioUnitSetParameter(_eqUnit, kAUNBandEQParam_FilterType + i, kAudioUnitScope_Global, 0, kAUNBandEQFilterType_Parametric, 0);
        AudioUnitSetParameter(_eqUnit, kAUNBandEQParam_Frequency + i, kAudioUnitScope_Global, 0, freq, 0);
        AudioUnitSetParameter(_eqUnit, kAUNBandEQParam_Bandwidth + i, kAudioUnitScope_Global, 0, 1.0f, 0);
        AudioUnitSetParameter(_eqUnit, kAUNBandEQParam_BypassBand + i, kAudioUnitScope_Global, 0, _eqEnabled ? 0.0f : 1.0f, 0);
        AudioUnitSetParameter(_eqUnit, kAUNBandEQParam_Gain + i, kAudioUnitScope_Global, 0, _eqGains[i], 0);
    }

    AudioUnitSetProperty(_ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &asbd, sizeof(asbd));

    AURenderCallbackStruct cb;
    cb.inputProc = AudioRenderCallback;
    cb.inputProcRefCon = (__bridge void *)self;
    status = AUGraphSetNodeInputCallback(_auGraph, _eqNode, 0, &cb);
    if (status != noErr) return NO;

    status = AUGraphConnectNodeInput(_auGraph, _eqNode, 0, _ioNode, 0);
    if (status != noErr) return NO;

    status = AUGraphInitialize(_auGraph);
    if (status != noErr) {
        if (error) *error = [NSError errorWithDomain:@"LosslessAudioEngine" code:status userInfo:@{NSLocalizedDescriptionKey: @"Failed to initialize AUGraph"}];
        return NO;
    }

    _graphInitialized = YES;
    return YES;
}

- (void)teardownAUGraph {
    if (_auGraph) {
        AUGraphStop(_auGraph);
        AUGraphUninitialize(_auGraph);
        AUGraphClose(_auGraph);
        DisposeAUGraph(_auGraph);
        _auGraph = NULL;
        _eqUnit = NULL;
        _ioUnit = NULL;
        _graphInitialized = NO;
    }
}

#pragma mark - Loading & Decoding

- (void)closeDecoders {
    pthread_mutex_lock(&_decodeMutex);
    if (_flac) {
        drflac_close(_flac);
        _flac = NULL;
    }
    if (_extAudioFile) {
        ExtAudioFileDispose(_extAudioFile);
        _extAudioFile = NULL;
    }
    _decoderType = DecoderTypeNone;
    pthread_mutex_unlock(&_decodeMutex);
}

- (BOOL)loadURL:(NSURL *)url error:(NSError **)error {
    [self stop];
    [self closeDecoders];

    if (!url) {
        if (error) *error = [NSError errorWithDomain:@"LosslessAudioEngine" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL"}];
        return NO;
    }

    NSString *ext = url.pathExtension.lowercaseString;
    BOOL loaded = NO;

    if ([ext isEqualToString:@"flac"]) {
        loaded = [self openFLACAtURL:url error:error];
    } else {
        loaded = [self openCoreAudioAtURL:url error:error];
    }

    if (!loaded) {
        return NO;
    }

    // Match hardware sample rate up to 48kHz (iPhone 4S DAC native max is 48kHz)
    double targetRate = _fileSampleRate > 0 ? _fileSampleRate : 44100.0;
    [[AVAudioSession sharedInstance] setPreferredSampleRate:MIN(targetRate, 48000.0) error:nil];

    if (![self setupAUGraphWithSampleRate:targetRate error:error]) {
        [self closeDecoders];
        return NO;
    }

    _ringReadIdx = 0;
    _ringWriteIdx = 0;
    _ringAvailableFrames = 0;
    _decodedFrameCursor = 0;
    _playedFrameCursor = 0;
    _eofReached = NO;
    _eofNotified = NO;

    // Pre-fill ring buffer before playback starts
    [self fillRingBuffer];

    return YES;
}

- (BOOL)openFLACAtURL:(NSURL *)url error:(NSError **)error {
    const char *path = [url.path UTF8String];
    if (!path) return NO;

    drflac *flac = drflac_open_file(path, NULL);
    if (!flac) {
        if (error) *error = [NSError errorWithDomain:@"LosslessAudioEngine" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to open FLAC file"}];
        return NO;
    }

    _flac = flac;
    _decoderType = DecoderTypeFLAC;
    _fileSampleRate = (double)flac->sampleRate;
    _fileChannels = flac->channels;
    _fileBitsPerSample = flac->bitsPerSample;
    _totalFrames = (SInt64)flac->totalPCMFrameCount;
    self.codecName = @"FLAC";
    return YES;
}

- (BOOL)openCoreAudioAtURL:(NSURL *)url error:(NSError **)error {
    ExtAudioFileRef extFile = NULL;
    OSStatus status = ExtAudioFileOpenURL((__bridge CFURLRef)url, &extFile);
    if (status != noErr || !extFile) {
        if (error) *error = [NSError errorWithDomain:@"LosslessAudioEngine" code:status userInfo:@{NSLocalizedDescriptionKey: @"Failed to open audio file"}];
        return NO;
    }

    AudioStreamBasicDescription fileFormat = {0};
    UInt32 propSize = sizeof(fileFormat);
    status = ExtAudioFileGetProperty(extFile, kExtAudioFileProperty_FileDataFormat, &propSize, &fileFormat);
    if (status != noErr) {
        ExtAudioFileDispose(extFile);
        return NO;
    }

    SInt64 totalFrames = 0;
    propSize = sizeof(totalFrames);
    ExtAudioFileGetProperty(extFile, kExtAudioFileProperty_FileLengthFrames, &propSize, &totalFrames);

    // Client format: 32-bit Float Stereo Interleaved at file's native sample rate
    AudioStreamBasicDescription clientFormat = {0};
    clientFormat.mSampleRate = fileFormat.mSampleRate;
    clientFormat.mFormatID = kAudioFormatLinearPCM;
    clientFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    clientFormat.mBitsPerChannel = 32;
    clientFormat.mChannelsPerFrame = 2;
    clientFormat.mFramesPerPacket = 1;
    clientFormat.mBytesPerFrame = sizeof(float) * 2;
    clientFormat.mBytesPerPacket = sizeof(float) * 2;

    status = ExtAudioFileSetProperty(extFile, kExtAudioFileProperty_ClientDataFormat, sizeof(clientFormat), &clientFormat);
    if (status != noErr) {
        ExtAudioFileDispose(extFile);
        return NO;
    }

    _extAudioFile = extFile;
    _decoderType = DecoderTypeCoreAudio;
    _fileSampleRate = fileFormat.mSampleRate;
    _fileChannels = fileFormat.mChannelsPerFrame;
    _fileBitsPerSample = fileFormat.mBitsPerChannel > 0 ? fileFormat.mBitsPerChannel : 16;
    _totalFrames = totalFrames;

    if (fileFormat.mFormatID == kAudioFormatAppleLossless) {
        self.codecName = @"ALAC";
        // ALAC bit depth is encoded in mFormatFlags (1=16, 2=20, 3=24, 4=32)
        if (fileFormat.mFormatFlags == kAppleLosslessFormatFlag_24BitSourceData) _fileBitsPerSample = 24;
        else if (fileFormat.mFormatFlags == kAppleLosslessFormatFlag_20BitSourceData) _fileBitsPerSample = 20;
        else if (fileFormat.mFormatFlags == kAppleLosslessFormatFlag_32BitSourceData) _fileBitsPerSample = 32;
        else _fileBitsPerSample = 16;
    } else if (fileFormat.mFormatID == kAudioFormatLinearPCM) {
        self.codecName = @"PCM";
    } else {
        self.codecName = url.pathExtension.uppercaseString ?: @"AUDIO";
    }
    return YES;
}

- (void)fillRingBuffer {
    pthread_mutex_lock(&_decodeMutex);
    if (_decoderType == DecoderTypeNone || _eofReached) {
        pthread_mutex_unlock(&_decodeMutex);
        return;
    }

    uint32_t freeFrames = RING_BUFFER_FRAMES - _ringAvailableFrames;
    if (freeFrames < DECODE_CHUNK_FRAMES) {
        pthread_mutex_unlock(&_decodeMutex);
        return;
    }

    float tempBuf[DECODE_CHUNK_FRAMES * 2];
    while (freeFrames >= DECODE_CHUNK_FRAMES && !_eofReached) {
        UInt32 framesRead = 0;

        if (_decoderType == DecoderTypeFLAC && _flac) {
            if (_fileChannels == 2) {
                framesRead = (UInt32)drflac_read_pcm_frames_f32(_flac, DECODE_CHUNK_FRAMES, tempBuf);
            } else if (_fileChannels == 1) {
                float monoBuf[DECODE_CHUNK_FRAMES];
                framesRead = (UInt32)drflac_read_pcm_frames_f32(_flac, DECODE_CHUNK_FRAMES, monoBuf);
                for (UInt32 i = 0; i < framesRead; i++) {
                    tempBuf[i * 2] = monoBuf[i];
                    tempBuf[i * 2 + 1] = monoBuf[i];
                }
            } else {
                // Multi-channel downmix first 2 channels
                float multiBuf[DECODE_CHUNK_FRAMES * 8];
                UInt32 ch = MIN(_fileChannels, 8);
                framesRead = (UInt32)drflac_read_pcm_frames_f32(_flac, DECODE_CHUNK_FRAMES, multiBuf);
                for (UInt32 i = 0; i < framesRead; i++) {
                    tempBuf[i * 2] = multiBuf[i * ch];
                    tempBuf[i * 2 + 1] = multiBuf[i * ch + 1];
                }
            }
        } else if (_decoderType == DecoderTypeCoreAudio && _extAudioFile) {
            AudioBufferList abl;
            abl.mNumberBuffers = 1;
            abl.mBuffers[0].mNumberChannels = 2;
            abl.mBuffers[0].mDataByteSize = DECODE_CHUNK_FRAMES * sizeof(float) * 2;
            abl.mBuffers[0].mData = tempBuf;

            framesRead = DECODE_CHUNK_FRAMES;
            OSStatus status = ExtAudioFileRead(_extAudioFile, &framesRead, &abl);
            if (status != noErr) {
                framesRead = 0;
            }
        }

        if (framesRead == 0) {
            _eofReached = YES;
            break;
        }

        // Copy into circular ring buffer
        uint32_t writePos = _ringWriteIdx;
        uint32_t firstPart = MIN(framesRead, RING_BUFFER_FRAMES - writePos);
        memcpy(&_ringBuffer[writePos * 2], tempBuf, firstPart * 2 * sizeof(float));
        if (framesRead > firstPart) {
            memcpy(&_ringBuffer[0], &tempBuf[firstPart * 2], (framesRead - firstPart) * 2 * sizeof(float));
        }

        _ringWriteIdx = (writePos + framesRead) % RING_BUFFER_FRAMES;
        OSAtomicAdd32((int32_t)framesRead, (volatile int32_t *)&_ringAvailableFrames);
        _decodedFrameCursor += framesRead;
        freeFrames -= framesRead;
    }

    pthread_mutex_unlock(&_decodeMutex);
}

#pragma mark - Transport

- (void)play {
    if (!_graphInitialized || _decoderType == DecoderTypeNone) return;
    if (self.state == AudioEngineStatePlaying) return;

    [[AVAudioSession sharedInstance] setActive:YES error:nil];
    AUGraphStart(_auGraph);
    self.state = AudioEngineStatePlaying;

    [self startDecodeLoop];
    [self startProgressTimer];
}

- (void)pause {
    if (self.state != AudioEngineStatePlaying) return;
    if (_auGraph) {
        AUGraphStop(_auGraph);
    }
    self.state = AudioEngineStatePaused;
    _leftLevel = 0.0f;
    _rightLevel = 0.0f;
    [self stopDecodeLoop];
    [self stopProgressTimer];
}

- (void)stop {
    if (_auGraph) {
        AUGraphStop(_auGraph);
    }
    self.state = AudioEngineStateStopped;
    _leftLevel = 0.0f;
    _rightLevel = 0.0f;
    [self stopDecodeLoop];
    [self stopProgressTimer];
}

- (void)seekToTime:(NSTimeInterval)time {
    if (_decoderType == DecoderTypeNone || _fileSampleRate <= 0) return;
    SInt64 targetFrame = (SInt64)(MAX(0.0, time) * _fileSampleRate);
    if (_totalFrames > 0) {
        targetFrame = MIN(targetFrame, _totalFrames);
    }

    pthread_mutex_lock(&_decodeMutex);
    if (_decoderType == DecoderTypeFLAC && _flac) {
        drflac_seek_to_pcm_frame(_flac, (drflac_uint64)targetFrame);
    } else if (_decoderType == DecoderTypeCoreAudio && _extAudioFile) {
        ExtAudioFileSeek(_extAudioFile, targetFrame);
    }
    _ringReadIdx = 0;
    _ringWriteIdx = 0;
    _ringAvailableFrames = 0;
    _decodedFrameCursor = targetFrame;
    _playedFrameCursor = targetFrame;
    _eofReached = NO;
    _eofNotified = NO;
    pthread_mutex_unlock(&_decodeMutex);

    [self fillRingBuffer];
}

#pragma mark - Timers

- (void)startDecodeLoop {
    [self stopDecodeLoop];
    _decodeTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _decodeQueue);
    dispatch_source_set_timer(_decodeTimer, DISPATCH_TIME_NOW, (uint64_t)(25 * NSEC_PER_MSEC), (uint64_t)(5 * NSEC_PER_MSEC));
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_decodeTimer, ^{
        [weakSelf fillRingBuffer];
    });
    dispatch_resume(_decodeTimer);
}

- (void)stopDecodeLoop {
    if (_decodeTimer) {
        dispatch_source_cancel(_decodeTimer);
        _decodeTimer = nil;
    }
}

- (void)startProgressTimer {
    [self stopProgressTimer];
    _progressTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                      target:self
                                                    selector:@selector(onProgressTick)
                                                    userInfo:nil
                                                     repeats:YES];
}

- (void)stopProgressTimer {
    [_progressTimer invalidate];
    _progressTimer = nil;
}

- (void)onProgressTick {
    if ([self.delegate respondsToSelector:@selector(audioEngine:didUpdatePosition:duration:)]) {
        [self.delegate audioEngine:self didUpdatePosition:self.currentTime duration:self.duration];
    }
}

#pragma mark - Real-time Audio Render Callback

static OSStatus AudioRenderCallback(void *inRefCon,
                                    AudioUnitRenderActionFlags *ioActionFlags,
                                    const AudioTimeStamp *inTimeStamp,
                                    UInt32 inBusNumber,
                                    UInt32 inNumberFrames,
                                    AudioBufferList *ioData) {
    LosslessAudioEngine *engine = (__bridge LosslessAudioEngine *)inRefCon;
    float *outBuf = (float *)ioData->mBuffers[0].mData;

    uint32_t avail = engine->_ringAvailableFrames;
    uint32_t toRead = MIN(inNumberFrames, avail);

    if (toRead > 0) {
        uint32_t readPos = engine->_ringReadIdx;
        uint32_t firstPart = MIN(toRead, RING_BUFFER_FRAMES - readPos);
        memcpy(outBuf, &engine->_ringBuffer[readPos * 2], firstPart * 2 * sizeof(float));
        if (toRead > firstPart) {
            memcpy(&outBuf[firstPart * 2], &engine->_ringBuffer[0], (toRead - firstPart) * 2 * sizeof(float));
        }

        engine->_ringReadIdx = (readPos + toRead) % RING_BUFFER_FRAMES;
        OSAtomicAdd32(-(int32_t)toRead, (volatile int32_t *)&engine->_ringAvailableFrames);
        engine->_playedFrameCursor += toRead;

        // Compute RMS levels for Cassette VU Meters
        float sumL = 0.0f, sumR = 0.0f;
        for (uint32_t i = 0; i < toRead; i++) {
            float l = outBuf[i * 2];
            float r = outBuf[i * 2 + 1];
            sumL += l * l;
            sumR += r * r;
        }
        float rmsL = sqrtf(sumL / (float)toRead);
        float rmsR = sqrtf(sumR / (float)toRead);
        // Smooth + boost slightly for natural analog VU needle feel
        engine->_leftLevel = engine->_leftLevel * 0.65f + MIN(1.0f, rmsL * 2.2f) * 0.35f;
        engine->_rightLevel = engine->_rightLevel * 0.65f + MIN(1.0f, rmsR * 2.2f) * 0.35f;
    }

    if (toRead < inNumberFrames) {
        memset(&outBuf[toRead * 2], 0, (inNumberFrames - toRead) * 2 * sizeof(float));
        if (engine->_eofReached && engine->_ringAvailableFrames == 0 && !engine->_eofNotified) {
            engine->_eofNotified = YES;
            dispatch_async(dispatch_get_main_queue(), ^{
                [engine stop];
                if ([engine.delegate respondsToSelector:@selector(audioEngineDidFinishPlayingTrack:)]) {
                    [engine.delegate audioEngineDidFinishPlayingTrack:engine];
                }
            });
        }
    }

    return noErr;
}

#pragma mark - Properties

- (NSTimeInterval)currentTime {
    if (_fileSampleRate <= 0) return 0;
    return (NSTimeInterval)_playedFrameCursor / _fileSampleRate;
}

- (NSTimeInterval)duration {
    if (_fileSampleRate <= 0 || _totalFrames <= 0) return 0;
    return (NSTimeInterval)_totalFrames / _fileSampleRate;
}

- (double)sampleRate {
    return _fileSampleRate;
}

- (UInt32)bitsPerSample {
    return _fileBitsPerSample;
}

- (UInt32)channels {
    return _fileChannels;
}

- (float)leftLevel {
    return _leftLevel;
}

- (float)rightLevel {
    return _rightLevel;
}

#pragma mark - 10-Band Equalizer

- (void)setEqEnabled:(BOOL)eqEnabled {
    _eqEnabled = eqEnabled;
    if (_eqUnit) {
        for (UInt32 i = 0; i < 10; i++) {
            AudioUnitSetParameter(_eqUnit, kAUNBandEQParam_BypassBand + i, kAudioUnitScope_Global, 0, eqEnabled ? 0.0f : 1.0f, 0);
        }
    }
}

- (void)setEQGain:(float)gainDb forBand:(NSUInteger)bandIndex {
    if (bandIndex >= 10) return;
    float clamped = MAX(-12.0f, MIN(12.0f, gainDb));
    _eqGains[bandIndex] = clamped;
    if (_eqUnit) {
        AudioUnitSetParameter(_eqUnit, kAUNBandEQParam_Gain + (AudioUnitParameterID)bandIndex, kAudioUnitScope_Global, 0, clamped, 0);
    }
}

- (float)eqGainForBand:(NSUInteger)bandIndex {
    if (bandIndex >= 10) return 0.0f;
    return _eqGains[bandIndex];
}

+ (NSArray<NSString *> *)availableEQPresets {
    return @[@"Flat (Pure)", @"Warm Cassette", @"Bass Boost", @"Vocal", @"Jazz", @"Rock", @"Acoustic"];
}

- (void)applyEQPreset:(NSString *)presetName {
    NSDictionary *presets = @{
        @"Flat (Pure)":   @[@0, @0, @0, @0, @0, @0, @0, @0, @0, @0],
        @"Warm Cassette": @[@2.5, @3.0, @2.0, @1.0, @0.0, @-0.5, @-1.0, @-1.5, @-2.5, @-3.5],
        @"Bass Boost":    @[@6.0, @5.0, @4.0, @2.5, @1.0, @0, @0, @0, @0, @0],
        @"Vocal":         @[@-2.0, @-1.0, @0, @2.0, @4.0, @4.5, @3.0, @1.5, @0, @-1.0],
        @"Jazz":          @[@3.0, @2.0, @1.0, @1.5, @-1.0, @-1.0, @0, @1.5, @2.5, @3.0],
        @"Rock":          @[@4.5, @3.5, @2.0, @0.5, @-1.0, @-0.5, @1.5, @3.0, @4.0, @4.5],
        @"Acoustic":      @[@3.5, @2.5, @1.5, @1.0, @1.5, @1.0, @2.0, @3.0, @3.5, @2.0]
    };
    NSArray *gains = presets[presetName] ?: presets[@"Flat (Pure)"];
    for (NSUInteger i = 0; i < 10; i++) {
        [self setEQGain:[gains[i] floatValue] forBand:i];
    }
}

@end
