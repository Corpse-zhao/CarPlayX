#ifndef CPX_COMMON_H
#define CPX_COMMON_H

#include <Foundation/Foundation.h>
#include <UIKit/UIKit.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <dlfcn.h>
#include "CPXPreferences.h"

#define CPX_VERSION @"0.1.0"

#define BAIL_IF_UNSUPPORTED_IOS { \
    if ([[[UIDevice currentDevice] systemVersion] compare:@"14.0" options:NSNumericSearch] == NSOrderedAscending) \
    { \
        return; \
    } \
}

/* Diagnostic logging -> /var/mobile/Documents/CarPlayX/probe.txt (implemented in CPXPreferences.mm) */
void CPXLog(NSString *fmt, ...);
void CPXDumpWallpaperClasses(void);

#define LOG_LIFECYCLE_EVENT { \
    NSString *func = [NSString stringWithFormat:@"%s", __func__]; \
    if ([func containsString:@"_method$"]) \
    { \
        NSArray *components = [func componentsSeparatedByString:@"$"]; \
        if ([components count] > 3) func = [NSString stringWithFormat:@"[%@ %@]", components[2], components[3]]; \
    } \
    CPXLog(@"[生命周期] %@", func); \
}

#define getIvar(object, ivar) [object valueForKey:ivar]
#define setIvar(object, ivar, value) [object setValue:value forKey:ivar]

#define objcInvokeT(a, b, t) ((t (*)(id, SEL))objc_msgSend)(a, NSSelectorFromString(b))
#define objcInvoke(a, b) objcInvokeT(a, b, id)
#define objcInvoke_1(a, b, c) ((id (*)(id, SEL, typeof(c)))objc_msgSend)(a, NSSelectorFromString(b), c)
#define objcInvoke_2(a, b, c, d) ((id (*)(id, SEL, typeof(c), typeof(d)))objc_msgSend)(a, NSSelectorFromString(b), c, d)
#define objcInvoke_3(a, b, c, d, e) ((id (*)(id, SEL, typeof(c), typeof(d), typeof(e)))objc_msgSend)(a, NSSelectorFromString(b), c, d, e)

#define assertGotExpectedObject(obj, type) if (!obj || ![obj isKindOfClass:NSClassFromString(type)]) [NSException raise:@"UnexpectedObjectException" format:@"Expected %@ but got %@", type, obj]

#define kPropertyKey_liveCarplayWindow *NSSelectorFromString(@"liveCarplayWindow")
#define kPropertyKey_lockAssertionIdentifiers *NSSelectorFromString(@"lockAssertions")
static char *kPropertyKey_didDrawPlaceholder;

/* Preferences / IPC */
#define PREFERENCES_PLIST_PATH @"/var/mobile/Library/Preferences/com.carplayx.preferences.plist"
#define CPX_NOTIFICATION_PREFS_CHANGED @"com.carplayx.preferences.changed"
#define CPX_NOTIFICATION_APP_DATA @"com.carplayx.prefs.app_data"
#define CPX_NOTIFICATION_LAUNCH @"com.carplayx.launch"
#define CPX_NOTIFICATION_ORIENTATION @"com.carplayx.orientation"
#define kPrefsAppDataRequesting @"Requesting"
#define kPrefsAppDataReceiving @"Receiving"
#define kPrefsAppLibraryChanged @"appLibrary"
#define kPrefsWallpaperChanged @"wallpaper"

#define CPX_WALLPAPER_DIR @"/var/mobile/Documents/CarPlayX"
#define CPX_WALLPAPER_BASENAME @"wallpaper"

#define CARPLAY_DOCK_WIDTH 40

extern int (*orig_BKSDisplayServicesSetScreenBlanked)(int);

#endif
