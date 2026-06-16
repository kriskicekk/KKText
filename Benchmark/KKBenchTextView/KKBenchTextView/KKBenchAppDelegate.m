//
//  KKBenchAppDelegate.m
//  KKBenchTextView
//
//  Created by kris on 2026/06/16.
//

#import "KKBenchAppDelegate.h"
#import "KKBenchViewController.h"

@implementation KKBenchAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    KKBenchViewController *controller = [KKBenchViewController new];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:controller];
    self.window.rootViewController = navigationController;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
