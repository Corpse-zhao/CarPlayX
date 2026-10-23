#include "common.h"
#include <mach-o/dyld.h>

@implementation CPXPreferences

+ (instancetype)sharedInstance
{
    static CPXPreferences *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[CPXPreferences alloc] init];
    });
    return sharedInstance;
}

- (id)init
{
    if ((self = [super init]))
    {
        [self reloadPreferences];
    }

    return self;
}

- (void)reloadPreferences
{
    /* MRC 注意：必须持有，绝不能把 autoreleased 字面量直接赋给 ivar（会导致僵尸对象崩溃） */
    NSDictionary *newPrefs = [[NSDictionary alloc] init];
    if ([[NSFileManager defaultManager] fileExistsAtPath:PREFERENCES_PLIST_PATH])
    {
        NSDictionary *loaded = [[NSDictionary alloc] initWithContentsOfFile:PREFERENCES_PLIST_PATH];
        if (loaded)
        {
            [newPrefs release];
            newPrefs = loaded;
        }
    }
    [_cachedPreferences release];
    _cachedPreferences = newPrefs;
}

- (void)updateValue:(id)value forPreferenceKey:(NSString *)key
{
    NSMutableDictionary *copy = [_cachedPreferences mutableCopy];
    copy[key] = value;
    /* 走 retain setter 持有新字典，再平衡 mutableCopy 的 +1，避免 ivar 指向已释放对象 */
    [self setCachedPreferences:copy];
    [copy release];
    [copy writeToFile:PREFERENCES_PLIST_PATH atomically:YES];
}

- (BOOL)masterEnabled
{
    if (_cachedPreferences && [_cachedPreferences valueForKey:@"masterEnabled"])
    {
        return [[_cachedPreferences valueForKey:@"masterEnabled"] boolValue];
    }
    return YES;
}

- (NSArray *)excludedApplications
{
    if (_cachedPreferences && [_cachedPreferences valueForKey:@"excludedApps"])
    {
        return [_cachedPreferences valueForKey:@"excludedApps"];
    }
    return @[];
}

- (NSArray *)removedApplications
{
    if (_cachedPreferences && [_cachedPreferences valueForKey:@"removedApps"])
    {
        return [_cachedPreferences valueForKey:@"removedApps"];
    }
    return @[];
}

- (BOOL)wallpaperEnabled
{
    if (_cachedPreferences && [_cachedPreferences valueForKey:@"wallpaperEnabled"])
    {
        return [[_cachedPreferences valueForKey:@"wallpaperEnabled"] boolValue];
    }
    return NO;
}

- (NSString *)wallpaperResourceOverride
{
    if (_cachedPreferences && [_cachedPreferences valueForKey:@"wallpaperResourceOverride"])
    {
        return [_cachedPreferences valueForKey:@"wallpaperResourceOverride"];
    }
    return @"";
}

- (BOOL)fiveColumnIconLayout
{
    if (_cachedPreferences && [_cachedPreferences valueForKey:@"fiveColumnIconLayout"])
    {
        return [[_cachedPreferences valueForKey:@"fiveColumnIconLayout"] boolValue];
    }
    return NO;
}

- (NSString *)firstExistingWallpaperPath
{
    NSArray *extensions = @[@"png", @"jpg", @"jpeg", @"heic", @"webp"];
    for (NSString *ext in extensions)
    {
        NSString *path = [NSString stringWithFormat:@"%@/%@.%@", CPX_WALLPAPER_DIR, CPX_WALLPAPER_BASENAME, ext];
        if ([[NSFileManager defaultManager] fileExistsAtPath:path])
        {
            return path;
        }
    }
    return nil;
}

- (UIImage *)customWallpaperImage
{
    @try
    {
        NSString *path = [self firstExistingWallpaperPath];
        if (!path)
        {
            return nil;
        }
        UIImage *img = [[UIImage alloc] initWithContentsOfFile:path];
        if (img)
        {
            return [img autorelease];
        }
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (data)
        {
            return [UIImage imageWithData:data];
        }
    }
    @catch (NSException *exception)
    {
        CPXLog(@"[壁纸] 读取自定义壁纸失败: %@", exception);
    }
    return nil;
}

@end

/* ============ 诊断日志 ============ */

#define CPX_PROBE_PATH @"/var/mobile/Documents/CarPlayX/probe.txt"
#define CPX_PROBE_MAX_BYTES (512 * 1024)

void CPXLog(NSString *fmt, ...)
{
    @autoreleasepool
    {
        @try
        {
            va_list args;
            va_start(args, fmt);
            NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
            va_end(args);

            NSString *line = [NSString stringWithFormat:@"[%@] (%@ pid=%d) %@\n",
                              [NSDate date], NSProcessInfo.processInfo.processName, (int)getpid(), msg];
            [msg release];

            NSFileManager *fm = [NSFileManager defaultManager];
            [fm createDirectoryAtPath:CPX_WALLPAPER_DIR withIntermediateDirectories:YES attributes:nil error:NULL];

            NSDictionary *attr = [fm attributesOfItemAtPath:CPX_PROBE_PATH error:NULL];
            unsigned long long sz = attr ? [attr fileSize] : 0;
            NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
            if (sz > CPX_PROBE_MAX_BYTES)
            {
                [data writeToFile:CPX_PROBE_PATH atomically:YES];
            }
            else
            {
                NSFileHandle *h = [NSFileHandle fileHandleForUpdatingAtPath:CPX_PROBE_PATH];
                if (h)
                {
                    [h seekToEndOfFile];
                    [h writeData:data];
                    [h closeFile];
                    [h release];
                }
                else
                {
                    [data writeToFile:CPX_PROBE_PATH atomically:YES];
                }
            }
        }
        @catch (NSException *exception)
        {
            /* diagnostics must never crash the host */
        }
    }
}

/*
枚举运行时所有类名含 "Wallpaper" 的类（只认系统镜像），把「壁纸类名清单」写进诊断日志。
这是我们定位 iOS 16 CarPlay 壁纸真实渲染类的第一手情报。
*/
void CPXDumpWallpaperClasses(void)
{
    @autoreleasepool
    {
        @try
        {
            unsigned int count = 0;
            Class *classes = objc_copyClassList(&count);
            NSMutableArray *hits = [NSMutableArray array];
            for (unsigned int i = 0; i < count; i++)
            {
                NSString *cn = NSStringFromClass(classes[i]);
                if (![cn containsString:@"Wallpaper"] && ![cn containsString:@"wallpaper"])
                {
                    continue;
                }
                const char *img = class_getImageName(classes[i]);
                NSString *imgPath = img ? [NSString stringWithUTF8String:img] : @"?";
                /* 只关心系统镜像里的 */
                if (![imgPath hasPrefix:@"/System/Library/"] && ![imgPath hasPrefix:@"/usr/lib/"])
                {
                    continue;
                }
                [hits addObject:[NSString stringWithFormat:@"%@(%@)", cn, [imgPath lastPathComponent]]];
            }
            free(classes);
            CPXLog(@"[壁纸类清点] 命中 %lu 个: %@", (unsigned long)[hits count],
                   [hits componentsJoinedByString:@" "]);
        }
        @catch (NSException *exception)
        {
            /* ignore */
        }
    }
}
