#ifndef CPX_CARPLAY_WINDOW_H
#define CPX_CARPLAY_WINDOW_H

#include <UIKit/UIKit.h>

id getCarplayCADisplay(void);

/*
把一个普通 app 的实时画面托管到 CarPlay 外接屏上。
移植自 CarPlayEnable (Ethan Arbuckle, Apache-2.0)。
*/
@interface CPXCarPlayWindow : NSObject

@property (nonatomic, retain) UIWindow *rootWindow;
@property (nonatomic, retain) UIView *dockView;
@property (nonatomic, retain) UIView *appContainerView;
@property (nonatomic, retain) UIImageView *launchImageView;
@property (nonatomic, retain) UIView *fullscreenTransparentOverlay;
@property (nonatomic, retain) id appViewController;
@property (nonatomic, retain) id sceneMonitor;
@property (nonatomic, retain) id application;
@property (nonatomic, retain) id sessionStatus;
@property (nonatomic, retain) NSMutableArray *observers;
@property (nonatomic, retain) UITapGestureRecognizer *screenTapRecognizer;

@property (nonatomic) int orientation;
@property (nonatomic) BOOL isFullscreen;
@property (nonatomic) BOOL shouldGenerateSnapshot;
@property (nonatomic) BOOL drawOnMainScreen;

- (id)initWithBundleIdentifier:(NSString *)identifier;

@end

#endif
