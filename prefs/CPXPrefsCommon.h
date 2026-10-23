#ifndef CPX_PREFS_COMMON_H
#define CPX_PREFS_COMMON_H

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

/* iOS SDK 头文件不公开 NSDistributedNotificationCenter，这里自行声明 */
@interface NSDistributedNotificationCenter : NSNotificationCenter
+ (instancetype)defaultCenter;
- (void)postNotificationName:(NSString *)name object:(id)object userInfo:(NSDictionary *)userInfo deliverImmediately:(BOOL)deliverImmediately;
@end

#define CPX_VERSION @"0.1.7"

#define PREFERENCES_PLIST_PATH @"/var/mobile/Library/Preferences/com.carplayx.preferences.plist"
#define CPX_NOTIFICATION_PREFS_CHANGED @"com.carplayx.preferences.changed"
#define CPX_NOTIFICATION_APP_DATA @"com.carplayx.prefs.app_data"
#define kPrefsAppDataRequesting @"Requesting"
#define kPrefsAppDataReceiving @"Receiving"
#define kPrefsAppLibraryChanged @"appLibrary"
#define kPrefsWallpaperChanged @"wallpaper"

#define CPX_WALLPAPER_DIR @"/var/mobile/Documents/CarPlayX"

/* prefs 进程自己的日志函数（与插件端写同一个 probe.txt，时间线可对齐） */
void CPXPrefsLog(NSString *fmt, ...);

/* plist 配置读写小助手 */
@interface CPXPrefsStore : NSObject
+ (NSDictionary *)loadDict;
+ (void)saveDict:(NSDictionary *)dict;
+ (id)valueForKey:(NSString *)key;
+ (void)setValue:(id)value forKey:(NSString *)key;
+ (void)postPrefsChangedWithObject:(NSString *)object;
@end

#endif
