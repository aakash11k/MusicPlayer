#import "LibraryViewController.h"
#import "MusicLibrary.h"
#import "PlaybackManager.h"
#import "WiFiUploadServer.h"

typedef NS_ENUM(NSInteger, LibrarySectionMode) {
    LibrarySectionSongs = 0,
    LibrarySectionAlbums,
    LibrarySectionArtists,
    LibrarySectionPlaylists,
    LibrarySectionFavorites
};

@interface LibraryViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UISegmentedControl *segmentedControl;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, assign) LibrarySectionMode mode;
@property (nonatomic, strong) NSArray *currentItems;
@property (nonatomic, strong) PlaylistModel *selectedPlaylist;
@property (nonatomic, copy) NSString *selectedFilterGroup;
@end

@implementation LibraryViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Lossless Library";
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.09 alpha:1.0];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Wi-Fi Upload"
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(toggleWiFiUpload)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                                           target:self
                                                                                           action:@selector(createPlaylistPrompt)];

    CGFloat w = self.view.bounds.size.width;
    self.segmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"Songs", @"Albums", @"Artists", @"Lists", @"Favs"]];
    self.segmentedControl.frame = CGRectMake(8, 70, w - 16, 28);
    self.segmentedControl.selectedSegmentIndex = 0;
    self.segmentedControl.tintColor = [UIColor colorWithRed:0.92 green:0.46 blue:0.16 alpha:1.0];
    [self.segmentedControl addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.segmentedControl];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 104, w, self.view.bounds.size.height - 104 - 49) style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    [self.view addSubview:self.tableView];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData) name:MusicLibraryDidUpdateNotification object:nil];
    [self reloadData];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)segmentChanged:(UISegmentedControl *)sender {
    self.mode = (LibrarySectionMode)sender.selectedSegmentIndex;
    self.selectedPlaylist = nil;
    self.selectedFilterGroup = nil;
    [self reloadData];
}

- (void)reloadData {
    MusicLibrary *lib = [MusicLibrary sharedLibrary];
    if (self.selectedPlaylist) {
        self.currentItems = [lib tracksForPlaylist:self.selectedPlaylist];
    } else if (self.selectedFilterGroup) {
        if (self.mode == LibrarySectionAlbums) {
            self.currentItems = [lib tracksForAlbum:self.selectedFilterGroup];
        } else {
            self.currentItems = [lib tracksForArtist:self.selectedFilterGroup];
        }
    } else {
        switch (self.mode) {
            case LibrarySectionSongs: self.currentItems = lib.allTracks; break;
            case LibrarySectionAlbums: self.currentItems = [lib allAlbums]; break;
            case LibrarySectionArtists: self.currentItems = [lib allArtists]; break;
            case LibrarySectionPlaylists: self.currentItems = lib.playlists; break;
            case LibrarySectionFavorites: self.currentItems = [lib favoriteTracks]; break;
        }
    }
    [self.tableView reloadData];
}

#pragma mark - Wi-Fi Uploader & Playlists

- (void)toggleWiFiUpload {
    WiFiUploadServer *srv = [WiFiUploadServer sharedServer];
    if (srv.isRunning) {
        [srv stop];
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Wi-Fi Uploader Stopped"
                                                                   message:@"Server has been turned off."
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:ac animated:YES completion:nil];
    } else {
        if ([srv startWithPort:8080]) {
            NSString *msg = [NSString stringWithFormat:@"Open this URL in your PC browser (same Wi-Fi) to drop .FLAC or .M4A (ALAC) files:\n\n%@", srv.serverURLString];
            UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Wi-Fi Uploader Active"
                                                                       message:msg
                                                                preferredStyle:UIAlertControllerStyleAlert];
            [ac addAction:[UIAlertAction actionWithTitle:@"Keep Running" style:UIAlertActionStyleDefault handler:nil]];
            [ac addAction:[UIAlertAction actionWithTitle:@"Stop Server" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
                [srv stop];
            }]];
            [self presentViewController:ac animated:YES completion:nil];
        }
    }
}

- (void)createPlaylistPrompt {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"New Mixtape Playlist"
                                                               message:@"Enter a name for your playlist:"
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"90s Lossless Mix";
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Create" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *name = ac.textFields.firstObject.text;
        [[MusicLibrary sharedLibrary] createPlaylistWithName:name];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - TableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.currentItems.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cid = @"LibCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [UIColor lightGrayColor];
    }

    id obj = self.currentItems[indexPath.row];
    if ([obj isKindOfClass:[TrackItem class]]) {
        TrackItem *t = (TrackItem *)obj;
        cell.textLabel.text = t.title;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ • %@", t.artist, [t formattedQualityBadge]];
        cell.accessoryType = UITableViewCellAccessoryDetailButton;
    } else if ([obj isKindOfClass:[PlaylistModel class]]) {
        PlaylistModel *p = (PlaylistModel *)obj;
        cell.textLabel.text = p.name;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu tracks", (unsigned long)p.trackIds.count];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if ([obj isKindOfClass:[NSString class]]) {
        cell.textLabel.text = (NSString *)obj;
        cell.detailTextLabel.text = (self.mode == LibrarySectionAlbums) ? @"Album" : @"Artist";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    id obj = self.currentItems[indexPath.row];

    if ([obj isKindOfClass:[TrackItem class]]) {
        TrackItem *t = (TrackItem *)obj;
        [[PlaybackManager sharedManager] playTrack:t inQueue:self.currentItems];
        self.tabBarController.selectedIndex = 0; // Switch to Cassette Deck
    } else if ([obj isKindOfClass:[PlaylistModel class]]) {
        self.selectedPlaylist = (PlaylistModel *)obj;
        [self reloadData];
    } else if ([obj isKindOfClass:[NSString class]]) {
        self.selectedFilterGroup = (NSString *)obj;
        [self reloadData];
    }
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
    id obj = self.currentItems[indexPath.row];
    if (![obj isKindOfClass:[TrackItem class]]) return;
    TrackItem *t = (TrackItem *)obj;

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:t.title
                                                                   message:[t formattedQualityBadge]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Play Next" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [[PlaybackManager sharedManager] playNextInQueue:t];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Add to Queue" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [[PlaybackManager sharedManager] addToQueue:t];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:(t.isFavorite ? @"Remove from Favorites" : @"Add to Favorites")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [[MusicLibrary sharedLibrary] toggleFavoriteForTrack:t];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Add to Playlist..." style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self showPlaylistPickerForTrack:t];
    }]];
    if (t.fileURL.isFileURL) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Delete File" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            [[MusicLibrary sharedLibrary] deleteTrack:t];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)showPlaylistPickerForTrack:(TrackItem *)track {
    NSArray<PlaylistModel *> *lists = [MusicLibrary sharedLibrary].playlists;
    UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"Add to Playlist"
                                                                    message:nil
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    for (PlaylistModel *p in lists) {
        [picker addAction:[UIAlertAction actionWithTitle:p.name style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [[MusicLibrary sharedLibrary] addTrack:track toPlaylist:p];
        }]];
    }
    [picker addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:picker animated:YES completion:nil];
}

@end
