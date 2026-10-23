#include "common.h"
#include "CPXCarPlayWindow.h"

/*
Find the CADisplay handling the CarPlay stuff
*/
id getCarplayCADisplay(void)
{
    id carplayAVDisplay = objcInvoke(objc_getClass("AVExternalDevice"), @"currentCarPlayExternalDevice");
    if (!carplayAVDisplay)
    {
        return nil;
    }

    NSArray *screenIDs = objcInvoke(carplayAVDisplay, @"screenIDs");
    if (![screenIDs count])
    {
        return nil;
    }
    NSString *carplayDisplayUniqueID = screenIDs[0];
    for (id display in objcInvoke(objc_getClass("CADisplay"), @"displays"))
    {
        if ([carplayDisplayUniqueID isEqualToString:objcInvoke(display, @"uniqueId")])
        {
            return display;
        }
    }

    return nil;
}

@implementation CPXCarPlayWindow

- (id)initWithBundleIdentifier:(id)identifier
{
    if ((self = [super init]))
    {
        _observers = [[NSMutableArray alloc] init];
        [[CPXPreferences sharedInstance] reloadPreferences];

        /* Start in landscape */
        self.orientation = 3;

        self.sessionStatus = objcInvoke([objc_getClass("CARSessionStatus") alloc], @"initForCarPlayShell");

        self.application = objcInvoke_1(objcInvoke(objc_getClass("SBApplicationController"), @"sharedInstance"), @"applicationWithBundleIdentifier:", identifier);
        assertGotExpectedObject(self.application, @"SBApplication");

        if (_drawOnMainScreen)
        {
            self.rootWindow = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
            ((void (*)(id, SEL, int, int, int, int))objc_msgSend)(self.rootWindow, NSSelectorFromString(@"_rotateWindowToOrientation:updateStatusBar:duration:skipCallbacks:"), 3, 1, 0, 0);
        }
        else
        {
            id carplayExternalDisplay = getCarplayCADisplay();
            assertGotExpectedObject(carplayExternalDisplay, @"CADisplay");

            id displayConfiguration = objcInvoke_2([objc_getClass("FBSDisplayConfiguration") alloc], @"initWithCADisplay:isMainDisplay:", carplayExternalDisplay, 0);
            assertGotExpectedObject(displayConfiguration, @"FBSDisplayConfiguration");

            /* Create window on the Carplay screen */
            self.rootWindow = objcInvoke_1([objc_getClass("UIRootSceneWindow") alloc], @"initWithDisplayConfiguration:", displayConfiguration);
        }

        [self.rootWindow.layer setCornerRadius:13.0f];
        [self.rootWindow.layer setMasksToBounds:YES];
        [self setupWallpaperBackground];
        [self setupDock];

        [self setupLiveAppView];

        CGRect rootWindowFrame = [[self rootWindow] frame];

        self.appContainerView = [[UIView alloc] initWithFrame:CGRectMake(CARPLAY_DOCK_WIDTH, rootWindowFrame.origin.y, rootWindowFrame.size.width - CARPLAY_DOCK_WIDTH, rootWindowFrame.size.height)];
        [[self appContainerView] setBackgroundColor:[UIColor clearColor]];
        [[self rootWindow] addSubview:[self appContainerView]];
        [self.appContainerView release];

        [self setupLaunchImage];

        [[self appContainerView] addSubview:objcInvoke(self.appViewController, @"view")];
        [self resizeAppViewForOrientation:self.orientation fullscreen:NO forceUpdate:YES];

        [[self rootWindow] setAlpha:0];
        [[self rootWindow] setHidden:0];

        /* 让息屏后动画/视频仍可渲染（不会真的点亮屏幕） */
        orig_BKSDisplayServicesSetScreenBlanked(0);

        [UIView animateWithDuration:1.0 animations:^(void)
        {
            [[self rootWindow] setAlpha:1];
        } completion:nil];

        /* 主屏上给被托管的 app 画占位界面 */
        id currentSceneHandle = objcInvoke(self.appViewController, @"sceneHandle");
        id mainSceneLayoutController = objcInvoke(objc_getClass("SBMainDisplaySceneLayoutViewController"), @"mainDisplaySceneLayoutViewController");
        id liveAppSceneControllers = objcInvoke(mainSceneLayoutController, @"appViewControllers");
        for (id appSceneLayoutController in liveAppSceneControllers)
        {
            id appSceneController = objcInvoke(appSceneLayoutController, @"_applicationSceneViewController");
            id appSceneView = objcInvoke(appSceneController, @"_sceneView");
            id appSceneHandle = objcInvoke(appSceneView, @"sceneHandle");
            if ([appSceneHandle isEqual:currentSceneHandle])
            {
                objcInvoke(appSceneView, @"drawCarplayPlaceholder");
            }
        }

        /* Dock 对齐方式变化的通知 */
        id observer = [[objc_getClass("NSDistributedNotificationCenter") defaultCenter] addObserverForName:CPX_NOTIFICATION_PREFS_CHANGED object:@"dockAlignment" queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            [[CPXPreferences sharedInstance] reloadPreferences];
            [self setupDock];
            [self resizeAppViewForOrientation:_orientation fullscreen:_isFullscreen forceUpdate:YES];
        }];
        [_observers addObject:observer];
        [observer release];

        _screenTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleScreenTapped)];
        id systemGestureManager = objcInvoke(objc_getClass("_UISystemGestureManager"), @"sharedInstance");
        id identity = objcInvoke(objcInvoke(self.rootWindow, @"displayConfiguration"), @"identity");
        objcInvoke_2(systemGestureManager, @"addGestureRecognizer:toDisplayWithIdentity:", _screenTapRecognizer, identity);
    }

    return self;
}

- (void)setupWallpaperBackground
{
    CGRect rootWindowFrame = [[self rootWindow] frame];

    UIImageView *wallpaperImageView = [[UIImageView alloc] initWithFrame:rootWindowFrame];

    /* 优先用用户自定义壁纸（配合 CarPlayX 设置面板），否则回退系统 CarPlay 壁纸 */
    UIImage *wallpaperImage = nil;
    if ([[CPXPreferences sharedInstance] masterEnabled] && [[CPXPreferences sharedInstance] wallpaperEnabled])
    {
        wallpaperImage = [[CPXPreferences sharedInstance] customWallpaperImage];
    }
    if (!wallpaperImage)
    {
        id defaultWallpaper = objcInvoke(objc_getClass("CRSUIWallpaperPreferences"), @"defaultWallpaper");
        if (defaultWallpaper)
        {
            wallpaperImage = objcInvoke_1(defaultWallpaper, @"wallpaperImageCompatibleWithTraitCollection:", nil);
        }
    }
    [wallpaperImageView setImage:wallpaperImage];

    UIVisualEffectView *wallpaperBlurView = [[UIVisualEffectView alloc] initWithEffect:objcInvoke_1(objc_getClass("UIBlurEffect"), @"effectWithBlurRadius:", 10.0)];
    [wallpaperBlurView setFrame:rootWindowFrame];
    [wallpaperImageView addSubview:wallpaperBlurView];
    [wallpaperBlurView release];
    [[self rootWindow] addSubview:wallpaperImageView];
    [wallpaperImageView release];
}

- (void)setupDock
{
    if (_dockView)
    {
        [_dockView removeFromSuperview];
    }

    CGRect rootWindowFrame = [[self rootWindow] frame];
    BOOL rightHandDock = [self shouldUseRightHandDock];

    CGFloat dockXOrigin = (rightHandDock) ? rootWindowFrame.size.width - CARPLAY_DOCK_WIDTH : 0;
    self.dockView = [[UIView alloc] initWithFrame:CGRectMake(dockXOrigin, rootWindowFrame.origin.y, CARPLAY_DOCK_WIDTH, rootWindowFrame.size.height)];

    /* Dock 毛玻璃效果 */
    id blurEffect = objcInvoke_1(objc_getClass("UIBlurEffect"), @"effectWithBlurRadius:", 20.0);
    UIVisualEffectView *effectsView = [[UIVisualEffectView alloc] init];
    [effectsView setFrame:CGRectMake(0, 0, CARPLAY_DOCK_WIDTH, rootWindowFrame.size.height)];
    id colorEffect = objcInvoke_1(objc_getClass("UIColorEffect"), @"colorEffectSaturate:", 2.0);
    id darkEffect = objcInvoke_3(objc_getClass("UIVisualEffect"), @"effectCompositingColor:withMode:alpha:", [UIColor blackColor], 7, 0.6);
    NSArray *effects = [NSArray arrayWithObjects:darkEffect, colorEffect, blurEffect, nil];
    objcInvoke_1(effectsView, @"setBackgroundEffects:", effects);
    [self.dockView addSubview:effectsView];
    [effectsView release];

    [[self rootWindow] addSubview:self.dockView];

    NSBundle *carplayBundle = [NSBundle bundleWithPath:@"/System/Library/CoreServices/CarPlay.app"];
    UITraitCollection *carplayTrait = [UITraitCollection traitCollectionWithUserInterfaceIdiom:(UIUserInterfaceIdiom)3];
    UITraitCollection *interfaceStyleTrait = [UITraitCollection traitCollectionWithUserInterfaceStyle:(UIUserInterfaceStyle)1];
    UITraitCollection *traitCollection = [UITraitCollection traitCollectionWithTraitsFromCollections:@[carplayTrait, interfaceStyleTrait]];

    CGFloat buttonSize = 35;
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImage *homeButtonLightImage = [[UIImage imageNamed:@"CarStatusBarIconsHomeButton" inBundle:carplayBundle compatibleWithTraitCollection:traitCollection] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [closeButton setImage:homeButtonLightImage forState:UIControlStateNormal];
    [closeButton addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [closeButton setFrame:CGRectMake((CARPLAY_DOCK_WIDTH - buttonSize) / 2, rootWindowFrame.size.height - buttonSize, buttonSize, buttonSize)];
    [closeButton setTintColor:[UIColor whiteColor]];
    [self.dockView addSubview:closeButton];

    id imageConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightLight];

    buttonSize = 30;

    UIButton *fullscreenButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [fullscreenButton setImage:[UIImage systemImageNamed:@"arrow.up.left.and.arrow.down.right" withConfiguration:imageConfiguration] forState:UIControlStateNormal];
    [fullscreenButton addTarget:self action:@selector(enterFullscreen) forControlEvents:UIControlEventTouchUpInside];
    [fullscreenButton setFrame:CGRectMake((CARPLAY_DOCK_WIDTH - buttonSize) / 2, 10, buttonSize, buttonSize)];
    [fullscreenButton setTintColor:[UIColor whiteColor]];
    [self.dockView addSubview:fullscreenButton];

    UIButton *rotateButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [rotateButton setImage:[UIImage systemImageNamed:@"rotate.right" withConfiguration:imageConfiguration] forState:UIControlStateNormal];
    [rotateButton addTarget:self action:@selector(handleRotate) forControlEvents:UIControlEventTouchUpInside];
    [rotateButton setFrame:CGRectMake((CARPLAY_DOCK_WIDTH - buttonSize) / 2, fullscreenButton.frame.origin.y + 10 + buttonSize, buttonSize, buttonSize)];
    [rotateButton setTintColor:[UIColor whiteColor]];
    [self.dockView addSubview:rotateButton];
}

- (void)setupLaunchImage
{
    LOG_LIFECYCLE_EVENT;
    id launchImageSnapshotManifest = objcInvoke_1([objc_getClass("XBApplicationSnapshotManifest") alloc], @"initWithApplicationInfo:", objcInvoke(self.application, @"info"));

    id appSnapshot = nil;
    for (id snapshotGroup in objcInvoke(launchImageSnapshotManifest, @"_allSnapshotGroups"))
    {
        for (id snapshotCandidate in objcInvoke(snapshotGroup, @"snapshots"))
        {
            UIInterfaceOrientation snapshotOrientation = (UIInterfaceOrientation)objcInvokeT(snapshotCandidate, @"interfaceOrientation", int);
            int snapshotContentType = objcInvokeT(snapshotCandidate, @"contentType", int);
            if (UIInterfaceOrientationIsLandscape(snapshotOrientation))
            {
                BOOL isSceneContent = snapshotContentType == 0;
                if (!appSnapshot && isSceneContent)
                {
                    if ([objcInvoke(snapshotCandidate, @"name") isEqualToString:@"CarPlayLaunchImage"])
                    {
                        appSnapshot = snapshotCandidate;
                        break;
                    }
                }

                BOOL isStaticOrGeneratedImage = (snapshotContentType == 1 || snapshotContentType == 2);
                if (isStaticOrGeneratedImage)
                {
                    appSnapshot = snapshotCandidate;
                    break;
                }
            }

            if (!appSnapshot)
            {
                appSnapshot = snapshotCandidate;
            }
        }
    }

    self.shouldGenerateSnapshot = appSnapshot ? UIInterfaceOrientationIsPortrait((UIInterfaceOrientation)objcInvokeT(appSnapshot, @"interfaceOrientation", int)) : YES;

    id appSnapshotImage = appSnapshot ? objcInvoke_1(appSnapshot, @"imageForInterfaceOrientation:", 1) : nil;

    self.launchImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, [[self appContainerView] frame].size.width, [[self appContainerView] frame].size.height)];
    [self.launchImageView setImage:appSnapshotImage];
    [self.launchImageView setContentMode:UIViewContentModeScaleToFill];
    [[self appContainerView] addSubview:self.launchImageView];
    [self.launchImageView release];
}

- (void)setupLiveAppView
{
    LOG_LIFECYCLE_EVENT;
    NSString *appIdentifier = objcInvoke(self.application, @"bundleIdentifier");

    NSMutableArray *lockAssertions = objc_getAssociatedObject([UIApplication sharedApplication], &kPropertyKey_lockAssertionIdentifiers);
    [lockAssertions addObject:appIdentifier];

    id displaySceneManager = objcInvoke(objc_getClass("SBSceneManagerCoordinator"), @"mainDisplaySceneManager");
    assertGotExpectedObject(displaySceneManager, @"SBMainDisplaySceneManager");

    id sceneLayoutManager = objcInvoke(displaySceneManager, @"_layoutStateManager");
    assertGotExpectedObject(sceneLayoutManager, @"SBMainDisplayLayoutStateManager");

    id mainScreenIdentity = objcInvoke(displaySceneManager, @"displayIdentity");
    assertGotExpectedObject(mainScreenIdentity, @"FBSDisplayIdentity");

    id sceneIdentity = objcInvoke_2(displaySceneManager, @"_sceneIdentityForApplication:createPrimaryIfRequired:", self.application, 1);
    assertGotExpectedObject(sceneIdentity, @"FBSSceneIdentity");

    id sceneHandleRequest = objcInvoke_3(objc_getClass("SBApplicationSceneHandleRequest"), @"defaultRequestForApplication:sceneIdentity:displayIdentity:", self.application, sceneIdentity, mainScreenIdentity);
    assertGotExpectedObject(sceneHandleRequest, @"SBApplicationSceneHandleRequest");

    id sceneHandle = objcInvoke_1(displaySceneManager, @"fetchOrCreateApplicationSceneHandleForRequest:", sceneHandleRequest);
    assertGotExpectedObject(sceneHandle, @"SBDeviceApplicationSceneHandle");

    id appSceneEntity = objcInvoke_1([objc_getClass("SBDeviceApplicationSceneEntity") alloc], @"initWithApplicationSceneHandle:", sceneHandle);
    assertGotExpectedObject(appSceneEntity, @"SBDeviceApplicationSceneEntity");

    self.appViewController = objcInvoke_2([objc_getClass("SBAppViewController") alloc], @"initWithIdentifier:andApplicationSceneEntity:", appIdentifier, appSceneEntity);
    assertGotExpectedObject(self.appViewController, @"SBAppViewController");
    objcInvoke_1(self.appViewController, @"setIgnoresOcclusions:", 0);
    setIvar(self.appViewController, @"_currentMode", @(2));
    objcInvoke(getIvar(self.appViewController, @"_activationSettings"), @"clearActivationSettings");

    id sceneUpdateTransaction = objcInvoke_2(self.appViewController, @"_createSceneUpdateTransactionForApplicationSceneEntity:deliveringActions:", appSceneEntity, 1);
    assertGotExpectedObject(sceneUpdateTransaction, @"SBApplicationSceneUpdateTransaction");

    __block NSMutableArray *transactions = getIvar(self.appViewController, @"_activeTransitions");
    objcInvoke_1(sceneUpdateTransaction, @"setCompletionBlock:", ^void(int arg1) {

        [transactions removeObject:sceneUpdateTransaction];

        id processLaunchTransaction = getIvar(sceneUpdateTransaction, @"_processLaunchTransaction");
        assertGotExpectedObject(processLaunchTransaction, @"FBApplicationProcessLaunchTransaction");

        id appProcess = objcInvoke(processLaunchTransaction, @"process");
        assertGotExpectedObject(appProcess, @"FBProcess");

        objcInvoke_1(appProcess, @"_executeBlockAfterLaunchCompletes:", ^void(void) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [self.launchImageView removeFromSuperview];

                if (self.shouldGenerateSnapshot)
                {
                    id appScene = objcInvoke(sceneHandle, @"sceneIfExists");
                    if (!appScene)
                    {
                        return;
                    }
                    id sceneSettings = objcInvoke(appScene, @"mutableSettings");
                    objcInvoke_1(sceneSettings, @"setInterfaceOrientation:", self.orientation);
                    id snapshotContext = objcInvoke_2(objc_getClass("FBSSceneSnapshotContext"), @"contextWithSceneID:settings:", objcInvoke(appScene, @"identifier"), sceneSettings);
                    objcInvoke_1(snapshotContext, @"setName:", @"CarPlayLaunchImage");
                    objcInvoke_1(snapshotContext, @"setScale:", 2);
                    objcInvoke_1(snapshotContext, @"setExpirationInterval:", 99999);
                    objcInvoke_3(self.application, @"saveSnapshotForSceneHandle:context:completion:", sceneHandle, snapshotContext, nil);
                }
            });

            /* 通知 app 转到横屏 */
            [[objc_getClass("NSDistributedNotificationCenter") defaultCenter] postNotificationName:CPX_NOTIFICATION_ORIENTATION object:appIdentifier userInfo:@{@"orientation": @(self.orientation)}];
        });
    });

    [transactions addObject:sceneUpdateTransaction];
    objcInvoke(sceneUpdateTransaction, @"begin");
    objcInvoke(self.appViewController, @"_createSceneViewController");

    id animationFactory = objcInvoke(objc_getClass("SBApplicationSceneView"), @"defaultDisplayModeAnimationFactory");
    assertGotExpectedObject(animationFactory, @"BSUIAnimationFactory");

    id appView = objcInvoke(self.appViewController, @"appView");
    objcInvoke_3(appView, @"setDisplayMode:animationFactory:completion:", 4, animationFactory, 0);
    [[self.appViewController view] setBackgroundColor:[UIColor clearColor]];

    /* 监视 app 进程死亡，自动收掉窗口 */
    NSString *sceneID = objcInvoke_1(sceneLayoutManager, @"primarySceneIdentifierForBundleIdentifier:", appIdentifier);
    self.sceneMonitor = objcInvoke_1([objc_getClass("FBSceneMonitor") alloc], @"initWithSceneID:", sceneID);
    if (self.sceneMonitor)
    {
        objcInvoke_1(self.sceneMonitor, @"setDelegate:", self);
    }
}

/* FBSceneMonitor delegate: app 进程死了就关窗口 */
- (void)sceneMonitor:(id)arg1 sceneWasDestroyed:(id)arg2
{
    LOG_LIFECYCLE_EVENT;
    objcInvoke(self, @"dismiss");
}

- (void)handleScreenTapped
{
    if (_isFullscreen)
    {
        [self exitFullscreen];
    }
}

- (void)exitFullscreen
{
    if (_isFullscreen)
    {
        [self resizeAppViewForOrientation:self.orientation fullscreen:NO forceUpdate:NO];
    }
}

- (void)enterFullscreen
{
    if (UIInterfaceOrientationIsPortrait((UIInterfaceOrientation)self.orientation))
    {
        return;
    }

    BOOL toFullScreen = 1;
    [UIView animateWithDuration:0.2 animations:^(void) {
        [self resizeAppViewForOrientation:self.orientation fullscreen:toFullScreen forceUpdate:NO];
    } completion:nil];
}

/* 关闭托管窗口 */
- (void)dismiss
{
    LOG_LIFECYCLE_EVENT;
    [self.sceneMonitor invalidate];

    for (id observer in _observers)
    {
        [[objc_getClass("NSDistributedNotificationCenter") defaultCenter] removeObserver:observer];
    }

    id systemGestureManager = objcInvoke(objc_getClass("_UISystemGestureManager"), @"sharedInstance");
    id identity = objcInvoke(objcInvoke(self.rootWindow, @"displayConfiguration"), @"identity");
    objcInvoke_2(systemGestureManager, @"removeGestureRecognizer:fromDisplayWithIdentity:", _screenTapRecognizer, identity);

    void (^cleanupAfterCarplay)() = ^() {
        int resetOrientationLock = -1;
        NSString *hostedIdentifier = getIvar(self.appViewController, @"_identifier");
        [[objc_getClass("NSDistributedNotificationCenter") defaultCenter] postNotificationName:CPX_NOTIFICATION_ORIENTATION object:hostedIdentifier userInfo:@{@"orientation": @(resetOrientationLock)}];

        [self.rootWindow setHidden:YES];
        objcInvoke_1(self.appViewController, @"_setCurrentMode:", 0);

        id currentSceneHandle = objcInvoke(self.appViewController, @"sceneHandle");
        id mainSceneLayoutController = objcInvoke(objc_getClass("SBMainDisplaySceneLayoutViewController"), @"mainDisplaySceneLayoutViewController");
        id liveAppSceneControllers = objcInvoke(mainSceneLayoutController, @"appViewControllers");
        for (id appSceneLayoutController in liveAppSceneControllers)
        {
            id appSceneController = objcInvoke(appSceneLayoutController, @"_applicationSceneViewController");
            id appSceneView = objcInvoke(appSceneController, @"_sceneView");
            id appSceneHandle = objcInvoke(appSceneView, @"sceneHandle");
            if (appSceneHandle && [appSceneHandle isEqual:currentSceneHandle])
            {
                objcInvoke_3(appSceneView, @"setDisplayMode:animationFactory:completion:", 4, nil, nil);
            }
        }

        id sharedApp = [UIApplication sharedApplication];

        NSMutableArray *lockAssertions = objc_getAssociatedObject(sharedApp, &kPropertyKey_lockAssertionIdentifiers);
        id appScene = objcInvoke(objcInvoke(self.appViewController, @"sceneHandle"), @"sceneIfExists");
        if (appScene != nil)
        {
            NSString *sceneAppBundleID = objcInvoke(objcInvoke(objcInvoke(appScene, @"client"), @"process"), @"bundleIdentifier");
            [lockAssertions removeObject:sceneAppBundleID];

            id frontmostApp = objcInvoke(sharedApp, @"_accessibilityFrontMostApplication");
            BOOL isAppOnMainScreen = frontmostApp && [objcInvoke(frontmostApp, @"bundleIdentifier") isEqualToString:sceneAppBundleID];
            if (!isAppOnMainScreen)
            {
                id sceneSettings = objcInvoke(appScene, @"mutableSettings");
                objcInvoke_1(sceneSettings, @"setBackgrounded:", 1);
                objcInvoke_1(sceneSettings, @"setForeground:", 0);
                ((void (*)(id, SEL, id, id, void *))objc_msgSend)(appScene, NSSelectorFromString(@"updateSettings:withTransitionContext:completion:"), sceneSettings, nil, 0);
            }
        }

        if (objcInvokeT(sharedApp, @"isLocked", BOOL) == YES)
        {
            void *_BKSHIDServicesGetBacklightFactor = dlsym(RTLD_DEFAULT, "BKSHIDServicesGetBacklightFactor");
            if (_BKSHIDServicesGetBacklightFactor)
            {
                float backlightFactor = ((float (*)(void))_BKSHIDServicesGetBacklightFactor)();
                if (backlightFactor < 0.2)
                {
                    orig_BKSDisplayServicesSetScreenBlanked(1);
                }
            }
        }

        objc_setAssociatedObject(sharedApp, &kPropertyKey_liveCarplayWindow, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        [self.rootWindow removeFromSuperview];
        self.rootWindow = nil;
    };

    [UIView animateWithDuration:0.5 animations:^(void)
    {
        [[self rootWindow] setAlpha:0];
    } completion:^(BOOL completed)
    {
        cleanupAfterCarplay();
    }];
}

/* 旋转按钮 */
- (void)handleRotate
{
    UIInterfaceOrientation desiredOrientation = (UIInterfaceOrientation)((UIInterfaceOrientationIsLandscape((UIInterfaceOrientation)self.orientation)) ? 1 : 3);

    id appScene = objcInvoke(objcInvoke([self appViewController], @"sceneHandle"), @"sceneIfExists");
    if (!appScene)
    {
        return;
    }

    NSString *sceneAppBundleID = objcInvoke(objcInvoke(objcInvoke(appScene, @"client"), @"process"), @"bundleIdentifier");

    [[objc_getClass("NSDistributedNotificationCenter") defaultCenter] postNotificationName:CPX_NOTIFICATION_ORIENTATION object:sceneAppBundleID userInfo:@{@"orientation": @(desiredOrientation)}];
    [self resizeAppViewForOrientation:desiredOrientation fullscreen:self.isFullscreen forceUpdate:NO];
}

/* 托管窗口随方向/全屏状态重排 */
- (void)resizeAppViewForOrientation:(int)desiredOrientation fullscreen:(BOOL)fullscreen forceUpdate:(BOOL)forceUpdate
{
    if (!forceUpdate && (desiredOrientation == self.orientation && self.isFullscreen == fullscreen))
    {
        return;
    }

    id appSceneView = getIvar(getIvar(self.appViewController, @"_deviceAppViewController"), @"_sceneView");
    assertGotExpectedObject(appSceneView, @"SBSceneView");
    UIView *hostingContentView = getIvar(appSceneView, @"_sceneContentContainerView");
    UIScreen *targetScreen = nil;
    if (_drawOnMainScreen)
    {
        targetScreen = [UIScreen mainScreen];
    }
    else {
        for (UIScreen *currentScreen in [UIScreen screens])
        {
            if (objcInvokeT(currentScreen, @"_isCarScreen", BOOL))
            {
                targetScreen = currentScreen;
                break;
            }
        }
    }

    assertGotExpectedObject(targetScreen, @"UIScreen");

    CGRect carplayDisplayBounds = [targetScreen bounds];
    CGFloat dockWidth = (fullscreen) ? 0 : CARPLAY_DOCK_WIDTH;
    CGSize carplayDisplaySize = CGSizeMake(carplayDisplayBounds.size.width - dockWidth, carplayDisplayBounds.size.height);

    CGSize mainScreenSize = ((CGRect (*)(id, SEL, int))objc_msgSend)([UIScreen mainScreen], NSSelectorFromString(@"boundsForOrientation:"), desiredOrientation).size;

    CGFloat widthScale = carplayDisplaySize.width / mainScreenSize.width;
    CGFloat heightScale = carplayDisplaySize.height / mainScreenSize.height;
    CGFloat xOrigin = [[self rootWindow] frame].origin.x;

    /* 车机屏永远是物理横屏，竖屏时特殊缩放 */
    if (UIInterfaceOrientationIsPortrait(desiredOrientation))
    {
        widthScale = (carplayDisplaySize.width / 2) / mainScreenSize.width;
        CGFloat scaledDisplayWidth = carplayDisplaySize.width * widthScale;
        xOrigin = (carplayDisplaySize.width / 2) - (scaledDisplayWidth / 2);
    }

    [hostingContentView setTransform:CGAffineTransformMakeScale(widthScale, heightScale)];
    [[self.appViewController view] setFrame:CGRectMake(xOrigin, [[self.appViewController view] frame].origin.y, carplayDisplaySize.width, carplayDisplaySize.height)];

    BOOL rightHandDock = [self shouldUseRightHandDock];
    UIView *containingView = [self appContainerView];
    CGRect containingViewFrame = [containingView frame];
    containingViewFrame.origin.x = (rightHandDock) ? 0 : dockWidth;
    [containingView setFrame:containingViewFrame];

    [self.dockView setAlpha: (fullscreen) ? 0 : 1];

    self.orientation = desiredOrientation;
    self.isFullscreen = fullscreen;
}

- (BOOL)shouldUseRightHandDock
{
    id carplaySession = objcInvoke(self.sessionStatus, @"session");
    id usesRightHand = carplaySession ? objcInvoke_1(carplaySession, @"_endpointValueForKey:", @"RightHandDrive") : nil;
    return [usesRightHand boolValue];
}

- (void)dealloc
{
    [_rootWindow release];
    [_dockView release];
    [_appContainerView release];
    [_launchImageView release];
    [_fullscreenTransparentOverlay release];
    [_appViewController release];
    [_sceneMonitor release];
    [_application release];
    [_sessionStatus release];
    [_observers release];
    [_screenTapRecognizer release];
    [super dealloc];
}

@end
