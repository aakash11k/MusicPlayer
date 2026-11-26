#import "CassetteDeckView.h"
#import <QuartzCore/QuartzCore.h>

@interface CassetteDeckView ()
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) CGFloat reelAngle;
@property (nonatomic, assign) CGFloat boostSpeed;
@end

@implementation CassetteDeckView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        _trackTitle = @"NO CASSETTE LOADED";
        _artistName = @"TAP LIBRARY TO LOAD FLAC / ALAC";
        _qualityBadge = @"LOSSLESS DECK";
    }
    return self;
}

- (void)dealloc {
    [self stopAnimation];
}

- (void)startAnimation {
    if (!self.displayLink) {
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

- (void)stopAnimation {
    [self.displayLink invalidate];
    self.displayLink = nil;
}

- (void)pulseFastSpin {
    self.boostSpeed = 0.28f;
}

- (void)tick:(CADisplayLink *)link {
    BOOL needsRedraw = NO;
    if (self.isPlaying) {
        // Real cassette rotation (~0.04 rad/frame + slight speed boost when seeking)
        self.reelAngle += 0.045f + self.boostSpeed;
        if (self.reelAngle > M_PI * 2.0) {
            self.reelAngle -= M_PI * 2.0;
        }
        needsRedraw = YES;
    } else if (self.boostSpeed > 0.005f) {
        self.reelAngle += self.boostSpeed;
        needsRedraw = YES;
    }

    if (self.boostSpeed > 0.0f) {
        self.boostSpeed *= 0.90f;
        if (self.boostSpeed < 0.003f) self.boostSpeed = 0.0f;
    }

    if (self.leftLevel > 0.01f || self.rightLevel > 0.01f) {
        needsRedraw = YES;
    }

    if (needsRedraw) {
        [self setNeedsDisplay];
    }
}

- (void)setProgress:(float)progress {
    _progress = MAX(0.0f, MIN(1.0f, progress));
    [self setNeedsDisplay];
}

- (void)setTrackTitle:(NSString *)trackTitle {
    _trackTitle = [trackTitle copy];
    [self setNeedsDisplay];
}

- (void)setArtistName:(NSString *)artistName {
    _artistName = [artistName copy];
    [self setNeedsDisplay];
}

- (void)setQualityBadge:(NSString *)qualityBadge {
    _qualityBadge = [qualityBadge copy];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGRect bounds = self.bounds;
    CGFloat w = bounds.size.width;
    CGFloat h = bounds.size.height;

    // 1. Outer Cassette Shell (Brushed Dark Charcoal)
    CGRect shellRect = CGRectInset(bounds, 4, 4);
    UIBezierPath *shellPath = [UIBezierPath bezierPathWithRoundedRect:shellRect cornerRadius:14];
    [[UIColor colorWithRed:0.13 green:0.13 blue:0.15 alpha:1.0] setFill];
    [shellPath fill];

    [[UIColor colorWithRed:0.28 green:0.28 blue:0.31 alpha:1.0] setStroke];
    shellPath.lineWidth = 1.5;
    [shellPath stroke];

    // Corner Screws
    CGFloat screwOffset = 14.0;
    CGPoint screws[4] = {
        CGPointMake(shellRect.origin.x + screwOffset, shellRect.origin.y + screwOffset),
        CGPointMake(CGRectGetMaxX(shellRect) - screwOffset, shellRect.origin.y + screwOffset),
        CGPointMake(shellRect.origin.x + screwOffset, CGRectGetMaxY(shellRect) - screwOffset),
        CGPointMake(CGRectGetMaxX(shellRect) - screwOffset, CGRectGetMaxY(shellRect) - screwOffset)
    };
    for (int i = 0; i < 4; i++) {
        CGRect sr = CGRectMake(screws[i].x - 4, screws[i].y - 4, 8, 8);
        [[UIColor colorWithRed:0.35 green:0.35 blue:0.38 alpha:1.0] setFill];
        CGContextFillEllipseInRect(ctx, sr);
        [[UIColor colorWithRed:0.1 green:0.1 blue:0.12 alpha:1.0] setStroke];
        CGContextSetLineWidth(ctx, 1.0);
        CGContextMoveToPoint(ctx, screws[i].x - 2.5, screws[i].y - 2.5);
        CGContextAddLineToPoint(ctx, screws[i].x + 2.5, screws[i].y + 2.5);
        CGContextStrokePath(ctx);
    }

    // 2. Vintage Paper Label
    CGRect labelRect = CGRectMake(shellRect.origin.x + 16, shellRect.origin.y + 14, shellRect.size.width - 32, shellRect.size.height - 54);
    UIBezierPath *labelPath = [UIBezierPath bezierPathWithRoundedRect:labelRect cornerRadius:8];
    [[UIColor colorWithRed:0.95 green:0.92 blue:0.84 alpha:1.0] setFill];
    [labelPath fill];

    // Retro Orange/Amber Top Stripe on Label
    CGContextSaveGState(ctx);
    [labelPath addClip];
    CGRect stripeRect = CGRectMake(labelRect.origin.x, labelRect.origin.y, labelRect.size.width, 28);
    [[UIColor colorWithRed:0.92 green:0.46 blue:0.16 alpha:1.0] setFill];
    CGContextFillRect(ctx, stripeRect);

    // Side A Badge + Quality Text on Stripe
    NSDictionary *sideAttrs = @{
        NSFontAttributeName: [UIFont boldSystemFontOfSize:11],
        NSForegroundColorAttributeName: [UIColor whiteColor]
    };
    [@"SIDE A" drawAtPoint:CGPointMake(labelRect.origin.x + 10, labelRect.origin.y + 7) withAttributes:sideAttrs];

    NSDictionary *qualAttrs = @{
        NSFontAttributeName: [UIFont fontWithName:@"Menlo-Bold" size:9.5] ?: [UIFont boldSystemFontOfSize:9.5],
        NSForegroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:0.95]
    };
    CGSize qSize = [self.qualityBadge sizeWithAttributes:qualAttrs];
    [self.qualityBadge drawAtPoint:CGPointMake(CGRectGetMaxX(labelRect) - qSize.width - 10, labelRect.origin.y + 8) withAttributes:qualAttrs];

    // Track Title & Artist on Label
    NSMutableParagraphStyle *centerStyle = [[NSMutableParagraphStyle alloc] init];
    centerStyle.alignment = NSTextAlignmentCenter;
    centerStyle.lineBreakMode = NSLineBreakByTruncatingTail;

    NSDictionary *titleAttrs = @{
        NSFontAttributeName: [UIFont boldSystemFontOfSize:13],
        NSForegroundColorAttributeName: [UIColor colorWithRed:0.12 green:0.12 blue:0.14 alpha:1.0],
        NSParagraphStyleAttributeName: centerStyle
    };
    [self.trackTitle drawInRect:CGRectMake(labelRect.origin.x + 8, labelRect.origin.y + 32, labelRect.size.width - 16, 18) withAttributes:titleAttrs];

    NSDictionary *artistAttrs = @{
        NSFontAttributeName: [UIFont systemFontOfSize:11],
        NSForegroundColorAttributeName: [UIColor colorWithRed:0.35 green:0.33 blue:0.30 alpha:1.0],
        NSParagraphStyleAttributeName: centerStyle
    };
    [self.artistName drawInRect:CGRectMake(labelRect.origin.x + 8, labelRect.origin.y + 50, labelRect.size.width - 16, 16) withAttributes:artistAttrs];

    CGContextRestoreGState(ctx);

    // 3. Dark Transparent Tape Window (Center of Label)
    CGFloat winW = labelRect.size.width - 36;
    CGFloat winH = MAX(62, labelRect.size.height - 76);
    CGRect windowRect = CGRectMake(labelRect.origin.x + 18, CGRectGetMaxY(labelRect) - winH - 10, winW, winH);
    UIBezierPath *winPath = [UIBezierPath bezierPathWithRoundedRect:windowRect cornerRadius:8];
    [[UIColor colorWithRed:0.08 green:0.08 blue:0.09 alpha:1.0] setFill];
    [winPath fill];
    [[UIColor colorWithRed:0.25 green:0.23 blue:0.20 alpha:1.0] setStroke];
    winPath.lineWidth = 1.5;
    [winPath stroke];

    // 4. Magnetic Tape Spools & Spinning Reels
    CGContextSaveGState(ctx);
    [winPath addClip];

    CGFloat centerY = CGRectGetMidY(windowRect);
    CGFloat leftX = windowRect.origin.x + winW * 0.26;
    CGFloat rightX = windowRect.origin.x + winW * 0.74;

    // Tape spool radius varies with playback progress!
    CGFloat minSpoolR = 20.0;
    CGFloat maxSpoolR = 42.0;
    CGFloat leftSpoolR = maxSpoolR - (maxSpoolR - minSpoolR) * self.progress;
    CGFloat rightSpoolR = minSpoolR + (maxSpoolR - minSpoolR) * self.progress;

    // Draw dark brown magnetic tape packs
    [[UIColor colorWithRed:0.22 green:0.12 blue:0.07 alpha:1.0] setFill];
    CGContextFillEllipseInRect(ctx, CGRectMake(leftX - leftSpoolR, centerY - leftSpoolR, leftSpoolR * 2, leftSpoolR * 2));
    CGContextFillEllipseInRect(ctx, CGRectMake(rightX - rightSpoolR, centerY - rightSpoolR, rightSpoolR * 2, rightSpoolR * 2));

    // Draw Spinning Reel Hubs
    [self drawReelAtCenter:CGPointMake(leftX, centerY) radius:16.5 angle:self.reelAngle context:ctx];
    [self drawReelAtCenter:CGPointMake(rightX, centerY) radius:16.5 angle:self.reelAngle context:ctx];

    // Tape Guide Window Center Scale Marks
    [[UIColor colorWithWhite:0.55 alpha:0.6] setStroke];
    CGContextSetLineWidth(ctx, 1.0);
    CGFloat midX = CGRectGetMidX(windowRect);
    for (int i = -2; i <= 2; i++) {
        CGFloat tickX = midX + i * 8;
        CGContextMoveToPoint(ctx, tickX, windowRect.origin.y + 4);
        CGContextAddLineToPoint(ctx, tickX, windowRect.origin.y + (i == 0 ? 11 : 7));
    }
    CGContextStrokePath(ctx);

    CGContextRestoreGState(ctx);

    // 5. Bottom Trapezoid Tape Head Bridge + Analog VU Meters
    CGFloat bridgeW = w * 0.62;
    CGFloat bridgeX = (w - bridgeW) / 2.0;
    CGFloat bridgeY = CGRectGetMaxY(shellRect) - 32;
    UIBezierPath *bridge = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(bridgeX, bridgeY, bridgeW, 24) cornerRadius:5];
    [[UIColor colorWithRed:0.08 green:0.08 blue:0.09 alpha:1.0] setFill];
    [bridge fill];

    // Draw L & R LED VU Meters inside the bottom bridge
    [self drawVUMeterInRect:CGRectMake(bridgeX + 10, bridgeY + 5, bridgeW - 20, 6) level:self.leftLevel label:@"L" context:ctx];
    [self drawVUMeterInRect:CGRectMake(bridgeX + 10, bridgeY + 13, bridgeW - 20, 6) level:self.rightLevel label:@"R" context:ctx];
}

- (void)drawReelAtCenter:(CGPoint)center radius:(CGFloat)r angle:(CGFloat)angle context:(CGContextRef)ctx {
    // White/cream hub ring
    [[UIColor colorWithRed:0.92 green:0.90 blue:0.86 alpha:1.0] setFill];
    CGContextFillEllipseInRect(ctx, CGRectMake(center.x - r, center.y - r, r * 2, r * 2));

    // Inner dark hole
    CGFloat innerR = r * 0.62;
    [[UIColor colorWithRed:0.10 green:0.10 blue:0.11 alpha:1.0] setFill];
    CGContextFillEllipseInRect(ctx, CGRectMake(center.x - innerR, center.y - innerR, innerR * 2, innerR * 2));

    // 6 rotating teeth inside the hub
    [[UIColor colorWithRed:0.92 green:0.90 blue:0.86 alpha:1.0] setFill];
    for (int i = 0; i < 6; i++) {
        CGFloat a = angle + i * (M_PI / 3.0);
        CGFloat tx = center.x + cosf(a) * (innerR * 0.72);
        CGFloat ty = center.y + sinf(a) * (innerR * 0.72);
        CGContextFillEllipseInRect(ctx, CGRectMake(tx - 2.2, ty - 2.2, 4.4, 4.4));
    }

    // Visual spoke marker on outer ring so rotation is unmistakable
    [[UIColor colorWithRed:0.92 green:0.46 blue:0.16 alpha:1.0] setStroke];
    CGContextSetLineWidth(ctx, 2.0);
    CGContextMoveToPoint(ctx, center.x + cosf(angle) * innerR, center.y + sinf(angle) * innerR);
    CGContextAddLineToPoint(ctx, center.x + cosf(angle) * r, center.y + sinf(angle) * r);
    CGContextStrokePath(ctx);
}

- (void)drawVUMeterInRect:(CGRect)rect level:(float)level label:(NSString *)label context:(CGContextRef)ctx {
    int segments = 14;
    CGFloat segGap = 2.0;
    CGFloat startX = rect.origin.x + 12;
    CGFloat totalW = rect.size.width - 12;
    CGFloat segW = (totalW - (segments - 1) * segGap) / segments;
    int activeSegs = (int)roundf(MIN(1.0f, MAX(0.0f, level)) * segments);

    NSDictionary *lblAttr = @{
        NSFontAttributeName: [UIFont boldSystemFontOfSize:7],
        NSForegroundColorAttributeName: [UIColor colorWithWhite:0.65 alpha:1.0]
    };
    [label drawAtPoint:CGPointMake(rect.origin.x, rect.origin.y - 1) withAttributes:lblAttr];

    for (int i = 0; i < segments; i++) {
        CGRect sr = CGRectMake(startX + i * (segW + segGap), rect.origin.y, segW, rect.size.height);
        BOOL lit = (i < activeSegs);
        if (i >= 11) {
            [[UIColor colorWithRed:0.95 green:0.22 blue:0.20 alpha:(lit ? 1.0 : 0.18)] setFill];
        } else if (i >= 8) {
            [[UIColor colorWithRed:0.98 green:0.72 blue:0.18 alpha:(lit ? 1.0 : 0.18)] setFill];
        } else {
            [[UIColor colorWithRed:0.24 green:0.85 blue:0.45 alpha:(lit ? 1.0 : 0.18)] setFill];
        }
        CGContextFillRect(ctx, sr);
    }
}

@end
