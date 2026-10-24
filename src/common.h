#ifndef CPX_COMMON_H
#define CPX_COMMON_H

#include <Foundation/Foundation.h>
#include <UIKit/UIKit.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <dlfcn.h>
#include "CPXPreferences.h"

#define CPX_VERSION @"0.1.8"

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

/* 保险丝：创建此文件即整体禁用插件（崩溃急救用，无需卸载） */
#define CPX_DISABLE_PATH @"/var/mobile/Documents/CarPlayX/DISABLED"
#define CPX_DISABLED ([[NSFileManager defaultManager] fileExistsAtPath:CPX_DISABLE_PATH])

/* 金丝雀分级：读取 /var/mobile/Documents/CarPlayX/STAGE 文件里的数字（缺省 0）
   0=ctor 只写日志  1=+壁纸类清点  2=+%init 钩子挂载  3=+MSHookFunction */
int CPXStage(void);

#define CARPLAY_DOCK_WIDTH 40

extern int (*orig_BKSDisplayServicesSetScreenBlanked)(int);

#endif
