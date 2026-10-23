#import "CPXListControllers.h"
#import "CPXPrefsCommon.h"

@implementation CPXRootListController

- (id)initForContentSize:(CGSize)size
{
    if ((self = [super init]))
    {
        [self setTitle:@"CarPlayX"];

        _rootTable = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
        _rootTable.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _rootTable.delegate = self;
        _rootTable.dataSource = self;
        [self.view addSubview:_rootTable];

        /* 预取 app 清单（SpringBoard 通过分布式通知回传） */
        [self requestAppList];
    }

    return self;
}

- (void)requestAppList
{
    [[NSDistributedNotificationCenter defaultCenter] addObserverForName:CPX_NOTIFICATION_APP_DATA object:kPrefsAppDataReceiving queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        NSDictionary *data = note.userInfo;
        NSArray *list = data[@"appList"];
        if (list)
        {
            self.appList = list;
            CPXPrefsLog(@"[设置面板] 收到 app 清单 %lu 个", (unsigned long)list.count);
        }
    }];
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName:CPX_NOTIFICATION_APP_DATA object:kPrefsAppDataRequesting userInfo:nil deliverImmediately:YES];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section)
    {
        case 0: return 2;   /* 总开关 / 自定义壁纸开关 */
        case 1: return 2;   /* 加入应用 / 移除默认应用 */
        case 2: return 1;   /* 五列布局 */
        case 3: return 1;   /* 复制诊断日志 */
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cellId = @"CPXRootCell";
    static NSString *switchId = @"CPXRootSwitchCell";
    UITableViewCell *cell;

    if (indexPath.section == 0 || indexPath.section == 2)
    {
        cell = [tableView dequeueReusableCellWithIdentifier:switchId];
        if (!cell)
        {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:switchId];
        }

        UISwitch *sw = (UISwitch *)cell.accessoryView;
        if (![sw isKindOfClass:[UISwitch class]])
        {
            sw = [[UISwitch alloc] initWithFrame:CGRectZero];
            cell.accessoryView = sw;
        }

        if (indexPath.section == 0 && indexPath.row == 0)
        {
            cell.textLabel.text = @"启用 CarPlayX";
            id v = [CPXPrefsStore valueForKey:@"masterEnabled"];
            sw.on = v ? [v boolValue] : NO;
            [sw addTarget:self action:@selector(masterSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        }
        else if (indexPath.section == 0 && indexPath.row == 1)
        {
            cell.textLabel.text = @"自定义壁纸";
            id v = [CPXPrefsStore valueForKey:@"wallpaperEnabled"];
            sw.on = v ? [v boolValue] : NO;
            [sw addTarget:self action:@selector(wallpaperSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        }
        else if (indexPath.section == 2)
        {
            cell.textLabel.text = @"五列图标布局";
            id v = [CPXPrefsStore valueForKey:@"fiveColumnIconLayout"];
            sw.on = v ? [v boolValue] : NO;
            [sw addTarget:self action:@selector(fiveColumnSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        }
    }
    else
    {
        cell = [tableView dequeueReusableCellWithIdentifier:cellId];
        if (!cell)
        {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellId];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }

        if (indexPath.section == 1 && indexPath.row == 0)
        {
            cell.textLabel.text = @"加入 / 排除应用";
            cell.detailTextLabel.text = @"强制把 App 加进 CarPlay";
        }
        else if (indexPath.section == 1 && indexPath.row == 1)
        {
            cell.textLabel.text = @"移除默认应用";
            cell.detailTextLabel.text = @"从 CarPlay 隐藏默认 App";
        }
        else if (indexPath.section == 3 && indexPath.row == 0)
        {
            cell.textLabel.text = @"复制诊断日志";
            cell.detailTextLabel.text = nil;
            cell.accessoryType = UITableViewCellAccessoryNone;
        }
    }

    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section)
    {
        case 0: return @"功能开关";
        case 1: return @"应用管理";
        case 2: return @"显示";
        case 3: return @"诊断";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == 1)
    {
        return @"「移除默认应用」可以隐藏 CarPlay 默认自带且系统不允许取消的 App（如播客、图书等）；「加入应用」可以把任意第三方 App 强制加入 CarPlay 主屏。改动即时生效，无需注销。";
    }
    if (section == 3)
    {
        return [NSString stringWithFormat:@"CarPlayX %@ · 基于开源项目 CarPlayEnable (Apache-2.0, Ethan Arbuckle) 移植扩展\n连接车机后把诊断日志发给开发者，便于排查问题。", CPX_VERSION];
    }
    return nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 1 && indexPath.row == 0)
    {
        if (self.appList.count == 0)
        {
            UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"正在加载" message:@"App 清单尚未拿到，请稍后再试一次。" delegate:nil cancelButtonTitle:@"好" otherButtonTitles:nil];
            [av show];
            return;
        }
        CPXAppListController *vc = [[CPXAppListController alloc] initWithAppList:self.appList mode:@"add"];
        [self.navigationController pushViewController:vc animated:YES];
    }
    else if (indexPath.section == 1 && indexPath.row == 1)
    {
        if (self.appList.count == 0)
        {
            UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"正在加载" message:@"App 清单尚未拿到，请稍后再试一次。" delegate:nil cancelButtonTitle:@"好" otherButtonTitles:nil];
            [av show];
            return;
        }
        CPXAppListController *vc = [[CPXAppListController alloc] initWithAppList:self.appList mode:@"remove"];
        [self.navigationController pushViewController:vc animated:YES];
    }
    else if (indexPath.section == 3 && indexPath.row == 0)
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
}

- (void)masterSwitchChanged:(UISwitch *)sender
{
    [CPXPrefsStore setValue:@(sender.on) forKey:@"masterEnabled"];
    [CPXPrefsStore postPrefsChangedWithObject:kPrefsAppLibraryChanged];
}

- (void)wallpaperSwitchChanged:(UISwitch *)sender
{
    [CPXPrefsStore setValue:@(sender.on) forKey:@"wallpaperEnabled"];
    [CPXPrefsStore postPrefsChangedWithObject:kPrefsWallpaperChanged];
}

- (void)fiveColumnSwitchChanged:(UISwitch *)sender
{
    [CPXPrefsStore setValue:@(sender.on) forKey:@"fiveColumnIconLayout"];
    [CPXPrefsStore postPrefsChangedWithObject:kPrefsAppLibraryChanged];
}

@end

/* ============ 应用列表页 ============ */

@implementation CPXAppListController
{
    NSArray *_appList;
    NSString *_mode;
    UITableView *_table;
}

- (id)initWithAppList:(NSArray *)appList mode:(NSString *)mode
{
    if ((self = [super init]))
    {
        NSSortDescriptor *stock = [[NSSortDescriptor alloc] initWithKey:@"isStock" ascending:NO];
        NSSortDescriptor *name = [[NSSortDescriptor alloc] initWithKey:@"name" ascending:YES];
        _appList = [appList sortedArrayUsingDescriptors:@[stock, name]];
        _mode = mode;
        if ([mode isEqualToString:@"add"])
            [self setTitle:@"加入 / 排除应用"];
        else
            [self setTitle:@"移除默认应用"];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    _table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _table.delegate = self;
    _table.dataSource = self;
    [self.view addSubview:_table];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)_appList.count;
}

- (BOOL)appIsIncludedInAddMode:(NSDictionary *)app
{
    /* 加入模式：默认全加，勾选 = 在 CarPlay 上显示 */
    NSArray *excluded = [CPXPrefsStore valueForKey:@"excludedApps"];
    NSString *bid = app[@"bundleID"];
    return !(excluded && [excluded containsObject:bid]);
}

- (BOOL)appIsRemovedInRemoveMode:(NSDictionary *)app
{
    NSArray *removed = [CPXPrefsStore valueForKey:@"removedApps"];
    NSString *bid = app[@"bundleID"];
    return removed && [removed containsObject:bid];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cellId = @"CPXAppCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell)
    {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
    }

    NSDictionary *app = _appList[indexPath.row];
    NSString *bid = app[@"bundleID"];

    cell.textLabel.text = app[@"name"];
    cell.detailTextLabel.text = bid;
    cell.imageView.image = [UIImage imageWithData:app[@"iconImage"]];

    if ([_mode isEqualToString:@"add"])
    {
        cell.accessoryType = [self appIsIncludedInAddMode:app] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        /* 系统自带 app 在"加入"页里置灰（默认不加入也不建议加） */
        cell.textLabel.enabled = ![app[@"isStock"] boolValue];
        cell.imageView.alpha = cell.textLabel.enabled ? 1.0 : 0.35;
    }
    else
    {
        cell.accessoryType = [self appIsRemovedInRemoveMode:app] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        cell.textLabel.enabled = YES;
    }

    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return [_mode isEqualToString:@"add"] ? @"勾选 = 在 CarPlay 显示" : @"勾选 = 已从 CarPlay 移除";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if ([_mode isEqualToString:@"add"])
    {
        return @"第三方 App 全部默认加入 CarPlay，取消勾选即排除。系统自带 App 默认不强制加入（它们原本就在或按需手动加）。";
    }
    return @"用于移除 CarPlay 默认添加且系统不允许删除的 App（播客、图书、新闻等）。取消勾选即可恢复显示。";
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSDictionary *app = _appList[indexPath.row];
    NSString *bid = app[@"bundleID"];
    NSString *key = [_mode isEqualToString:@"add"] ? @"excludedApps" : @"removedApps";
    BOOL currentlyOn = [_mode isEqualToString:@"add"] ? [self appIsIncludedInAddMode:app] : ![self appIsRemovedInRemoveMode:app];

    /* 目前状态 -> 新状态取反 */
    NSMutableArray *list = [[CPXPrefsStore valueForKey:key] mutableCopy] ?: [NSMutableArray array];
    BOOL shouldAddToList = !currentlyOn;

    if (shouldAddToList)
    {
        if (![list containsObject:bid]) [list addObject:bid];
    }
    else
    {
        [list removeObject:bid];
    }

    [CPXPrefsStore setValue:list forKey:key];
    [CPXPrefsStore postPrefsChangedWithObject:kPrefsAppLibraryChanged];
    CPXPrefsLog(@"[设置面板] %@ 列表更新: %@ -> %@", _mode, bid, shouldAddToList ? @"加入名单" : @"移出名单");

    [_table reloadData];
}

@end

/* ============ 壁纸设置页 ============ */

@implementation CPXWallpaperController

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self setTitle:@"自定义壁纸"];

    _table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _table.delegate = self;
    _table.dataSource = self;
    [self.view addSubview:_table];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return section == 0 ? 1 : 2;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *switchId = @"CPXWallSwitchCell";
    static NSString *cellId = @"CPXWallCell";
    UITableViewCell *cell;

    if (indexPath.section == 0)
    {
        cell = [tableView dequeueReusableCellWithIdentifier:switchId];
        if (!cell)
        {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:switchId];
        }
        cell.textLabel.text = @"启用自定义壁纸";

        UISwitch *sw = (UISwitch *)cell.accessoryView;
        if (![sw isKindOfClass:[UISwitch class]])
        {
            sw = [[UISwitch alloc] initWithFrame:CGRectZero];
            cell.accessoryView = sw;
        }
        id v = [CPXPrefsStore valueForKey:@"wallpaperEnabled"];
        sw.on = v ? [v boolValue] : NO;
        [sw addTarget:self action:@selector(enabledChanged:) forControlEvents:UIControlEventValueChanged];
    }
    else
    {
        cell = [tableView dequeueReusableCellWithIdentifier:cellId];
        if (!cell)
        {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellId];
        }
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.textLabel.text = indexPath.row == 0 ? @"从相册选择壁纸图片" : @"恢复默认壁纸";
        cell.textLabel.textColor = indexPath.row == 1 ? [UIColor systemRedColor] : [UIColor labelColor];
    }

    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == 1)
    {
        return @"建议使用横版图片（如 1280×720），保存后重新连接 CarPlay 即可看到新壁纸。壁纸同时作用于 CarPlay 主屏与应用托管窗口背景。";
    }
    return nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 1 && indexPath.row == 0)
    {
        [self presentPicker];
    }
    else if (indexPath.section == 1 && indexPath.row == 1)
    {
        [self deleteWallpaper];
    }
}

- (void)enabledChanged:(UISwitch *)sender
{
    [CPXPrefsStore setValue:@(sender.on) forKey:@"wallpaperEnabled"];
    [CPXPrefsStore postPrefsChangedWithObject:kPrefsWallpaperChanged];
}

- (void)presentPicker
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

    /* 按具体 -> 抽象逐个尝试类型 */
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
                    /* 统一转成 PNG 落盘，避免扩展名/格式坑 */
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

- (void)deleteWallpaper
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
