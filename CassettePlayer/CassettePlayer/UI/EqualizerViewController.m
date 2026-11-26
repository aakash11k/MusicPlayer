#import "EqualizerViewController.h"
#import "PlaybackManager.h"
#import "LosslessAudioEngine.h"

@interface EqualizerViewController ()
@property (nonatomic, strong) UISwitch *bypassSwitch;
@property (nonatomic, strong) NSMutableArray<UISlider *> *sliders;
@property (nonatomic, strong) NSMutableArray<UILabel *> *valueLabels;
@end

@implementation EqualizerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"10-Band Lossless EQ";
    self.view.backgroundColor = [UIColor colorWithRed:0.09 green:0.09 blue:0.11 alpha:1.0];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Done"
                                                                              style:UIBarButtonItemStyleDone
                                                                             target:self
                                                                             action:@selector(closeSelf)];

    LosslessAudioEngine *engine = [PlaybackManager sharedManager].engine;
    CGFloat w = self.view.bounds.size.width;

    // Enable Switch
    UILabel *enableLbl = [[UILabel alloc] initWithFrame:CGRectMake(16, 76, 180, 30)];
    enableLbl.text = @"Equalizer Active";
    enableLbl.textColor = [UIColor whiteColor];
    enableLbl.font = [UIFont boldSystemFontOfSize:15];
    [self.view addSubview:enableLbl];

    self.bypassSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(w - 68, 76, 51, 31)];
    self.bypassSwitch.onTintColor = [UIColor colorWithRed:0.92 green:0.46 blue:0.16 alpha:1.0];
    self.bypassSwitch.on = engine.eqEnabled;
    [self.bypassSwitch addTarget:self action:@selector(toggleEQ:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.bypassSwitch];

    // Preset Scroll Row
    UIScrollView *presetScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 118, w, 40)];
    presetScroll.showsHorizontalScrollIndicator = NO;
    CGFloat px = 16;
    for (NSString *preset in [LosslessAudioEngine availableEQPresets]) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        [btn setTitle:preset forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        btn.backgroundColor = [UIColor colorWithRed:0.18 green:0.18 blue:0.21 alpha:1.0];
        btn.layer.cornerRadius = 14;
        CGFloat bw = [preset sizeWithAttributes:@{NSFontAttributeName: btn.titleLabel.font}].width + 24;
        btn.frame = CGRectMake(px, 4, bw, 30);
        [btn addTarget:self action:@selector(selectPreset:) forControlEvents:UIControlEventTouchUpInside];
        [presetScroll addSubview:btn];
        px += bw + 8;
    }
    presetScroll.contentSize = CGSizeMake(px + 8, 40);
    [self.view addSubview:presetScroll];

    // 10-Band Vertical Sliders
    self.sliders = [NSMutableArray array];
    self.valueLabels = [NSMutableArray array];
    NSArray *freqs = @[@"32", @"64", @"125", @"250", @"500", @"1K", @"2K", @"4K", @"8K", @"16K"];
    CGFloat bandW = (w - 20) / 10.0;
    CGFloat sliderCenterY = 275;

    for (NSUInteger i = 0; i < 10; i++) {
        CGFloat cx = 10 + bandW * i + bandW / 2.0;

        UILabel *valLbl = [[UILabel alloc] initWithFrame:CGRectMake(cx - 16, 170, 32, 16)];
        valLbl.textAlignment = NSTextAlignmentCenter;
        valLbl.font = [UIFont systemFontOfSize:9];
        valLbl.textColor = [UIColor colorWithRed:0.92 green:0.46 blue:0.16 alpha:1.0];
        [self.view addSubview:valLbl];
        [self.valueLabels addObject:valLbl];

        UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 170, 30)];
        slider.minimumValue = -12.0f;
        slider.maximumValue = 12.0f;
        slider.value = [engine eqGainForBand:i];
        slider.tag = i;
        slider.tintColor = [UIColor colorWithRed:0.92 green:0.46 blue:0.16 alpha:1.0];
        slider.transform = CGAffineTransformMakeRotation(-M_PI_2);
        slider.center = CGPointMake(cx, sliderCenterY);
        [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
        [self.view addSubview:slider];
        [self.sliders addObject:slider];

        UILabel *freqLbl = [[UILabel alloc] initWithFrame:CGRectMake(cx - 16, 372, 32, 16)];
        freqLbl.text = freqs[i];
        freqLbl.textAlignment = NSTextAlignmentCenter;
        freqLbl.font = [UIFont boldSystemFontOfSize:10];
        freqLbl.textColor = [UIColor lightGrayColor];
        [self.view addSubview:freqLbl];
    }
    [self refreshValueLabels];
}

- (void)toggleEQ:(UISwitch *)sender {
    [PlaybackManager sharedManager].engine.eqEnabled = sender.isOn;
}

- (void)selectPreset:(UIButton *)sender {
    NSString *preset = [sender titleForState:UIControlStateNormal];
    LosslessAudioEngine *engine = [PlaybackManager sharedManager].engine;
    [engine applyEQPreset:preset];
    for (NSUInteger i = 0; i < 10; i++) {
        self.sliders[i].value = [engine eqGainForBand:i];
    }
    [self refreshValueLabels];
}

- (void)sliderChanged:(UISlider *)sender {
    [[PlaybackManager sharedManager].engine setEQGain:sender.value forBand:(NSUInteger)sender.tag];
    [self refreshValueLabels];
}

- (void)refreshValueLabels {
    LosslessAudioEngine *engine = [PlaybackManager sharedManager].engine;
    for (NSUInteger i = 0; i < 10; i++) {
        float g = [engine eqGainForBand:i];
        self.valueLabels[i].text = [NSString stringWithFormat:@"%+.0f", g];
    }
}

- (void)closeSelf {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
