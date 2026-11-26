#import <UIKit/UIKit.h>

@interface CassetteDeckView : UIView

@property (nonatomic, copy) NSString *trackTitle;
@property (nonatomic, copy) NSString *artistName;
@property (nonatomic, copy) NSString *qualityBadge;
@property (nonatomic, strong) UIImage *artwork;

@property (nonatomic, assign) BOOL isPlaying;
@property (nonatomic, assign) float progress; // 0.0 to 1.0
@property (nonatomic, assign) float leftLevel; // 0.0 to 1.0
@property (nonatomic, assign) float rightLevel; // 0.0 to 1.0

- (void)startAnimation;
- (void)stopAnimation;
- (void)pulseFastSpin;

@end
