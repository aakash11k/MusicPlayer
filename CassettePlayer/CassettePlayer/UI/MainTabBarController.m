#import "MainTabBarController.h"
#import "NowPlayingViewController.h"
#import "LibraryViewController.h"
#import "SearchViewController.h"

@implementation MainTabBarController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tabBar.barStyle = UIBarStyleBlack;
    self.tabBar.tintColor = [UIColor colorWithRed:0.92 green:0.46 blue:0.16 alpha:1.0];

    NowPlayingViewController *deckVC = [[NowPlayingViewController alloc] init];
    deckVC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Deck" image:nil tag:0];

    UINavigationController *libNav = [[UINavigationController alloc] initWithRootViewController:[[LibraryViewController alloc] init]];
    libNav.navigationBar.barStyle = UIBarStyleBlack;
    libNav.navigationBar.tintColor = [UIColor colorWithRed:0.92 green:0.46 blue:0.16 alpha:1.0];
    libNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Library" image:nil tag:1];

    UINavigationController *searchNav = [[UINavigationController alloc] initWithRootViewController:[[SearchViewController alloc] init]];
    searchNav.navigationBar.barStyle = UIBarStyleBlack;
    searchNav.navigationBar.tintColor = [UIColor colorWithRed:0.92 green:0.46 blue:0.16 alpha:1.0];
    searchNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Search" image:nil tag:2];

    self.viewControllers = @[deckVC, libNav, searchNav];
}

@end
