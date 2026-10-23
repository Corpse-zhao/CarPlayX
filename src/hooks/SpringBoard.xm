#include "../common.h"
#include "../CPXCarPlayWindow.h"

/*
注入到 SpringBoard：
1) 接收 CarPlay 进程的启动通知，把被强塞的 app 实际托管到车机屏上
2) 锁屏保活 / 场景布局修正（移植自 CarPlayEnable）
3) 给设置面板提供已安装 app 清单（含图标）
*/
%group SPRINGBOARD

int (*orig_BKSDisplayServicesSetScreenBlanked)(int);

/* 锁屏时不挂起被托管到 CarPlay 的 app */
%hook SBSuspendedUnderLockManager

- (int)_shouldBeBackgroundUnderLockForScene:(id)arg2 withSettings:(id)arg3
{
    BOOL shouldBackground = %orig;
    if (shouldBackground && [[CPXPreferences sharedInstance] masterEnabled])
    {
        NSString *sceneAppBundleID = objcInvoke(objcInvoke(objcInvoke(arg2, @"client"), @"process"), @"bundleIdentifier");
        NSArray *lockAssertions = objc_getAssociatedObject([UIApplication sharedApplication], &kPropertyKey_lockAssertionIdentifiers);
        if (lockAssertions && [lockAssertions containsObject:sceneAppBundleID])
        {
            LOG_LIFECYCLE_EVENT;
            shouldBackground = NO;
        }
    }

    return shouldBackground;
}

%end

%hook SpringBoard

/* CarPlay 主屏上点了被强塞的 app 图标 */
%new
- (void)handleCarPlayLaunchNotification:(id)notification
{
    if (![[CPXPreferences sharedInstance] masterEnabled])
    {
        return;
    }
    LOG_LIFECYCLE_EVENT;
    NSString *identifier = [notification userInfo][@"identifier"];
    CPXLog(@"[托管] 收到启动请求: %@", identifier);
    objcInvoke_1(self, @"launchAppOnCarplay:", identifier);
}

%new
- (void)launchAppOnCarplay:(NSString *)identifier
{
    LOG_LIFECYCLE_EVENT;
    @try
    {
        /* 先关掉已托管的窗口 */
        id liveCarplayWindow = objcInvoke([UIApplication sharedApplication], @"liveCarplayWindow");
        if (liveCarplayWindow != nil)
        {
            objcInvoke(liveCarplayWindow, @"dismiss");
            objc_setAssociatedObject([UIApplication sharedApplication], &kPropertyKey_liveCarplayWindow, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }

        CPXCarPlayWindow *window = [[CPXCarPlayWindow alloc] initWithBundleIdentifier:identifier];
        if (window)
        {
            objc_setAssociatedObject(self, &kPropertyKey_liveCarplayWindow, window, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [window release];
            CPXLog(@"[托管] %@ 已启动托管窗口", identifier);
        }
        else
        {
            CPXLog(@"[托管] %@ 托管窗口创建失败（返回 nil）", identifier);
        }
    }
    @catch (NSException *exception)
    {
        CPXLog(@"[托管] 启动失败: %@", exception);
    }
}

- (void)applicationDidFinishLaunching:(id)arg1
{
    LOG_LIFECYCLE_EVENT;
    [[objc_getClass("NSDistributedNotificationCenter") defaultCenter] addObserver:self selector:NSSelectorFromString(@"handleCarPlayLaunchNotification:") name:CPX_NOTIFICATION_LAUNCH object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(carplayIsConnectedChanged) name:@"CarPlayIsConnectedDidChange" object:nil];

    NSMutableArray *appIdentifiersToIgnoreLockAssertions = [[NSMutableArray alloc] init];
    objc_setAssociatedObject(self, &kPropertyKey_lockAssertionIdentifiers, appIdentifiersToIgnoreLockAssertions, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [appIdentifiersToIgnoreLockAssertions release];

    %orig;

    /* 设置面板请求 app 清单：全量返回（含系统 app，供"移除默认应用"用），带图标 */
    NSOperationQueue *notificationQueue = [[NSOperationQueue alloc] init];
    [notificationQueue release];
    [[objc_getClass("NSDistributedNotificationCenter") defaultCenter] addObserverForName:CPX_NOTIFICATION_APP_DATA object:kPrefsAppDataRequesting queue:notificationQueue usingBlock:^(NSNotification *note) {
        @autoreleasepool
        {
            id appController = objcInvoke(objc_getClass("SBApplicationController"), @"sharedInstance");
            NSMutableArray *appList = [[NSMutableArray alloc] init];
            int skipped = 0;
            for (id appInfo in objcInvoke(appController, @"allInstalledApplications"))
            {
                NSString *identifier = objcInvoke(appInfo, @"bundleIdentifier");
                if (!identifier)
                {
                    skipped++;
                    continue;
                }
                BOOL isStock = (![objcInvoke(appInfo, @"bundleType") isEqualToString:@"User"] && [identifier containsString:@"com.apple."]);
                /* CarPlay 基础设施进程不对外展示 */
                NSSet *infraIdentifiers = [NSSet setWithArray:@[@"com.apple.CarPlayTemplateUIHost", @"com.apple.MusicUIService", @"com.apple.springboard", @"com.apple.InCallService", @"com.apple.CarPlaySettings", @"com.apple.CarPlayApp"]];
                if ([infraIdentifiers containsObject:identifier])
                {
                    skipped++;
                    continue;
                }

                UIImage *appIconImage = objcInvoke_3(objc_getClass("UIImage"), @"_applicationIconImageForBundleIdentifier:format:scale:", identifier, 0, [UIScreen mainScreen].scale);
                NSData *iconImageData = UIImagePNGRepresentation(appIconImage);

                BOOL hasCarPlay = NO;
                @try
                {
                    hasCarPlay = (getIvar(appInfo, @"_carPlayDeclaration") != nil);
                }
                @catch (NSException *e)
                {
                    hasCarPlay = NO;
                }

                NSDictionary *appInfoDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                             objcInvoke(appInfo, @"displayName") ?: identifier, @"name",
                                             identifier, @"bundleID",
                                             iconImageData ?: [NSData data], @"iconImage",
                                             @(isStock), @"isStock",
                                             @(hasCarPlay), @"hasCarPlay",
                                             nil];
                [appList addObject:appInfoDict];
            }
            CPXLog(@"[设置面板] 提供 app 清单: %lu 个 (跳过 %d)", (unsigned long)[appList count], skipped);
            NSDictionary *replyDict = [NSDictionary dictionaryWithObject:appList forKey:@"appList"];
            [[objc_getClass("NSDistributedNotificationCenter") defaultCenter] postNotification:[NSNotification notificationWithName:CPX_NOTIFICATION_APP_DATA object:kPrefsAppDataReceiving userInfo:replyDict]];
            [appList release];
        }
    }];
}

%new
- (id)liveCarplayWindow
{
    return objc_getAssociatedObject(self, &kPropertyKey_liveCarplayWindow);
}

/* CarPlay 断开时收掉托管窗口 */
%new
- (void)carplayIsConnectedChanged
{
    LOG_LIFECYCLE_EVENT;
    id liveCarplayWindow = objcInvoke(self, @"liveCarplayWindow");
    if (liveCarplayWindow && !getCarplayCADisplay())
    {
        dispatch_sync(dispatch_get_main_queue(), ^(void) {
            objcInvoke(liveCarplayWindow, @"dismiss");
        });
    }
}

%end

%hook SBSceneView

/* CarPlay 托管窗口的横竖屏变换，face-up/face-down 会抛异常，强制落到 landscape */
- (void)_updateReferenceSize:(struct CGSize)arg1 andOrientation:(long long)arg2
{
    if (arg2 > 4)
    {
        return %orig(arg1, 3);
    }
    %orig;
}

%end

%hook FBScene

/* 防止托管在 CarPlay 上的 app 因为主屏启动其它 app 而被切后台 */
- (void)updateSettings:(id)arg1 withTransitionContext:(id)arg2 completion:(void *)arg3
{
    id sceneClient = objcInvoke(self, @"client");
    if (sceneClient && [sceneClient respondsToSelector:NSSelectorFromString(@"process")] && [[CPXPreferences sharedInstance] masterEnabled])
    {
        NSString *sceneAppBundleID = objcInvoke(objcInvoke(sceneClient, @"process"), @"bundleIdentifier");
        NSArray *lockAssertions = objc_getAssociatedObject([UIApplication sharedApplication], &kPropertyKey_lockAssertionIdentifiers);
        if (lockAssertions && [lockAssertions containsObject:sceneAppBundleID])
        {
            if (objcInvokeT(arg1, @"isForeground", BOOL) == NO)
            {
                return;
            }
        }
    }

    %orig;
}

%end

%hook SBMainSwitcherViewController

/* App 切换器跟随设备物理方向（而不是 CarPlay 上 app 的方向） */
- (void)_updateContentViewInterfaceOrientation:(int)arg1
{
    if (objcInvoke([UIApplication sharedApplication], @"liveCarplayWindow") != nil)
    {
        int deviceOrientation = [[UIDevice currentDevice] orientation];
        return %orig(deviceOrientation);
    }

    return %orig;
}

%end

%hook SBDeviceApplicationSceneView

%new
- (BOOL)isMainScreenCounterpartToLiveCarplayApp
{
    id liveCarplayWindow = objcInvoke([UIApplication sharedApplication], @"liveCarplayWindow");
    if (liveCarplayWindow != nil)
    {
        id liveAppViewController = [liveCarplayWindow appViewController];
        id carplaySceneHandle = objcInvoke(liveAppViewController, @"sceneHandle");
        if (carplaySceneHandle && [carplaySceneHandle isEqual:objcInvoke(self, @"sceneHandle")])
        {
            id carplayAppViewController = getIvar(liveAppViewController, @"_deviceAppViewController");
            id carplayAppSceneView = objcInvoke(carplayAppViewController, @"_sceneView");
            return carplayAppSceneView && [self isEqual:carplayAppSceneView] == NO;
        }
    }

    return NO;
}

- (void)layoutSubviews
{
    %orig;
    @try
    {
        BOOL isCarplayCounterpart = objcInvokeT(self, @"isMainScreenCounterpartToLiveCarplayApp", BOOL);
        if (isCarplayCounterpart)
        {
            int currentDisplayMode = objcInvokeT(self, @"displayMode", int);
            BOOL isHostingAnApp = currentDisplayMode == 4;
            if (isHostingAnApp)
            {
                return;
            }

            objcInvoke(self, @"rotateToDeviceOrientation");

            UIView *backgroundView = objcInvoke(self, @"backgroundView");
            int deviceOrientation = [[UIDevice currentDevice] orientation];
            BOOL bgIsLandscape = [backgroundView frame].size.width > [backgroundView frame].size.height;
            BOOL deviceIsLandscape = UIInterfaceOrientationIsLandscape((UIInterfaceOrientation)deviceOrientation);
            if (bgIsLandscape == deviceIsLandscape)
            {
                objcInvoke(self, @"drawCarplayPlaceholder");
            }
        }
    }
    @catch (NSException *e)
    {
        /* layout 高频路径，绝不能崩 */
    }
}

%new
- (void)rotateToDeviceOrientation
{
    UIView *backgroundView = objcInvoke(self, @"backgroundView");

    id orientationTransformedView = nil;
    id _candidate = [backgroundView superview];
    while (_candidate != nil)
    {
        if (_candidate && [_candidate isKindOfClass:objc_getClass("SBOrientationTransformWrapperView")])
        {
            orientationTransformedView = _candidate;
            break;
        }

        _candidate = [_candidate superview];
    }

    if (orientationTransformedView != nil)
    {
        int deviceOrientation = [[UIDevice currentDevice] orientation];
        objcInvoke_1(orientationTransformedView, @"setContentOrientation:", deviceOrientation);
    }
}

/* 主屏上显示"该 app 正在 CarPlay 屏幕上运行"的占位界面 */
%new
- (void)drawCarplayPlaceholder
{
    int deviceOrientation = [[UIDevice currentDevice] orientation];
    UIView *backgroundView = objcInvoke(self, @"backgroundView");
    id _drawnForOrientation = objc_getAssociatedObject(backgroundView, &kPropertyKey_didDrawPlaceholder);
    int drawnForOrientation = (_drawnForOrientation) ? [_drawnForOrientation intValue] : -1;
    if (drawnForOrientation != deviceOrientation)
    {
        if (drawnForOrientation > 0)
        {
            for (UIView *subview in [backgroundView subviews])
            {
                if ([subview isKindOfClass:[UILabel class]])
                {
                    [subview removeFromSuperview];
                }
            }
        }

        objc_setAssociatedObject(backgroundView, &kPropertyKey_didDrawPlaceholder, @(deviceOrientation), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        CGRect screenBounds = ((CGRect (*)(id, SEL, int))objc_msgSend)([UIScreen mainScreen], NSSelectorFromString(@"boundsForOrientation:"), deviceOrientation);

        UILabel *hostedOnCarplayLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 300, screenBounds.size.width, 50)];
        hostedOnCarplayLabel.text = @"正在 CarPlay 屏幕上运行";
        hostedOnCarplayLabel.textAlignment = NSTextAlignmentCenter;
        hostedOnCarplayLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightSemibold];
        hostedOnCarplayLabel.center = [backgroundView center];
        [backgroundView addSubview:hostedOnCarplayLabel];
        [hostedOnCarplayLabel release];
    }

    objcInvoke_1(backgroundView, @"setWallpaperStyle:", 18);

    id animationFactory = objcInvoke(objc_getClass("SBApplicationSceneView"), @"defaultDisplayModeAnimationFactory");
    objcInvoke_3(self, @"setDisplayMode:animationFactory:completion:", 1, animationFactory, nil);
}

- (void)setDisplayMode:(int)arg1 animationFactory:(id)arg2 completion:(void *)arg3
{
    BOOL isCarplayCounterpart = objcInvokeT(self, @"isMainScreenCounterpartToLiveCarplayApp", BOOL);
    BOOL requestingLiveContent = arg1 == 4;
    if (requestingLiveContent && isCarplayCounterpart)
    {
        /* app 已在 CarPlay 屏上，主屏保持占位模式 */
        %orig(1, arg2, arg3);
        return;
    }

    %orig;
}

%end

%hook UIScreen

%new
- (CGRect)boundsForOrientation:(int)orientation
{
    CGFloat width = [self bounds].size.width;
    CGFloat height = [self bounds].size.height;

    CGRect bounds = CGRectZero;
    if (UIInterfaceOrientationIsLandscape((UIInterfaceOrientation)orientation))
    {
        bounds.size = CGSizeMake(MAX(width, height), MIN(width, height));
    }
    else
    {
        bounds.size = CGSizeMake(MIN(width, height), MAX(width, height));
    }

    return bounds;
}

%end

/* 主屏息屏时，若 CarPlay 上有托管 app，恢复渲染（不点亮屏幕） */
int hook_BKSDisplayServicesSetScreenBlanked(int arg1)
{
    id liveCarplayWindow = objcInvoke([UIApplication sharedApplication], @"liveCarplayWindow");
    if (arg1 == 1 && liveCarplayWindow != nil)
    {
        NSArray *lockAssertions = objc_getAssociatedObject([UIApplication sharedApplication], &kPropertyKey_lockAssertionIdentifiers);

        id sceneHandle = objcInvoke([liveCarplayWindow appViewController], @"sceneHandle");
        id appScene = objcInvoke(sceneHandle, @"sceneIfExists");
        if (appScene)
        {
            NSString *sceneAppBundleID = objcInvoke(objcInvoke(objcInvoke(appScene, @"client"), @"process"), @"bundleIdentifier");
            if (lockAssertions && [lockAssertions containsObject:sceneAppBundleID])
            {
                orig_BKSDisplayServicesSetScreenBlanked(1);

                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    orig_BKSDisplayServicesSetScreenBlanked(0);
                });
                return 0;
            }
        }
    }

    return orig_BKSDisplayServicesSetScreenBlanked(arg1);
}

%end

%ctor
{
    @autoreleasepool
    {
        BAIL_IF_UNSUPPORTED_IOS;

        if ([[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"])
        {
            if (CPX_DISABLED)
            {
                return;
            }
            @try
            {
                CPXLog(@"========== CarPlayX %@ 启动（SpringBoard 进程）==========", CPX_VERSION);
                CPXDumpWallpaperClasses();
                %init(SPRINGBOARD);
                void *_BKSDisplayServicesSetScreenBlanked = dlsym(dlopen(NULL, 0), "BKSDisplayServicesSetScreenBlanked");
                if (_BKSDisplayServicesSetScreenBlanked)
                {
                    MSHookFunction(_BKSDisplayServicesSetScreenBlanked, (void *)hook_BKSDisplayServicesSetScreenBlanked, (void **)&orig_BKSDisplayServicesSetScreenBlanked);
                }
                CPXLog(@"[启动] SpringBoard 侧钩子全部挂载完成");
            }
            @catch (NSException *e)
            {
                CPXLog(@"[启动] SpringBoard 侧初始化异常（已忽略）: %@", e);
            }
        }
    }
}
