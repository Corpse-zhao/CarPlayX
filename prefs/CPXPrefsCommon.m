#import "CPXPrefsCommon.h"

@implementation CPXPrefsStore

+ (NSDictionary *)loadDict
{
    if ([[NSFileManager defaultManager] fileExistsAtPath:PREFERENCES_PLIST_PATH])
    {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:PREFERENCES_PLIST_PATH];
        return d ?: @{};
    }
    return @{};
}

+ (void)saveDict:(NSDictionary *)dict
{
    [dict writeToFile:PREFERENCES_PLIST_PATH atomically:YES];
}

+ (id)valueForKey:(NSString *)key
{
    return [[self loadDict] valueForKey:key];
}

+ (void)setValue:(id)value forKey:(NSString *)key
{
    NSMutableDictionary *d = [[self loadDict] mutableCopy];
    d[key] = value;
    [self saveDict:d];
}

+ (void)postPrefsChangedWithObject:(NSString *)object
{
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName:CPX_NOTIFICATION_PREFS_CHANGED object:object userInfo:nil deliverImmediately:YES];
}

@end

void CPXPrefsLog(NSString *fmt, ...)
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

            NSString *probePath = @"/var/mobile/Documents/CarPlayX/probe.txt";
            NSFileManager *fm = [NSFileManager defaultManager];
            [fm createDirectoryAtPath:CPX_WALLPAPER_DIR withIntermediateDirectories:YES attributes:nil error:NULL];

            NSDictionary *attr = [fm attributesOfItemAtPath:probePath error:NULL];
            unsigned long long sz = attr ? [attr fileSize] : 0;
            NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
            if (sz > 512 * 1024)
            {
                [data writeToFile:probePath atomically:YES];
            }
            else
            {
                NSFileHandle *h = [NSFileHandle fileHandleForUpdatingAtPath:probePath];
                if (h)
                {
                    [h seekToEndOfFile];
                    [h writeData:data];
                    [h closeFile];
                }
                else
                {
                    [data writeToFile:probePath atomically:YES];
                }
            }
        }
        @catch (NSException *exception)
        {
            /* 诊断日志绝不崩设置进程 */
        }
    }
}
