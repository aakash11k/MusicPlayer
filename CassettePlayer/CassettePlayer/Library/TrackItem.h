#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface TrackItem : NSObject

@property (nonatomic, copy) NSString *trackId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, copy) NSString *album;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, copy) NSString *codec; // @"FLAC", @"ALAC", @"PCM"
@property (nonatomic, assign) double sampleRate;
@property (nonatomic, assign) UInt32 bitsPerSample;
@property (nonatomic, strong) NSURL *fileURL;
@property (nonatomic, strong) UIImage *artwork;
@property (nonatomic, assign) BOOL isFavorite;
@property (nonatomic, assign) NSInteger playCount;
@property (nonatomic, strong) NSDate *lastPlayedAt;

- (NSString *)formattedQualityBadge; // e.g. "FLAC • 24-bit / 48 kHz"
- (NSString *)formattedDuration;

@end

@interface PlaylistModel : NSObject

@property (nonatomic, copy) NSString *playlistId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSMutableArray<NSString *> *trackIds;
@property (nonatomic, strong) NSDate *createdAt;

- (NSDictionary *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary *)dict;

@end
