#include "../common.h"

/*
注入到 CarPlay 进程 (com.apple.CarPlayApp)
功能：强制把 App 加入 CarPlay / 移除默认不可删除的 App / 自定义壁纸 / 5列布局
基于 Ethan Arbuckle 的 CarPlayEnable (Apache-2.0) 移植扩展
*/
%group CARPLAY

struct SBIconImageInfo {
    struct CGSize size;
    double scale;
    double continuousCornerRadius;
};

/*
给 FBSApplicationLibrary 里的 app 强塞 CarPlay 声明，使其出现在 CarPlay 主屏。
排除：用户黑名单(excludedApps) + 用户要求移除的(removedApps) + 系统自带 app
*/
void addCarplayDeclarationsToAppLibrary(id appLibrary)
{
    NSArray *userExcludedApps = [[CPXPreferences sharedInstance] excludedApplications];
    NSArray *removedApps = [[CPXPreferences sharedInstance] removedApplications];
    int added = 0;

    for (id appInfo in objcInvoke(appLibrary, @"allInstalledApplications"))
    {
        if (getIvar(appInfo, @"_carPlayDeclaration") == nil)
        {
            NSString *appBundleID = objcInvoke(appInfo, @"bundleIdentifier");

            /* 用户要求从 CarPlay 移除的（含默认 app） */
            if (removedApps && [removedApps containsObject:appBundleID])
            {
                continue;
            }

            /* 系统 app 默认不加（原生支持 CarPlay 的系统 app 自带声明，不受影响） */
            if ([objcInvoke(appInfo, @"bundleType") isEqualToString:@"User"] == NO)
            {
                if ([appBundleID containsString:@"com.apple."])
                {
                    continue;
                }
            }

            /* 用户黑名单 */
            if (userExcludedApps && [userExcludedApps containsObject:appBundleID])
            {
                continue;
            }

            id carplayDeclaration = [[objc_getClass("CRCarPlayAppDeclaration") alloc] init];
            /* 不能是 template-driven，否则宿主进程会不停找不存在的 template 然后崩溃 */
            objcInvoke_1(carplayDeclaration, @"setSupportsTemplates:", 0);
            objcInvoke_1(carplayDeclaration, @"setSupportsMaps:", 1);
            objcInvoke_1(carplayDeclaration, @"setBundleIdentifier:", appBundleID);
            objcInvoke_1(carplayDeclaration, @"setBundlePath:", objcInvoke(appInfo, @"bundleURL"));
            setIvar(appInfo, @"_carPlayDeclaration", carplayDeclaration);
            [carplayDeclaration release];

            NSArray *newTags = @[@"CarPlayEnable"];
            if (objcInvoke(appInfo, @"tags"))
            {
                newTags = [newTags arrayByAddingObjectsFromArray:objcInvoke(appInfo, @"tags")];
            }
            setIvar(appInfo, @"_tags", newTags);
            added++;
        }
    }

    CPXLog(@"[应用库] 本次强制加入 CarPlay 的 app 数量: %d (黑名单=%lu 移除=%lu)",
           added, (unsigned long)[userExcludedApps count], (unsigned long)[removedApps count]);
}

%hook CARApplication

/*
重建 CarPlay 应用库：默认库里只有原生支持 CarPlay 的 app。
替换成一个包含全部已安装 app 的库，再逐个塞 CarPlay 声明。
同时把用户要求移除的默认 app 直接过滤出库（主屏网格基于应用库构建，库里没有=界面上没有）。
*/
+ (id)_newApplicationLibrary
{
    LOG_LIFECYCLE_EVENT;

    if (![[CPXPreferences sharedInstance] masterEnabled])
    {
        return %orig;
    }

    NSArray *removedApps = [[CPXPreferences sharedInstance] removedApplications];

    id allAppsConfiguration = [[objc_getClass("FBSApplicationLibraryConfiguration") alloc] init];
    objcInvoke_1(allAppsConfiguration, @"setApplicationInfoClass:", objc_getClass("CARApplicationInfo"));
    objcInvoke_1(allAppsConfiguration, @"setApplicationPlaceholderClass:", objc_getClass("FBSApplicationPlaceholder"));
    objcInvoke_1(allAppsConfiguration, @"setAllowConcurrentLoading:", 1);
    objcInvoke_1(allAppsConfiguration, @"setInstalledApplicationFilter:", ^BOOL(id appProxy, NSSet *arg2) {
        NSArray *appTags = objcInvoke(appProxy, @"appTags");
        /* 系统标记为 hidden 的跳过 */
        if ([appTags containsObject:@"hidden"])
        {
            return 0;
        }
        /* 用户要求从 CarPlay 移除的（默认不可删除的 app 就是这样移掉的） */
        NSString *bid = objcInvoke(appProxy, @"bundleIdentifier");
        if (removedApps && bid && [removedApps containsObject:bid])
        {
            CPXLog(@"[移除] 已按用户配置从应用库剔除: %@", bid);
            return 0;
        }
        return 1;
    });

    id allAppsLibrary = objcInvoke_1([objc_getClass("FBSApplicationLibrary") alloc], @"initWithConfiguration:", allAppsConfiguration);
    [allAppsConfiguration release];
    addCarplayDeclarationsToAppLibrary(allAppsLibrary);

    /* CarPlay 基础设施进程，必须保留在库里 */
    NSArray *systemIdentifiers = @[@"com.apple.CarPlayTemplateUIHost", @"com.apple.MusicUIService", @"com.apple.springboard", @"com.apple.InCallService", @"com.apple.CarPlaySettings", @"com.apple.CarPlayApp"];
    for (NSString *systemIdent in systemIdentifiers)
    {
        id appProxy = objcInvoke_1(objc_getClass("LSApplicationProxy"), @"applicationProxyForIdentifier:", systemIdent);
        id appState = objcInvoke(appProxy, @"appState");
        if (objcInvokeT(appState, @"isValid", int) == 1)
        {
            objcInvoke_2(allAppsLibrary, @"addApplicationProxy:withOverrideURL:", appProxy, 0);
        }
    }

    CPXLog(@"[应用库] 重建完成，库内 app 总数: %lu", (unsigned long)[objcInvoke(allAppsLibrary, @"allInstalledApplications") count]);
    return allAppsLibrary;
}

%end

/* CarPlay 主屏图标布局：可开 5 列 */
%hook SBIconListGridLayoutConfiguration

- (int)numberOfPortraitColumns
{
    int columns = %orig;
    if ([[CPXPreferences sharedInstance] masterEnabled] && [[CPXPreferences sharedInstance] fiveColumnIconLayout])
    {
        columns = MAX(5, columns);
    }
    return columns;
}

- (struct SBIconImageInfo)iconImageInfoForGridSizeClass:(unsigned long long)arg1
{
    struct SBIconImageInfo info = %orig;
    if ([[CPXPreferences sharedInstance] masterEnabled] && [[CPXPreferences sharedInstance] fiveColumnIconLayout])
    {
        info.size = CGSizeMake(50, 50);
    }
    return info;
}

%end

/* 通过主屏网格点开一个被强塞进来的 app */
%hook CARApplicationLaunchInfo

+ (id)launchInfoForApplication:(id)arg1 withActivationSettings:(id)arg2
{
    if ([[CPXPreferences sharedInstance] masterEnabled] &&
        [objcInvoke(arg1, @"tags") containsObject:@"CarPlayEnable"])
    {
        LOG_LIFECYCLE_EVENT;
        /* 通知 SpringBoard 托管这个 app 的窗口 */
        [[objc_getClass("NSDistributedNotificationCenter") defaultCenter] postNotificationName:CPX_NOTIFICATION_LAUNCH object:nil userInfo:@{@"identifier": objcInvoke(arg1, @"bundleIdentifier")}];

        /* 记进 App History（dock 的"最近使用"） */
        id sharedApp = [UIApplication sharedApplication];
        id appHistory = objcInvoke(sharedApp, @"_currentAppHistory");

        NSString *previousBundleID = nil;
        NSArray *orderedAppHistory = objcInvoke(appHistory, @"orderedAppHistory");
        if ([orderedAppHistory count] > 0)
        {
            previousBundleID = objcInvoke([orderedAppHistory firstObject], @"bundleIdentifier");
        }

        ((void (*)(id, SEL, id, id))objc_msgSend)(appHistory, NSSelectorFromString(@"_bundleIdentifierDidBecomeVisible:previousBundleIdentifier:"), objcInvoke(arg1, @"bundleIdentifier"), previousBundleID);

        id dashboardRootController = objcInvoke(objcInvoke(sharedApp, @"_currentDashboard"), @"rootViewController");
        id dockController = objcInvoke(dashboardRootController, @"appDockViewController");
        objcInvoke(dockController, @"_refreshAppDock");

        /* 如果已经有原生 CarPlay app 在前台，先关掉它 */
        id dashboard = objcInvoke(sharedApp, @"_currentDashboard");
        assertGotExpectedObject(dashboard, @"CARDashboard");
        NSDictionary *foregroundScenes = objcInvoke(dashboard, @"identifierToForegroundAppScenesMap");
        if ([[foregroundScenes allKeys] count] > 0)
        {
            id homeButtonEvent = objcInvoke_2(objc_getClass("CAREvent"), @"eventWithType:context:", 1, @"Close carplay app");
            assertGotExpectedObject(homeButtonEvent, @"CAREvent");
            objcInvoke_1(dashboard, @"handleEvent:", homeButtonEvent);
        }

        return nil;
    }

    return %orig;
}

%end

/* 通过 dock 点开被强塞的 app */
%hook CARAppDockViewController

- (void)_dockButtonPressed:(id)arg1
{
    %orig;

    if (![[CPXPreferences sharedInstance] masterEnabled])
    {
        return;
    }

    NSString *bundleID = objcInvoke(arg1, @"bundleIdentifier");
    id sharedApp = [UIApplication sharedApplication];
    id appLibrary = objcInvoke(sharedApp, @"sharedApplicationLibrary");
    id selectedAppInfo = objcInvoke_1(appLibrary, @"applicationInfoForBundleIdentifier:", bundleID);
    if (selectedAppInfo && [objcInvoke(selectedAppInfo, @"tags") containsObject:@"CarPlayEnable"])
    {
        objcInvoke_1(self, @"setDockEnabled:", 1);
    }
}

%end

/* app 安装/卸载后的应用库刷新，补塞声明 */
%hook _CARDashboardHomeViewController

- (id)initWithEnvironment:(id)arg1
{
    id _self = %orig;
    [[objc_getClass("NSDistributedNotificationCenter") defaultCenter] addObserverForName:CPX_NOTIFICATION_PREFS_CHANGED object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        [[CPXPreferences sharedInstance] reloadPreferences];
        if ([note.object isEqualToString:kPrefsAppLibraryChanged])
        {
            id updatedLibrary = objcInvoke(objc_getClass("CARApplication"), @"_newApplicationLibrary");
            objcInvoke_1(_self, @"setLibrary:", updatedLibrary);
            objcInvoke(_self, @"_handleAppLibraryRefresh");
        }
        /* 壁纸变化由 UIImage 钩子在下次取图时自动生效，无需额外处理 */
    }];

    return _self;
}

- (void)_handleAppLibraryRefresh
{
    if ([[CPXPreferences sharedInstance] masterEnabled])
    {
        id appLibrary = objcInvoke(_self, @"library");
        addCarplayDeclarationsToAppLibrary(appLibrary);
    }
    %orig;
}

%end

/* 主屏图标：长按 1.5 秒以完整模式启动（对原生 app 也有用） */
%hook CARIconView

%new
- (void)handleLaunchAppInNormalMode:(UILongPressGestureRecognizer *)gesture
{
    if (gesture.state == UIGestureRecognizerStateBegan)
    {
        id icon = objcInvoke(self, @"icon");
        assertGotExpectedObject(icon, @"SBIcon");
        NSString *bundleID = objcInvoke(icon, @"applicationBundleID");

        [[objc_getClass("NSDistributedNotificationCenter") defaultCenter] postNotificationName:CPX_NOTIFICATION_LAUNCH object:nil userInfo:@{@"identifier": bundleID}];

        id sharedApp = [UIApplication sharedApplication];
        id appHistory = objcInvoke(sharedApp, @"_currentAppHistory");

        NSString *previousBundleID = nil;
        NSArray *orderedAppHistory = objcInvoke(appHistory, @"orderedAppHistory");
        if ([orderedAppHistory count] > 0)
        {
            previousBundleID = objcInvoke([orderedAppHistory firstObject], @"bundleIdentifier");
        }
        ((void (*)(id, SEL, id, id))objc_msgSend)(appHistory, NSSelectorFromString(@"_bundleIdentifierDidBecomeVisible:previousBundleIdentifier:"), bundleID, previousBundleID);

        id dashboardRootController = objcInvoke(objcInvoke(sharedApp, @"_currentDashboard"), @"rootViewController");
        id dockController = objcInvoke(dashboardRootController, @"appDockViewController");
        objcInvoke(dockController, @"_refreshAppDock");
    }
}

- (id)initWithConfigurationOptions:(unsigned long long)arg1 listLayoutProvider:(id)arg2
{
    id iconView = %orig;
    UILongPressGestureRecognizer *launchGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:iconView action:NSSelectorFromString(@"handleLaunchAppInNormalMode:")];
    launchGesture.minimumPressDuration = 1.5;
    [iconView addGestureRecognizer:launchGesture];
    [launchGesture release];
    return iconView;
}

%end

/* ======== 自定义壁纸 ======== */

/*
路径 1：CRSUIWallpaper（CarPlayKit 系壁纸对象）。
iOS 16 上该类若不存在，Logos 会静默跳过此 hook（安全），由路径 2 + 侦查日志兜底。
*/
@interface CRSUIWallpaper : NSObject
@end

%hook CRSUIWallpaper

- (UIImage *)wallpaperImageCompatibleWithTraitCollection:(id)traitCollection
{
    UIImage *origImage = %orig;
    if ([[CPXPreferences sharedInstance] wallpaperEnabled])
    {
        UIImage *custom = [[CPXPreferences sharedInstance] customWallpaperImage];
        if (custom)
        {
            return custom;
        }
    }
    return origImage;
}

%end

/*
路径 2：资产图替换。CarPlay 选中壁纸最终都是按资源名取 UIImage。
把名字含 "wallpaper" 的（或用户在设置里指定覆盖名的）资产图换成用户的自定义图。
同时记录前 30 秒所有 imageNamed 调用，用于定位壁纸真实资源名。
*/
static NSMutableSet *gCPXImageNameSeen = nil;
static CFAbsoluteTime gCPXImageNameWindowEnd = 0.0;

static BOOL CPXShouldReplaceImageName(NSString *name)
{
    if (![[CPXPreferences sharedInstance] wallpaperEnabled])
    {
        return NO;
    }
    if (![[CPXPreferences sharedInstance] customWallpaperImage])
    {
        return NO;
    }
    NSString *override = [[CPXPreferences sharedInstance] wallpaperResourceOverride];
    if ([override length] > 0)
    {
        return [name isEqualToString:override] || [[name stringByDeletingPathExtension] isEqualToString:override];
    }
    NSString *low = [name lowercaseString];
    return [low containsString:@"wallpaper"] || [low containsString:@"wall_paper"];
}

%hook UIImage

+ (UIImage *)imageNamed:(NSString *)name
{
    UIImage *img = %orig;

    /* 侦查：记录 CarPlay 进程里的取图请求（限时 + 去重 + 封顶，避免刷爆日志） */
    @try
    {
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (gCPXImageNameWindowEnd == 0.0)
        {
            gCPXImageNameWindowEnd = now + 30.0;
        }
        if (now < gCPXImageNameWindowEnd && name)
        {
            if (!gCPXImageNameSeen)
            {
                gCPXImageNameSeen = [[NSMutableSet alloc] init];
            }
            if ([gCPXImageNameSeen count] < 300 && ![gCPXImageNameSeen containsObject:name])
            {
                [gCPXImageNameSeen addObject:name];
                CPXLog(@"[壁纸资产] imageNamed: %@ -> %@", name, img ? @"OK" : @"nil");
            }
        }
    }
    @catch (NSException *e)
    {
        /* ignore */
    }

    if (name && CPXShouldReplaceImageName(name))
    {
        UIImage *custom = [[CPXPreferences sharedInstance] customWallpaperImage];
        if (custom)
        {
            return custom;
        }
    }
    return img;
}

+ (UIImage *)imageWithContentsOfFile:(NSString *)path
{
    UIImage *img = %orig;
    @try
    {
        if (path && [[path lowercaseString] containsString:@"wallpaper"] &&
            CPXShouldReplaceImageName([path lastPathComponent]))
        {
            UIImage *custom = [[CPXPreferences sharedInstance] customWallpaperImage];
            if (custom)
            {
                return custom;
            }
        }
    }
    @catch (NSException *e)
    {
        /* ignore */
    }
    return img;
}

%end

%end

%ctor
{
    @autoreleasepool
    {
        BAIL_IF_UNSUPPORTED_IOS;

        if ([[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.CarPlayApp"])
        {
            CPXLog(@"========== CarPlayX %@ 启动（CarPlay 进程）==========", CPX_VERSION);
            CPXDumpWallpaperClasses();
            %init(CARPLAY);
        }
    }
}
