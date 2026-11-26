#import <Foundation/Foundation.h>
#import "TrackItem.h"

extern NSString * const MusicLibraryDidUpdateNotification;

@interface MusicLibrary : NSObject

@property (nonatomic, strong, readonly) NSArray<TrackItem *> *allTracks;
@property (nonatomic, strong, readonly) NSArray<PlaylistModel *> *playlists;

+ (instancetype)sharedLibrary;

- (void)reloadLibrary;
- (NSString *)documentsMusicDirectory;
- (TrackItem *)importFileAtURL:(NSURL *)sourceURL;
- (BOOL)deleteTrack:(TrackItem *)track;

// Queries
- (NSArray<TrackItem *> *)favoriteTracks;
- (NSArray<TrackItem *> *)recentlyPlayedTracks;
- (NSArray<NSString *> *)allArtists;
- (NSArray<NSString *> *)allAlbums;
- (NSArray<TrackItem *> *)tracksForArtist:(NSString *)artist;
- (NSArray<TrackItem *> *)tracksForAlbum:(NSString *)album;
- (NSArray<TrackItem *> *)searchTracksWithQuery:(NSString *)query;
- (TrackItem *)trackWithId:(NSString *)trackId;

// Favorites & History
- (void)toggleFavoriteForTrack:(TrackItem *)track;
- (void)recordPlayForTrack:(TrackItem *)track;

// Playlists
- (PlaylistModel *)createPlaylistWithName:(NSString *)name;
- (void)deletePlaylist:(PlaylistModel *)playlist;
- (void)renamePlaylist:(PlaylistModel *)playlist toName:(NSString *)newName;
- (void)addTrack:(TrackItem *)track toPlaylist:(PlaylistModel *)playlist;
- (void)removeTrackAtIndex:(NSUInteger)index fromPlaylist:(PlaylistModel *)playlist;
- (NSArray<TrackItem *> *)tracksForPlaylist:(PlaylistModel *)playlist;

@end
