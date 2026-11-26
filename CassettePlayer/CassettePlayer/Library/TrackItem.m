#import "TrackItem.h"

@implementation TrackItem

- (NSString *)formattedQualityBadge {
    double khz = self.sampleRate / 1000.0;
    NSString *rateStr = (fmod(khz, 1.0) == 0.0)
        ? [NSString stringWithFormat:@"%.0f kHz", khz]
        : [NSString stringWithFormat:@"%.1f kHz", khz];
    UInt32 bits = self.bitsPerSample > 0 ? self.bitsPerSample : 16;
    return [NSString stringWithFormat:@"%@ • %u-bit / %@", self.codec ?: @"LOSSLESS", (unsigned int)bits, rateStr];
}

- (NSString *)formattedDuration {
    NSInteger total = (NSInteger)MAX(0, round(self.duration));
    NSInteger mins = total / 60;
    NSInteger secs = total % 60;
    return [NSString stringWithFormat:@"%ld:%02ld", (long)mins, (long)secs];
}

@end

@implementation PlaylistModel

- (instancetype)init {
    self = [super init];
    if (self) {
        _playlistId = [[NSUUID UUID] UUIDString];
        _trackIds = [NSMutableArray array];
        _createdAt = [NSDate date];
    }
    return self;
}

- (NSDictionary *)toDictionary {
    return @{
        @"id": self.playlistId ?: @"",
        @"name": self.name ?: @"Untitled",
        @"trackIds": self.trackIds ?: @[],
        @"createdAt": @([self.createdAt timeIntervalSince1970])
    };
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    PlaylistModel *p = [[PlaylistModel alloc] init];
    p.playlistId = dict[@"id"] ?: [[NSUUID UUID] UUIDString];
    p.name = dict[@"name"] ?: @"Untitled";
    NSArray *ids = dict[@"trackIds"];
    p.trackIds = ids ? [ids mutableCopy] : [NSMutableArray array];
    NSTimeInterval ts = [dict[@"createdAt"] doubleValue];
    p.createdAt = ts > 0 ? [NSDate dateWithTimeIntervalSince1970:ts] : [NSDate date];
    return p;
}

@end
