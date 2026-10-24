#import <UIKit/UIKit.h>
#import "CPXHomeViewController.h"

@interface CPXAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, retain) UIWindow *window;
@end

@implementation CPXAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    UIWindow *window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[[CPXHomeViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]];
    nav.navigationBar.prefersLargeTitles = YES;

    window.rootViewController = nav;
    window.backgroundColor = [UIColor whiteColor];
    self.window = window;
    [window makeKeyAndVisible];
    return YES;
}

@end
