#import "NowPlayingViewController.h"
#import "CassetteDeckView.h"
#import "PlaybackManager.h"
#import "MusicLibrary.h"
#import "EqualizerViewController.h"
#import "QueueViewController.h"

@interface NowPlayingViewController ()
@property (nonatomic, strong) CassetteDeckView *deckView;
@property (nonatomic, strong) UISlider *scrubber;
@property (nonatomic, strong) UILabel *elapsedLabel;
@property (nonatomic, strong) UILabel *durationLabel;

@property (nonatomic, strong) UIButton *shuffleBtn;
@property (nonatomic, strong) UIButton *favBtn;
@property (nonatomic, strong) UIButton *repeatBtn;
@property (nonatomic, strong) UIButton *playPauseBtn;

@property (nonatomic, assign) BOOL isScrubbing;
@property (nonatomic, strong) NSTimer *uiTimer;
@end

@implementation NowPlayingViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.09 alpha:1.0];

    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    CGFloat tabH = 49.0;
    CGFloat topY = 26.0;

    // Header Bar
    UILabel *headerLbl = [[UILabel alloc] initWithFrame:CGRectMake(16, topY, w - 120, 22)];
    headerLbl.text = @"CASSETTE LOSSLESS DECK";
    headerLbl.font = [UIFont fontWithName:@"Menlo-Bold" size:12] ?: [UIFont boldSystemFontOfSize:12];
    headerLbl.textColor = [UIColor colorWithRed:0.92 green:0.46 blue:0.16 alpha:1.0];
    [self.view addSubview:headerLbl];

    UIButton *eqBtn = [self makePillButton:@"EQ" frame:CGRectMake(w - 108, topY - 2, 42, 24)];
    [eqBtn addTarget:self action:@selector(openEQ) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:eqBtn];

    UIButton *queueBtn = [self makePillButton:@"QUEUE" frame:CGRectMake(w - 60, topY - 2, 48, 24)];
    [queueBtn addTarget:self action:@selector(openQueue) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:queueBtn];

    // Cassette Deck View (responsive for 3.5" 480pt iPhone 4S)
    CGFloat deckH = MIN(225.0, h - tabH - 210.0);
    self.deckView = [[CassetteDeckView alloc] initWithFrame:CGRectMake(10, topY + 28, w - 20, deckH)];
    [self.view addSubview:self.deckView];

    CGFloat y = CGRectGetMaxY(self.deckView.frame) + 10;

    // Scrubber + Time Labels
    self.elapsedLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, y, 48, 18)];
    self.elapsedLabel.font = [UIFont fontWithName:@"Menlo" size:11] ?: [UIFont systemFontOfSize:11];
    self.elapsedLabel.textColor = [UIColor lightGrayColor];
    self.elapsedLabel.text = @"0:00";
    [self.view addSubview:self.elapsedLabel];

    self.durationLabel = [[UILabel alloc] initWithFrame:CGRectMake(w - 64, y, 48, 18)];
    self.durationLabel.font = [UIFont fontWithName:@"Menlo" size:11] ?: [UIFont systemFontOfSize:11];
    self.durationLabel.textColor = [UIColor lightGrayColor];
    self.durationLabel.textAlignment = NSTextAlignmentRight;
    self.durationLabel.text = @"0:00";
    [self.view addSubview:self.durationLabel];

    self.scrubber = [[UISlider alloc] initWithFrame:CGRectMake(16, y + 16, w - 32, 28)];
    self.scrubber.minimumTrackTintColor = [UIColor colorWithRed:0.92 green:0.46 blue:0.16 alpha:1.0];
    self.scrubber.maximumTrackTintColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    [self.scrubber addTarget:self action:@selector(scrubberDown) forControlEvents:UIControlEventTouchDown];
    [self.scrubber addTarget:self action:@selector(scrubberChanged) forControlEvents:UIControlEventValueChanged];
    [self.scrubber addTarget:self action:@selector(scrubberUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [self.view addSubview:self.scrubber];

    y += 50;

    // Secondary Row: Shuffle | Favorite | Repeat
    self.shuffleBtn = [self makeIconButton:@"SHUFFLE" frame:CGRectMake(20, y, 76, 28)];
    [self.shuffleBtn addTarget:self action:@selector(toggleShuffle) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.shuffleBtn];

    self.favBtn = [self makeIconButton:@"♡ SAVE" frame:CGRectMake((w - 76) / 2.0, y, 76, 28)];
    [self.favBtn addTarget:self action:@selector(toggleFavorite) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.favBtn];

    self.repeatBtn = [self makeIconButton:@"REPEAT" frame:CGRectMake(w - 96, y, 76, 28)];
    [self.repeatBtn addTarget:self action:@selector(cycleRepeat) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.repeatBtn];

    y += 38;

    // Physical Cassette Transport Keys: |<   <<   PLAY/PAUSE   >>   >|
    CGFloat btnW = (w - 40) / 5.0;
    CGFloat btnH = 48.0;

    UIButton *prevBtn = [self makeTransportButton:@"|◀" frame:CGRectMake(12, y, btnW, btnH) primary:NO];
    [prevBtn addTarget:self action:@selector(prevTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:prevBtn];

    UIButton *rewBtn = [self makeTransportButton:@"◀◀" frame:CGRectMake(16 + btnW, y, btnW, btnH) primary:NO];
    [rewBtn addTarget:self action:@selector(rewTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:rewBtn];

    self.playPauseBtn = [self makeTransportButton:@"▶" frame:CGRectMake(20 + btnW * 2, y, btnW, btnH) primary:YES];
    [self.playPauseBtn addTarget:self action:@selector(playPauseTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.playPauseBtn];

    UIButton *ffBtn = [self makeTransportButton:@"▶▶" frame:CGRectMake(24 + btnW * 3, y, btnW, btnH) primary:NO];
    [ffBtn addTarget:self action:@selector(ffTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:ffBtn];

    UIButton *nextBtn = [self makeTransportButton:@"▶|" frame:CGRectMake(28 + btnW * 4, y, btnW, btnH) primary:NO];
    [nextBtn addTarget:self action:@selector(nextTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:nextBtn];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshTrackInfo) name:PlaybackDidChangeTrackNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshTrackInfo) name:PlaybackDidChangeStateNotification object:nil];

    [self refreshTrackInfo];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.deckView startAnimation];
    if (!self.uiTimer) {
        self.uiTimer = [NSTimer scheduledTimerWithTimeInterval:0.06 target:self selector:@selector(updateLiveMeters) userInfo:nil repeats:YES];
    }
    [self refreshTrackInfo];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.deckView stopAnimation];
    [self.uiTimer invalidate];
    self.uiTimer = nil;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - UI Helpers

- (UIButton *)makePillButton:(NSString *)title frame:(CGRect)frame {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = frame;
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:10];
    btn.backgroundColor = [UIColor colorWithRed:0.18 green:0.18 blue:0.20 alpha:1.0];
    btn.layer.cornerRadius = 6;
    btn.layer.borderWidth = 1;
    btn.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:1.0].CGColor;
    return btn;
}

- (UIButton *)makeIconButton:(NSString *)title frame:(CGRect)frame {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = frame;
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor lightGrayColor] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    return btn;
}

- (UIButton *)makeTransportButton:(NSString *)title frame:(CGRect)frame primary:(BOOL)primary {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = frame;
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    btn.backgroundColor = primary
        ? [UIColor colorWithRed:0.92 green:0.46 blue:0.16 alpha:1.0]
        : [UIColor colorWithRed:0.19 green:0.19 blue:0.22 alpha:1.0];
    btn.layer.cornerRadius = 8;
    btn.layer.borderWidth = 1;
    btn.layer.borderColor = [UIColor colorWithWhite:0.32 alpha:1.0].CGColor;
    return btn;
}

#pragma mark - Refresh & Live Updates

- (void)refreshTrackInfo {
    PlaybackManager *pm = [PlaybackManager sharedManager];
    TrackItem *t = pm.currentTrack;

    if (t) {
        self.deckView.trackTitle = t.title ?: @"Unknown Track";
        self.deckView.artistName = t.artist ?: @"Unknown Artist";
        self.deckView.qualityBadge = [t formattedQualityBadge];
        [self.favBtn setTitle:(t.isFavorite ? @"♥ SAVED" : @"♡ SAVE") forState:UIControlStateNormal];
        [self.favBtn setTitleColor:(t.isFavorite ? [UIColor colorWithRed:0.92 green:0.46 blue:0.16 alpha:1.0] : [UIColor lightGrayColor]) forState:UIControlStateNormal];
    } else {
        self.deckView.trackTitle = @"NO CASSETTE LOADED";
        self.deckView.artistName = @"OPEN LIBRARY TO PLAY FLAC / ALAC";
        self.deckView.qualityBadge = @"LOSSLESS DECK";
    }

    BOOL playing = (pm.engine.state == AudioEngineStatePlaying);
    self.deckView.isPlaying = playing;
    [self.playPauseBtn setTitle:(playing ? @"❚❚" : @"▶") forState:UIControlStateNormal];

    [self.shuffleBtn setTitleColor:(pm.shuffleEnabled ? [UIColor colorWithRed:0.92 green:0.46 blue:0.16 alpha:1.0] : [UIColor lightGrayColor]) forState:UIControlStateNormal];

    NSString *repText = @"REPEAT";
    UIColor *repColor = [UIColor lightGrayColor];
    if (pm.repeatMode == RepeatModeAll) {
        repText = @"REPEAT ALL";
        repColor = [UIColor colorWithRed:0.92 green:0.46 blue:0.16 alpha:1.0];
    } else if (pm.repeatMode == RepeatModeOne) {
        repText = @"REPEAT 1";
        repColor = [UIColor colorWithRed:0.92 green:0.46 blue:0.16 alpha:1.0];
    }
    [self.repeatBtn setTitle:repText forState:UIControlStateNormal];
    [self.repeatBtn setTitleColor:repColor forState:UIControlStateNormal];
}

- (void)updateLiveMeters {
    PlaybackManager *pm = [PlaybackManager sharedManager];
    LosslessAudioEngine *engine = pm.engine;

    self.deckView.leftLevel = engine.leftLevel;
    self.deckView.rightLevel = engine.rightLevel;

    NSTimeInterval dur = engine.duration;
    NSTimeInterval cur = engine.currentTime;
    if (!self.isScrubbing && dur > 0) {
        float pct = (float)(cur / dur);
        self.scrubber.value = pct;
        self.deckView.progress = pct;
        self.elapsedLabel.text = [self formatTime:cur];
        self.durationLabel.text = [self formatTime:dur];
    }
}

- (NSString *)formatTime:(NSTimeInterval)t {
    NSInteger s = (NSInteger)MAX(0, round(t));
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(s / 60), (long)(s % 60)];
}

#pragma mark - Actions

- (void)playPauseTapped { [[PlaybackManager sharedManager] togglePlayPause]; }
- (void)nextTapped { [self.deckView pulseFastSpin]; [[PlaybackManager sharedManager] nextTrack]; }
- (void)prevTapped { [self.deckView pulseFastSpin]; [[PlaybackManager sharedManager] previousTrack]; }
- (void)ffTapped { [self.deckView pulseFastSpin]; [[PlaybackManager sharedManager] seekByDelta:15.0]; }
- (void)rewTapped { [self.deckView pulseFastSpin]; [[PlaybackManager sharedManager] seekByDelta:-15.0]; }

- (void)scrubberDown { self.isScrubbing = YES; }
- (void)scrubberChanged {
    NSTimeInterval dur = [PlaybackManager sharedManager].engine.duration;
    self.elapsedLabel.text = [self formatTime:self.scrubber.value * dur];
    self.deckView.progress = self.scrubber.value;
}
- (void)scrubberUp {
    self.isScrubbing = NO;
    NSTimeInterval dur = [PlaybackManager sharedManager].engine.duration;
    [[PlaybackManager sharedManager] seekToTime:self.scrubber.value * dur];
}

- (void)toggleShuffle {
    PlaybackManager *pm = [PlaybackManager sharedManager];
    pm.shuffleEnabled = !pm.shuffleEnabled;
    [self refreshTrackInfo];
}

- (void)cycleRepeat {
    PlaybackManager *pm = [PlaybackManager sharedManager];
    pm.repeatMode = (pm.repeatMode + 1) % 3;
    [self refreshTrackInfo];
}

- (void)toggleFavorite {
    TrackItem *t = [PlaybackManager sharedManager].currentTrack;
    if (t) {
        [[MusicLibrary sharedLibrary] toggleFavoriteForTrack:t];
        [self refreshTrackInfo];
    }
}

- (void)openEQ {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[[EqualizerViewController alloc] init]];
    nav.navigationBar.barStyle = UIBarStyleBlack;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)openQueue {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[[QueueViewController alloc] init]];
    nav.navigationBar.barStyle = UIBarStyleBlack;
    [self presentViewController:nav animated:YES completion:nil];
}

@end
