#import "AppDelegate.h"
#import <AVFoundation/AVFoundation.h>
#import "MainTabBarController.h"
#import "MusicLibrary.h"
#import "PlaybackManager.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [self configureAudioSession];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.09 alpha:1.0];

    // Scan Documents & iPod Library on launch
    [[MusicLibrary sharedLibrary] reloadLibrary];

    MainTabBarController *tabController = [[MainTabBarController alloc] init];
    self.window.rootViewController = tabController;
    [self.window makeKeyAndVisible];

    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    return YES;
}

- (void)configureAudioSession {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error = nil;
    // Playback category ensures audio continues in background and ignores silent switch
    [session setCategory:AVAudioSessionCategoryPlayback error:&error];
    if (error) {
        NSLog(@"AudioSession category error: %@", error);
    }

    // Request highest hardware sample rate (48kHz on iPhone 4S DAC) and low latency buffer
    [session setPreferredSampleRate:48000.0 error:nil];
    [session setPreferredIOBufferDuration:0.023 error:nil];

    error = nil;
    [session setActive:YES error:&error];
    if (error) {
        NSLog(@"AudioSession activate error: %@", error);
    }
}

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<NSString *,id> *)options {
    return [self handleIncomingAudioURL:url];
}

// iOS 8/9 compatibility method
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation {
    return [self handleIncomingAudioURL:url];
}

- (BOOL)handleIncomingAudioURL:(NSURL *)url {
    if (!url || !url.isFileURL) return NO;
    TrackItem *imported = [[MusicLibrary sharedLibrary] importFileAtURL:url];
    if (imported) {
        [[PlaybackManager sharedManager] playTrack:imported inQueue:@[imported]];
        return YES;
    }
    return NO;
}

- (void)applicationWillTerminate:(UIApplication *)application {
    [[UIApplication sharedApplication] endReceivingRemoteControlEvents];
}

@end
