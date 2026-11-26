#import "MusicLibrary.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <MediaPlayer/MediaPlayer.h>
#include "dr_flac.h"

NSString * const MusicLibraryDidUpdateNotification = @"MusicLibraryDidUpdateNotification";

@interface MusicLibrary ()
@property (nonatomic, strong) NSMutableArray<TrackItem *> *mutableTracks;
@property (nonatomic, strong) NSMutableArray<PlaylistModel *> *mutablePlaylists;
@property (nonatomic, strong) NSMutableSet<NSString *> *favoriteIds;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *playHistory;
@end

@implementation MusicLibrary

+ (instancetype)sharedLibrary {
    static MusicLibrary *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[MusicLibrary alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableTracks = [NSMutableArray array];
        _mutablePlaylists = [NSMutableArray array];
        _favoriteIds = [NSMutableSet set];
        _playHistory = [NSMutableDictionary dictionary];
        [self loadPersistedState];
    }
    return self;
}

- (NSArray<TrackItem *> *)allTracks {
    return [self.mutableTracks copy];
}

- (NSArray<PlaylistModel *> *)playlists {
    return [self.mutablePlaylists copy];
}

- (NSString *)documentsMusicDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return paths.firstObject;
}

- (NSString *)appSupportDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *dir = paths.firstObject;
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

#pragma mark - Scanning

- (void)reloadLibrary {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray<TrackItem *> *found = [NSMutableArray array];
        NSSet *supportedExts = [NSSet setWithArray:@[@"flac", @"m4a", @"alac", @"caf", @"wav", @"aiff", @"aif"]];

        NSString *docsDir = [self documentsMusicDirectory];
        NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:docsDir];
        NSString *relPath = nil;
        while ((relPath = [enumerator nextObject])) {
            NSString *ext = relPath.pathExtension.lowercaseString;
            if ([supportedExts containsObject:ext]) {
                NSString *fullPath = [docsDir stringByAppendingPathComponent:relPath];
                NSURL *fileURL = [NSURL fileURLWithPath:fullPath];
                TrackItem *item = [self parseTrackAtURL:fileURL];
                if (item) {
                    [found addObject:item];
                }
            }
        }

        // Also include synced ALAC tracks from the device iPod library if available
        MPMediaQuery *songsQuery = [MPMediaQuery songsQuery];
        for (MPMediaItem *mediaItem in songsQuery.items) {
            NSURL *assetURL = [mediaItem valueForProperty:MPMediaItemPropertyAssetURL];
            if (!assetURL) continue; // DRM-protected or cloud-only item

            TrackItem *item = [[TrackItem alloc] init];
            item.trackId = [NSString stringWithFormat:@"ipod_%llu", mediaItem.persistentID];
            item.title = mediaItem.title ?: @"Unknown Track";
            item.artist = mediaItem.artist ?: @"Unknown Artist";
            item.album = mediaItem.albumTitle ?: @"Unknown Album";
            item.duration = mediaItem.playbackDuration;
            item.fileURL = assetURL;
            item.codec = @"ALAC/iPod";
            item.sampleRate = 44100.0;
            item.bitsPerSample = 16;
            MPMediaItemArtwork *art = mediaItem.artwork;
            if (art) {
                item.artwork = [art imageWithSize:CGSizeMake(300, 300)];
            }
            item.isFavorite = [self.favoriteIds containsObject:item.trackId];
            [self applyHistoryToTrack:item];
            [found addObject:item];
        }

        [found sortUsingComparator:^NSComparisonResult(TrackItem *a, TrackItem *b) {
            return [a.title localizedCaseInsensitiveCompare:b.title];
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.mutableTracks = found;
            [[NSNotificationCenter defaultCenter] postNotificationName:MusicLibraryDidUpdateNotification object:self];
        });
    });
}

- (TrackItem *)importFileAtURL:(NSURL *)sourceURL {
    if (!sourceURL || !sourceURL.isFileURL) return nil;
    NSString *filename = sourceURL.lastPathComponent;
    NSString *destPath = [[self documentsMusicDirectory] stringByAppendingPathComponent:filename];
    NSURL *destURL = [NSURL fileURLWithPath:destPath];

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![sourceURL.path isEqualToString:destPath]) {
        if ([fm fileExistsAtPath:destPath]) {
            [fm removeItemAtURL:destURL error:nil];
        }
        NSError *copyErr = nil;
        [fm copyItemAtURL:sourceURL toURL:destURL error:&copyErr];
        if (copyErr) {
            NSLog(@"Import error: %@", copyErr);
            return nil;
        }
    }

    TrackItem *item = [self parseTrackAtURL:destURL];
    if (item) {
        [self reloadLibrary];
    }
    return item;
}

- (BOOL)deleteTrack:(TrackItem *)track {
    if (!track.fileURL.isFileURL) return NO;
    NSError *err = nil;
    BOOL ok = [[NSFileManager defaultManager] removeItemAtURL:track.fileURL error:&err];
    if (ok) {
        [self.mutableTracks removeObject:track];
        [[NSNotificationCenter defaultCenter] postNotificationName:MusicLibraryDidUpdateNotification object:self];
    }
    return ok;
}

#pragma mark - Metadata Parsing (FLAC + ALAC)

typedef struct {
    char title[256];
    char artist[256];
    char album[256];
    const void *picData;
    size_t picSize;
    void *picOwnedCopy;
} FlacMetaContext;

static void flacMetadataCallback(void *pUserData, drflac_metadata *pMetadata) {
    FlacMetaContext *ctx = (FlacMetaContext *)pUserData;
    if (pMetadata->type == DRFLAC_METADATA_BLOCK_TYPE_VORBIS_COMMENT) {
        drflac_vorbis_comment_iterator iter;
        drflac_init_vorbis_comment_iterator(&iter, pMetadata->data.vorbis_comment.commentCount, pMetadata->data.vorbis_comment.pComments);
        drflac_uint32 len = 0;
        const char *comment = NULL;
        while ((comment = drflac_next_vorbis_comment(&iter, &len)) != NULL) {
            NSString *str = [[NSString alloc] initWithBytes:comment length:len encoding:NSUTF8StringEncoding];
            NSRange eq = [str rangeOfString:@"="];
            if (eq.location != NSNotFound) {
                NSString *key = [[str substringToIndex:eq.location] uppercaseString];
                NSString *val = [str substringFromIndex:eq.location + 1];
                if ([key isEqualToString:@"TITLE"] && val.length > 0) {
                    strlcpy(ctx->title, val.UTF8String, sizeof(ctx->title));
                } else if ([key isEqualToString:@"ARTIST"] && val.length > 0) {
                    strlcpy(ctx->artist, val.UTF8String, sizeof(ctx->artist));
                } else if ([key isEqualToString:@"ALBUM"] && val.length > 0) {
                    strlcpy(ctx->album, val.UTF8String, sizeof(ctx->album));
                }
            }
        }
    } else if (pMetadata->type == DRFLAC_METADATA_BLOCK_TYPE_PICTURE && !ctx->picOwnedCopy) {
        if (pMetadata->data.picture.pictureDataSize > 0 && pMetadata->data.picture.pPictureData) {
            ctx->picSize = pMetadata->data.picture.pictureDataSize;
            ctx->picOwnedCopy = malloc(ctx->picSize);
            if (ctx->picOwnedCopy) {
                memcpy(ctx->picOwnedCopy, pMetadata->data.picture.pPictureData, ctx->picSize);
            }
        }
    }
}

- (TrackItem *)parseTrackAtURL:(NSURL *)fileURL {
    TrackItem *item = [[TrackItem alloc] init];
    item.fileURL = fileURL;
    item.trackId = [NSString stringWithFormat:@"file_%@", fileURL.lastPathComponent];
    NSString *fallbackTitle = [[fileURL.lastPathComponent stringByDeletingPathExtension] stringByReplacingOccurrencesOfString:@"_" withString:@" "];
    item.title = fallbackTitle;
    item.artist = @"Unknown Artist";
    item.album = @"Unknown Album";

    NSString *ext = fileURL.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"flac"]) {
        FlacMetaContext ctx = {0};
        drflac *flac = drflac_open_file_with_metadata(fileURL.path.UTF8String, flacMetadataCallback, &ctx, NULL);
        if (!flac) return nil;

        item.codec = @"FLAC";
        item.sampleRate = (double)flac->sampleRate;
        item.bitsPerSample = flac->bitsPerSample;
        if (flac->sampleRate > 0) {
            item.duration = (NSTimeInterval)flac->totalPCMFrameCount / (double)flac->sampleRate;
        }
        if (ctx.title[0] != '\0') item.title = [NSString stringWithUTF8String:ctx.title];
        if (ctx.artist[0] != '\0') item.artist = [NSString stringWithUTF8String:ctx.artist];
        if (ctx.album[0] != '\0') item.album = [NSString stringWithUTF8String:ctx.album];
        if (ctx.picOwnedCopy && ctx.picSize > 0) {
            NSData *imgData = [NSData dataWithBytesNoCopy:ctx.picOwnedCopy length:ctx.picSize freeWhenDone:YES];
            item.artwork = [UIImage imageWithData:imgData];
        }
        drflac_close(flac);
    } else {
        // ALAC / M4A / CAF / WAV / AIFF via AVURLAsset + ExtAudioFile
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:fileURL options:nil];
        item.duration = CMTimeGetSeconds(asset.duration);
        if (isnan(item.duration)) item.duration = 0;

        for (AVMetadataItem *meta in asset.commonMetadata) {
            if ([meta.commonKey isEqualToString:AVMetadataCommonKeyTitle] && meta.stringValue.length > 0) {
                item.title = meta.stringValue;
            } else if ([meta.commonKey isEqualToString:AVMetadataCommonKeyArtist] && meta.stringValue.length > 0) {
                item.artist = meta.stringValue;
            } else if ([meta.commonKey isEqualToString:AVMetadataCommonKeyAlbumName] && meta.stringValue.length > 0) {
                item.album = meta.stringValue;
            } else if ([meta.commonKey isEqualToString:AVMetadataCommonKeyArtwork]) {
                NSData *data = meta.dataValue;
                if (data) item.artwork = [UIImage imageWithData:data];
            }
        }

        ExtAudioFileRef extFile = NULL;
        if (ExtAudioFileOpenURL((__bridge CFURLRef)fileURL, &extFile) == noErr && extFile) {
            AudioStreamBasicDescription asbd = {0};
            UInt32 size = sizeof(asbd);
            if (ExtAudioFileGetProperty(extFile, kExtAudioFileProperty_FileDataFormat, &size, &asbd) == noErr) {
                item.sampleRate = asbd.mSampleRate;
                if (asbd.mFormatID == kAudioFormatAppleLossless) {
                    item.codec = @"ALAC";
                    if (asbd.mFormatFlags == kAppleLosslessFormatFlag_24BitSourceData) item.bitsPerSample = 24;
                    else if (asbd.mFormatFlags == kAppleLosslessFormatFlag_20BitSourceData) item.bitsPerSample = 20;
                    else item.bitsPerSample = 16;
                } else {
                    item.codec = ext.uppercaseString;
                    item.bitsPerSample = asbd.mBitsPerChannel > 0 ? asbd.mBitsPerChannel : 16;
                }
            }
            ExtAudioFileDispose(extFile);
        } else {
            item.codec = ext.uppercaseString;
            item.sampleRate = 44100.0;
            item.bitsPerSample = 16;
        }
    }

    item.isFavorite = [self.favoriteIds containsObject:item.trackId];
    [self applyHistoryToTrack:item];
    return item;
}

- (void)applyHistoryToTrack:(TrackItem *)item {
    NSDictionary *hist = self.playHistory[item.trackId];
    if (hist) {
        item.playCount = [hist[@"count"] integerValue];
        NSTimeInterval ts = [hist[@"lastPlayed"] doubleValue];
        if (ts > 0) item.lastPlayedAt = [NSDate dateWithTimeIntervalSince1970:ts];
    }
}

#pragma mark - Queries

- (NSArray<TrackItem *> *)favoriteTracks {
    NSPredicate *pred = [NSPredicate predicateWithFormat:@"isFavorite == YES"];
    return [self.mutableTracks filteredArrayUsingPredicate:pred];
}

- (NSArray<TrackItem *> *)recentlyPlayedTracks {
    NSPredicate *pred = [NSPredicate predicateWithFormat:@"lastPlayedAt != nil"];
    NSArray *played = [self.mutableTracks filteredArrayUsingPredicate:pred];
    return [played sortedArrayUsingComparator:^NSComparisonResult(TrackItem *a, TrackItem *b) {
        return [b.lastPlayedAt compare:a.lastPlayedAt];
    }];
}

- (NSArray<NSString *> *)allArtists {
    NSMutableSet *set = [NSMutableSet set];
    for (TrackItem *t in self.mutableTracks) {
        [set addObject:t.artist ?: @"Unknown Artist"];
    }
    return [[set allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (NSArray<NSString *> *)allAlbums {
    NSMutableSet *set = [NSMutableSet set];
    for (TrackItem *t in self.mutableTracks) {
        [set addObject:t.album ?: @"Unknown Album"];
    }
    return [[set allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (NSArray<TrackItem *> *)tracksForArtist:(NSString *)artist {
    NSPredicate *pred = [NSPredicate predicateWithFormat:@"artist == %@", artist];
    return [self.mutableTracks filteredArrayUsingPredicate:pred];
}

- (NSArray<TrackItem *> *)tracksForAlbum:(NSString *)album {
    NSPredicate *pred = [NSPredicate predicateWithFormat:@"album == %@", album];
    return [self.mutableTracks filteredArrayUsingPredicate:pred];
}

- (NSArray<TrackItem *> *)searchTracksWithQuery:(NSString *)query {
    if (query.length == 0) return self.allTracks;
    NSPredicate *pred = [NSPredicate predicateWithFormat:
                         @"title CONTAINS[cd] %@ OR artist CONTAINS[cd] %@ OR album CONTAINS[cd] %@ OR codec CONTAINS[cd] %@",
                         query, query, query, query];
    return [self.mutableTracks filteredArrayUsingPredicate:pred];
}

- (TrackItem *)trackWithId:(NSString *)trackId {
    for (TrackItem *t in self.mutableTracks) {
        if ([t.trackId isEqualToString:trackId]) return t;
    }
    return nil;
}

#pragma mark - Favorites, History & Playlists

- (void)toggleFavoriteForTrack:(TrackItem *)track {
    if (!track) return;
    track.isFavorite = !track.isFavorite;
    if (track.isFavorite) {
        [self.favoriteIds addObject:track.trackId];
    } else {
        [self.favoriteIds removeObject:track.trackId];
    }
    [self savePersistedState];
    [[NSNotificationCenter defaultCenter] postNotificationName:MusicLibraryDidUpdateNotification object:self];
}

- (void)recordPlayForTrack:(TrackItem *)track {
    if (!track) return;
    track.playCount += 1;
    track.lastPlayedAt = [NSDate date];
    self.playHistory[track.trackId] = @{
        @"count": @(track.playCount),
        @"lastPlayed": @([track.lastPlayedAt timeIntervalSince1970])
    };
    [self savePersistedState];
}

- (PlaylistModel *)createPlaylistWithName:(NSString *)name {
    PlaylistModel *p = [[PlaylistModel alloc] init];
    p.name = name.length > 0 ? name : @"New Mixtape";
    [self.mutablePlaylists addObject:p];
    [self savePersistedState];
    [[NSNotificationCenter defaultCenter] postNotificationName:MusicLibraryDidUpdateNotification object:self];
    return p;
}

- (void)deletePlaylist:(PlaylistModel *)playlist {
    [self.mutablePlaylists removeObject:playlist];
    [self savePersistedState];
    [[NSNotificationCenter defaultCenter] postNotificationName:MusicLibraryDidUpdateNotification object:self];
}

- (void)renamePlaylist:(PlaylistModel *)playlist toName:(NSString *)newName {
    if (newName.length > 0) {
        playlist.name = newName;
        [self savePersistedState];
        [[NSNotificationCenter defaultCenter] postNotificationName:MusicLibraryDidUpdateNotification object:self];
    }
}

- (void)addTrack:(TrackItem *)track toPlaylist:(PlaylistModel *)playlist {
    if (!track || !playlist) return;
    [playlist.trackIds addObject:track.trackId];
    [self savePersistedState];
    [[NSNotificationCenter defaultCenter] postNotificationName:MusicLibraryDidUpdateNotification object:self];
}

- (void)removeTrackAtIndex:(NSUInteger)index fromPlaylist:(PlaylistModel *)playlist {
    if (index < playlist.trackIds.count) {
        [playlist.trackIds removeObjectAtIndex:index];
        [self savePersistedState];
        [[NSNotificationCenter defaultCenter] postNotificationName:MusicLibraryDidUpdateNotification object:self];
    }
}

- (NSArray<TrackItem *> *)tracksForPlaylist:(PlaylistModel *)playlist {
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *tid in playlist.trackIds) {
        TrackItem *t = [self trackWithId:tid];
        if (t) [result addObject:t];
    }
    return result;
}

#pragma mark - Persistence

- (void)savePersistedState {
    NSString *dir = [self appSupportDirectory];
    NSMutableArray *pArr = [NSMutableArray array];
    for (PlaylistModel *p in self.mutablePlaylists) {
        [pArr addObject:[p toDictionary]];
    }
    NSDictionary *state = @{
        @"favorites": [self.favoriteIds allObjects],
        @"playlists": pArr,
        @"history": self.playHistory
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:state options:0 error:nil];
    [data writeToFile:[dir stringByAppendingPathComponent:@"library_state.json"] atomically:YES];
}

- (void)loadPersistedState {
    NSString *path = [[self appSupportDirectory] stringByAppendingPathComponent:@"library_state.json"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return;
    NSDictionary *state = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![state isKindOfClass:[NSDictionary class]]) return;

    NSArray *favs = state[@"favorites"];
    if (favs) [self.favoriteIds addObjectsFromArray:favs];

    NSDictionary *hist = state[@"history"];
    if (hist) [self.playHistory addEntriesFromDictionary:hist];

    NSArray *pArr = state[@"playlists"];
    for (NSDictionary *dict in pArr) {
        [self.mutablePlaylists addObject:[PlaylistModel fromDictionary:dict]];
    }
}

@end
