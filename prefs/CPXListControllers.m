#import "CPXListControllers.h"
#import "CPXPrefsCommon.h"

/*
v0.1.8：全面改用 Preferences 原生 specifier 机制。
不再自绘 UITableView / 不再覆盖父类数据源方法 —— 全部交给父类机制驱动，
这是所有成熟 tweak 的标准写法，兼容性最高。
App 清单由 SpringBoard 写入 /var/mobile/Documents/CarPlayX/applist.plist，此处同步读取。
*/

#define CPX_APPLIST_PATH @"/var/mobile/Documents/CarPlayX/applist.plist"

/* ============ 通用工具 ============ */

static NSArray *CPXSortedAppList(void)
{
    NSDictionary *data = [NSDictionary dictionaryWithContentsOfFile:CPX_APPLIST_PATH];
    NSArray *list = data[@"appList"];
    if (!list.count) return nil;

    NSSortDescriptor *stock = [[NSSortDescriptor alloc] initWithKey:@"isStock" ascending:NO];
    NSSortDescriptor *name = [[NSSortDescriptor alloc] initWithKey:@"name" ascending:YES];
    NSArray *sorted = [list sortedArrayUsingDescriptors:@[stock, name]];
    return sorted;
}

/* ============ 主页 ============ */

@implementation CPXRootListController

- (id)initForContentSize:(CGSize)size
{
    if ((self = [super initForContentSize:size]))
    {
        [self setTitle:@"CarPlayX"];
    }
    return self;
}

- (id)initWithSpecifier:(PSSpecifier *)specifier
{
    if ((self = [super initWithSpecifier:specifier]))
    {
        [self setTitle:@"CarPlayX"];
    }
    return self;
}

- (instancetype)init
{
    if ((self = [super init]))
    {
        [self setTitle:@"CarPlayX"];
    }
    return self;
}

/* 进页面时向 SpringBoard 请求最新 app 清单（异步写到 applist.plist） */
- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[objc_getClass("NSDistributedNotificationCenter") defaultCenter] postNotificationName:CPX_NOTIFICATION_APP_DATA object:kPrefsAppDataRequesting userInfo:nil deliverImmediately:YES];
}

- (NSArray *)specifiers
{
    if (!_specifiers)
    {
        NSMutableArray *specs = [NSMutableArray array];

        PSSpecifier *g1 = [PSSpecifier groupSpecifierWithTitle:@"功能开关"];
        [g1 setProperty:@"开关改动即时生效，无需注销" forKey:@"footerText"];
        [specs addObject:g1];

        PSSpecifier *master = [PSSpecifier preferenceSpecifierNamed:@"启用 CarPlayX"
                                                             target:self
                                                                set:@selector(setValue:forSpecifier:)
                                                                get:@selector(valueForSpecifier:)
                                                             detail:nil
                                                                cell:kCPXCellSwitch
                                                                 edit:nil];
        [master setProperty:@"masterEnabled" forKey:@"key"];
        [master setProperty:@NO forKey:@"default"];
        [specs addObject:master];

        PSSpecifier *wallpaper = [PSSpecifier preferenceSpecifierNamed:@"自定义壁纸"
                                                                target:self
                                                                   set:@selector(setValue:forSpecifier:)
                                                                   get:@selector(valueForSpecifier:)
                                                                detail:nil
                                                                   cell:kCPXCellSwitch
                                                                    edit:nil];
        [wallpaper setProperty:@"wallpaperEnabled" forKey:@"key"];
        [wallpaper setProperty:@NO forKey:@"default"];
        [specs addObject:wallpaper];

        PSSpecifier *g2 = [PSSpecifier groupSpecifierWithTitle:@"应用管理"];
        [g2 setProperty:@"「移除默认应用」可隐藏 CarPlay 默认自带且系统不允许取消的 App；「加入 / 排除应用」可把任意第三方 App 强制加入 CarPlay 主屏。" forKey:@"footerText"];
        [specs addObject:g2];

        PSSpecifier *addLink = [PSSpecifier preferenceSpecifierNamed:@"加入 / 排除应用"
                                                              target:self
                                                                 set:NULL
                                                                 get:NULL
                                                              detail:[CPXAddListController class]
                                                                 cell:kCPXCellLink
                                                                  edit:nil];
        [addLink setProperty:@"强制把 App 加进 CarPlay" forKey:@"subtitle"];
        [specs addObject:addLink];

        PSSpecifier *removeLink = [PSSpecifier preferenceSpecifierNamed:@"移除默认应用"
                                                                 target:self
                                                                    set:NULL
                                                                    get:NULL
                                                                 detail:[CPXRemoveListController class]
                                                                    cell:kCPXCellLink
                                                                     edit:nil];
        [removeLink setProperty:@"从 CarPlay 隐藏默认 App" forKey:@"subtitle"];
        [specs addObject:removeLink];

        PSSpecifier *g3 = [PSSpecifier groupSpecifierWithTitle:@"显示"];
        [specs addObject:g3];

        PSSpecifier *fiveCol = [PSSpecifier preferenceSpecifierNamed:@"五列图标布局"
                                                              target:self
                                                                 set:@selector(setValue:forSpecifier:)
                                                                 get:@selector(valueForSpecifier:)
                                                              detail:nil
                                                                 cell:kCPXCellSwitch
                                                                  edit:nil];
        [fiveCol setProperty:@"fiveColumnIconLayout" forKey:@"key"];
        [fiveCol setProperty:@NO forKey:@"default"];
        [specs addObject:fiveCol];

        PSSpecifier *g4 = [PSSpecifier groupSpecifierWithTitle:@"诊断"];
        [g4 setProperty:@"CarPlayX %@ · 基于开源项目 CarPlayEnable (Apache-2.0, Ethan Arbuckle) 移植扩展" forKey:@"footerText"];
        [specs addObject:g4];

        PSSpecifier *logBtn = [PSSpecifier preferenceSpecifierNamed:@"复制诊断日志"
                                                             target:self
                                                                set:NULL
                                                                get:NULL
                                                             detail:nil
                                                                cell:kCPXCellButton
                                                                 edit:nil];
        if ([logBtn respondsToSelector:@selector(setTarget:action:)])
        {
            [logBtn setTarget:self action:@selector(copyLog:)];
        }
        if ([logBtn respondsToSelector:@selector(setButtonAction:)])
        {
            [logBtn setButtonAction:@selector(copyLog:)];
        }
        [specs addObject:logBtn];

        _specifiers = specs;
    }

    return _specifiers;
}

/* specifier 的 key 属性 -> CPXPrefsStore 存取 */
- (NSString *)keyForSpecifier:(PSSpecifier *)spec
{
    NSString *key = [spec propertyForKey:@"key"];
    if (!key) key = [spec propertyForKey:@"identifier"];
    return key;
}

- (id)valueForSpecifier:(PSSpecifier *)spec
{
    NSString *key = [self keyForSpecifier:spec];
    id v = key ? [CPXPrefsStore valueForKey:key] : nil;
    if (v == nil) v = [spec propertyForKey:@"default"] ?: @NO;
    return v;
}

- (void)setValue:(id)value forSpecifier:(PSSpecifier *)spec
{
    NSString *key = [self keyForSpecifier:spec];
    if (!key) return;
    [CPXPrefsStore setValue:value forKey:key];
    NSString *notify = [key isEqualToString:@"wallpaperEnabled"] ? kPrefsWallpaperChanged : kPrefsAppLibraryChanged;
    [CPXPrefsStore postPrefsChangedWithObject:notify];
}

- (void)copyLog:(PSSpecifier *)spec
{
    NSString *log = [NSString stringWithContentsOfFile:@"/var/mobile/Documents/CarPlayX/probe.txt" encoding:NSUTF8StringEncoding error:NULL];
    if (!log.length)
    {
        log = @"暂无日志。请先连接一次 CarPlay 再回来复制。";
    }
    else if (log.length > 20000)
    {
        log = [log substringFromIndex:log.length - 20000];
    }
    UIPasteboard.generalPasteboard.string = log;
    UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"已复制到剪贴板" message:@"最近 20KB 诊断日志已复制，直接粘贴发给开发者即可。" delegate:nil cancelButtonTitle:@"好" otherButtonTitles:nil];
    [av show];
}

@end

/* ============ 应用列表页 ============ */

@implementation CPXAppListController

- (NSString *)mode
{
    return [self isKindOfClass:[CPXAddListController class]] ? @"add" : @"remove";
}

- (id)initForContentSize:(CGSize)size
{
    if ((self = [super initForContentSize:size]))
    {
        [self setTitle:([[self mode] isEqualToString:@"add"]) ? @"加入 / 排除应用" : @"移除默认应用"];
    }
    return self;
}

- (id)initWithSpecifier:(PSSpecifier *)specifier
{
    if ((self = [super initWithSpecifier:specifier]))
    {
        [self setTitle:([[self mode] isEqualToString:@"add"]) ? @"加入 / 排除应用" : @"移除默认应用"];
    }
    return self;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    /* 清单可能刚被 SpringBoard 更新，重建 specifiers */
    [self reloadSpecifiers];
}

- (NSArray *)specifiers
{
    if (!_specifiers)
    {
        NSMutableArray *specs = [NSMutableArray array];
        BOOL addMode = [[self mode] isEqualToString:@"add"];

        PSSpecifier *group = [PSSpecifier groupSpecifierWithTitle:addMode ? @"勾选 = 在 CarPlay 显示" : @"勾选 = 已从 CarPlay 移除"];
        [group setProperty:addMode
            ? @"第三方 App 全部默认加入 CarPlay，取消勾选即排除。系统自带 App 默认不强制加入。"
            : @"用于移除 CarPlay 默认添加且系统不允许删除的 App（播客、图书、新闻等），取消勾选即可恢复。"
             forKey:@"footerText"];
        [specs addObject:group];

        NSArray *list = CPXSortedAppList();
        if (!list)
        {
            PSSpecifier *empty = [PSSpecifier preferenceSpecifierNamed:@"清单尚未加载，请返回本页后重新进入（已向系统请求清单）"
                                                                target:nil
                                                                   set:NULL
                                                                   get:NULL
                                                                detail:nil
                                                                   cell:kCPXCellStaticText
                                                                    edit:nil];
            [specs addObject:empty];
            _specifiers = specs;
            return _specifiers;
        }

        for (NSDictionary *app in list)
        {
            NSString *name = app[@"name"] ?: app[@"bundleID"];
            PSSpecifier *sw = [PSSpecifier preferenceSpecifierNamed:name
                                                             target:self
                                                                set:@selector(setValue:forSpecifier:)
                                                                get:@selector(valueForSpecifier:)
                                                             detail:nil
                                                                cell:kCPXCellSwitch
                                                                 edit:nil];
            [sw setProperty:app[@"bundleID"] forKey:@"bundleID"];
            id iconData = app[@"iconImage"];
            if (iconData)
            {
                UIImage *icon = [UIImage imageWithData:iconData];
                if (icon) [sw setProperty:icon forKey:@"iconImage"];
            }
            [specs addObject:sw];
        }

        _specifiers = specs;
    }

    return _specifiers;
}

- (BOOL)appIsOn:(NSString *)bid
{
    BOOL addMode = [[self mode] isEqualToString:@"add"];
    if (addMode)
    {
        /* 加入模式：默认全开，excludedApps 里的关闭 */
        NSArray *excluded = [CPXPrefsStore valueForKey:@"excludedApps"];
        return !(excluded && [excluded containsObject:bid]);
    }
    NSArray *removed = [CPXPrefsStore valueForKey:@"removedApps"];
    return removed && [removed containsObject:bid];
}

- (id)valueForSpecifier:(PSSpecifier *)spec
{
    NSString *bid = [spec propertyForKey:@"bundleID"];
    if (!bid) return @NO;
    return @([self appIsOn:bid]);
}

- (void)setValue:(id)value forSpecifier:(PSSpecifier *)spec
{
    NSString *bid = [spec propertyForKey:@"bundleID"];
    if (!bid) return;

    BOOL addMode = [[self mode] isEqualToString:@"add"];
    NSString *listKey = addMode ? @"excludedApps" : @"removedApps";
    BOOL currentlyOn = [self appIsOn:bid];
    BOOL shouldOn = [value boolValue];
    BOOL shouldAddToList = currentlyOn && !shouldOn;   /* 从开到关 => 进黑名单 */
    BOOL shouldRemoveFromList = !currentlyOn && shouldOn;

    NSMutableArray *list = [[CPXPrefsStore valueForKey:listKey] mutableCopy] ?: [NSMutableArray array];
    if (shouldAddToList && ![list containsObject:bid])
    {
        [list addObject:bid];
    }
    else if (shouldRemoveFromList)
    {
        [list removeObject:bid];
    }
    else
    {
        return;
    }

    [CPXPrefsStore setValue:list forKey:listKey];
    [CPXPrefsStore postPrefsChangedWithObject:kPrefsAppLibraryChanged];
    CPXPrefsLog(@"[设置面板] %@ 列表更新: %@ -> %@", listKey, bid, shouldAddToList ? @"加入名单" : @"移出名单");
}

@end

@implementation CPXAddListController
@end

@implementation CPXRemoveListController
@end

/* ============ 壁纸设置页 ============ */

@implementation CPXWallpaperController

- (id)initForContentSize:(CGSize)size
{
    if ((self = [super initForContentSize:size]))
    {
        [self setTitle:@"自定义壁纸"];
    }
    return self;
}

- (id)initWithSpecifier:(PSSpecifier *)specifier
{
    if ((self = [super initWithSpecifier:specifier]))
    {
        [self setTitle:@"自定义壁纸"];
    }
    return self;
}

- (NSArray *)specifiers
{
    if (!_specifiers)
    {
        NSMutableArray *specs = [NSMutableArray array];

        PSSpecifier *g1 = [PSSpecifier groupSpecifierWithTitle:@"壁纸"];
        [specs addObject:g1];

        PSSpecifier *sw = [PSSpecifier preferenceSpecifierNamed:@"启用自定义壁纸"
                                                         target:self
                                                            set:@selector(setValue:forSpecifier:)
                                                            get:@selector(valueForSpecifier:)
                                                         detail:nil
                                                            cell:kCPXCellSwitch
                                                             edit:nil];
        [sw setProperty:@"wallpaperEnabled" forKey:@"key"];
        [sw setProperty:@NO forKey:@"default"];
        [specs addObject:sw];

        PSSpecifier *g2 = [PSSpecifier groupSpecifierWithTitle:@"操作"];
        [g2 setProperty:@"建议使用横版图片（如 1280×720），保存后重新连接 CarPlay 即可看到新壁纸。壁纸同时作用于 CarPlay 主屏与应用托管窗口背景。" forKey:@"footerText"];
        [specs addObject:g2];

        PSSpecifier *pick = [PSSpecifier preferenceSpecifierNamed:@"从相册选择壁纸图片"
                                                           target:self
                                                              set:NULL
                                                              get:NULL
                                                           detail:nil
                                                              cell:kCPXCellButton
                                                               edit:nil];
        if ([pick respondsToSelector:@selector(setTarget:action:)])
        {
            [pick setTarget:self action:@selector(presentPicker:)];
        }
        if ([pick respondsToSelector:@selector(setButtonAction:)])
        {
            [pick setButtonAction:@selector(presentPicker:)];
        }
        [specs addObject:pick];

        PSSpecifier *del = [PSSpecifier preferenceSpecifierNamed:@"恢复默认壁纸（删除自定义壁纸）"
                                                          target:self
                                                             set:NULL
                                                             get:NULL
                                                          detail:nil
                                                             cell:kCPXCellButton
                                                              edit:nil];
        if ([del respondsToSelector:@selector(setTarget:action:)])
        {
            [del setTarget:self action:@selector(deleteWallpaper:)];
        }
        if ([del respondsToSelector:@selector(setButtonAction:)])
        {
            [del setButtonAction:@selector(deleteWallpaper:)];
        }
        [specs addObject:del];

        _specifiers = specs;
    }

    return _specifiers;
}

- (id)valueForSpecifier:(PSSpecifier *)spec
{
    NSString *key = [spec propertyForKey:@"key"];
    id v = key ? [CPXPrefsStore valueForKey:key] : nil;
    if (v == nil) v = [spec propertyForKey:@"default"] ?: @NO;
    return v;
}

- (void)setValue:(id)value forSpecifier:(PSSpecifier *)spec
{
    NSString *key = [spec propertyForKey:@"key"];
    if (!key) return;
    [CPXPrefsStore setValue:value forKey:key];
    [CPXPrefsStore postPrefsChangedWithObject:kPrefsWallpaperChanged];
}

- (void)presentPicker:(PSSpecifier *)spec
{
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init];
    config.filter = [PHPickerFilter imagesFilter];
    config.selectionLimit = 1;

    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results
{
    [picker dismissViewControllerAnimated:YES completion:nil];

    PHPickerResult *result = results.firstObject;
    if (!result)
    {
        return;
    }

    NSItemProvider *provider = result.itemProvider;
    NSString *dir = CPX_WALLPAPER_DIR;

    __block void (^loadType)(int);
    NSArray *types = @[@"public.png", @"public.jpeg", @"public.heic", @"public.image"];
    loadType = ^(int idx) {
        if (idx >= (int)types.count)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"导入失败" message:@"无法读取所选图片，请换一张普通 JPG/PNG 图片试试。" delegate:nil cancelButtonTitle:@"好" otherButtonTitles:nil];
                [av show];
            });
            return;
        }

        NSString *type = types[idx];
        [provider loadDataRepresentationForTypeIdentifier:type completionHandler:^(NSData *data, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (data.length > 0)
                {
                    UIImage *img = [UIImage imageWithData:data];
                    NSData *pngData = img ? UIImagePNGRepresentation(img) : data;
                    NSString *path = [dir stringByAppendingPathComponent:@"wallpaper.png"];
                    BOOL ok = [pngData writeToFile:path atomically:YES];
                    CPXPrefsLog(@"[设置面板] 壁纸导入 %@ (%lu 字节, 类型 %@)", ok ? @"成功" : @"失败", (unsigned long)pngData.length, type);

                    NSString *msg = ok ? @"壁纸已保存。重新连接 CarPlay（或杀掉 CarPlay 进程）后生效。" : @"保存失败：无法写入 /var/mobile/Documents/CarPlayX/";
                    UIAlertView *av = [[UIAlertView alloc] initWithTitle:ok ? @"完成" : @"失败" message:msg delegate:nil cancelButtonTitle:@"好" otherButtonTitles:nil];
                    [av show];
                    if (ok)
                    {
                        [CPXPrefsStore postPrefsChangedWithObject:kPrefsWallpaperChanged];
                    }
                }
                else
                {
                    loadType(idx + 1);
                }
            });
        }];
    };

    loadType(0);
}

- (void)deleteWallpaper:(PSSpecifier *)spec
{
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL existed = NO;
    for (NSString *ext in @[@"png", @"jpg", @"jpeg", @"heic", @"webp"])
    {
        NSString *path = [CPX_WALLPAPER_DIR stringByAppendingPathComponent:[NSString stringWithFormat:@"wallpaper.%@", ext]];
        if ([fm fileExistsAtPath:path])
        {
            [fm removeItemAtPath:path error:NULL];
            existed = YES;
        }
    }
    UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"完成" message:existed ? @"自定义壁纸已删除，将恢复系统默认壁纸。" : @"当前没有自定义壁纸。" delegate:nil cancelButtonTitle:@"好" otherButtonTitles:nil];
    [av show];
    if (existed)
    {
        [CPXPrefsStore postPrefsChangedWithObject:kPrefsWallpaperChanged];
    }
}

@end
