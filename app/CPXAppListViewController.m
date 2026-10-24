#import "CPXAppListViewController.h"
#import "CPXPrefsCommon.h"
#import <objc/message.h>

#define CPX_APPLIST_PATH @"/var/mobile/Documents/CarPlayX/applist.plist"

static NSSet *CPXInfraIdentifiers(void)
{
    static NSSet *infra = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        infra = [NSSet setWithArray:@[
            @"com.apple.CarPlayTemplateUIHost", @"com.apple.MusicUIService",
            @"com.apple.springboard", @"com.apple.InCallService",
            @"com.apple.CarPlaySettings", @"com.apple.CarPlayApp"
        ]];
    });
    return infra;
}

@implementation CPXAppListViewController
{
    NSArray *_appList;
    id _replyObserver;   /* 分布式通知观察 token（ARC） */
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = ([self.mode isEqualToString:@"add"]) ? @"加入 / 排除应用" : @"移除默认应用";
    [self loadAppList];

    /* SpringBoard 写完清单会广播回复，收到立即刷新（不等 1.5s 兜底） */
    __weak typeof(self) weakSelf = self;
    _replyObserver = [[objc_getClass("NSDistributedNotificationCenter") defaultCenter]
        addObserverForName:CPX_NOTIFICATION_APP_DATA object:kPrefsAppDataReceiving queue:nil
        usingBlock:^(NSNotification *note)
        {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            dispatch_async(dispatch_get_main_queue(), ^
            {
                [strongSelf loadAppList];
                [strongSelf.tableView reloadData];
            });
        }];
}

- (void)dealloc
{
    if (_replyObserver)
    {
        [[objc_getClass("NSDistributedNotificationCenter") defaultCenter] removeObserver:_replyObserver];
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    /* 先展示已缓存数据，再请求 SpringBoard 刷新（异步写 applist.plist） */
    [self loadAppList];
    [self.tableView reloadData];
    [[objc_getClass("NSDistributedNotificationCenter") defaultCenter] postNotificationName:CPX_NOTIFICATION_APP_DATA object:kPrefsAppDataRequesting userInfo:nil deliverImmediately:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self loadAppList];
        [self.tableView reloadData];
    });
}

- (void)loadAppList
{
    NSDictionary *data = [NSDictionary dictionaryWithContentsOfFile:CPX_APPLIST_PATH];
    NSArray *list = data[@"appList"];
    if (!list.count)
    {
        /* 文件为空（SpringBoard 侧钩子未生效/未注销刷新）→ App 内直接枚举兜底 */
        list = [self fallbackAppList];
    }
    if (!list.count)
    {
        _appList = nil;
        return;
    }
    NSSortDescriptor *stock = [[NSSortDescriptor alloc] initWithKey:@"isStock" ascending:NO];
    NSSortDescriptor *name = [[NSSortDescriptor alloc] initWithKey:@"name" ascending:YES];
    _appList = [list sortedArrayUsingDescriptors:@[stock, name]];
}

#pragma mark - App 进程内兜底枚举（LSApplicationWorkspace）

- (NSArray *)fallbackAppList
{
    NSMutableArray *result = [NSMutableArray array];
    @try
    {
        id workspace = ((id (*)(id, SEL))objc_msgSend)(objc_getClass("LSApplicationWorkspace"), NSSelectorFromString(@"defaultWorkspace"));
        if (!workspace) return result;
        NSArray *proxies = ((id (*)(id, SEL))objc_msgSend)(workspace, NSSelectorFromString(@"installedApplications"));
        if (![proxies isKindOfClass:[NSArray class]]) return result;

        for (id proxy in proxies)
        {
            NSString *bid = ((id (*)(id, SEL))objc_msgSend)(proxy, NSSelectorFromString(@"applicationIdentifier"));
            if (![bid isKindOfClass:[NSString class]] || bid.length == 0) continue;
            if ([CPXInfraIdentifiers() containsObject:bid]) continue;

            NSString *name = ((id (*)(id, SEL))objc_msgSend)(proxy, NSSelectorFromString(@"localizedName"));
            if (![name isKindOfClass:[NSString class]] || name.length == 0) name = bid;

            NSString *appType = ((id (*)(id, SEL))objc_msgSend)(proxy, NSSelectorFromString(@"applicationType"));
            BOOL isStock = [appType isKindOfClass:[NSString class]] && [appType isEqualToString:@"System"];

            UIImage *icon = nil;
            @try
            {
                icon = ((UIImage *(*)(id, SEL, NSString *, int, CGFloat))objc_msgSend)(objc_getClass("UIImage"), NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:"), bid, 0, [UIScreen mainScreen].scale);
            }
            @catch (NSException *e) { icon = nil; }
            NSData *iconData = icon ? UIImagePNGRepresentation(icon) : [NSData data];

            [result addObject:@{@"name": name, @"bundleID": bid, @"iconImage": iconData, @"isStock": @(isStock), @"hasCarPlay": @(NO)}];
        }
        if (result.count)
        {
            CPXPrefsLog(@"[App] applist.plist 为空，已用 LSApplicationWorkspace 兜底枚举 %lu 个应用", (unsigned long)result.count);
        }
    }
    @catch (NSException *e)
    {
        CPXPrefsLog(@"[App] LSApplicationWorkspace 兜底枚举失败: %@", e);
    }
    return result;
}

#pragma mark - 开关状态

- (BOOL)appIsOn:(NSString *)bid
{
    if ([self.mode isEqualToString:@"add"])
    {
        /* 加入模式：默认全开，excludedApps 里的关闭 */
        NSArray *excluded = [CPXPrefsStore valueForKey:@"excludedApps"];
        return !(excluded && [excluded containsObject:bid]);
    }
    NSArray *removed = [CPXPrefsStore valueForKey:@"removedApps"];
    return removed && [removed containsObject:bid];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return _appList.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return [self.mode isEqualToString:@"add"] ? @"勾选 = 在 CarPlay 显示" : @"勾选 = 已从 CarPlay 移除";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    return [self.mode isEqualToString:@"add"]
        ? @"第三方 App 全部默认加入 CarPlay，取消勾选即排除。系统自带 App 默认不强制加入。"
        : @"用于移除 CarPlay 默认添加且系统不允许删除的 App（播客、图书、新闻等），取消勾选即可恢复。";
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

    cell.textLabel.text = app[@"name"] ?: bid;
    cell.detailTextLabel.text = bid;
    cell.imageView.image = [UIImage imageWithData:app[@"iconImage"]];

    BOOL on = [self appIsOn:bid];
    if (!cell.accessoryView || ![cell.accessoryView isKindOfClass:[UISwitch class]])
    {
        UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
        cell.accessoryView = sw;
    }
    UISwitch *sw = (UISwitch *)cell.accessoryView;
    sw.on = on;
    sw.tag = indexPath.row;

    /* 移除时不给系统关键 app（SpringBoard 等基础设施已在上游过滤）加限制；加入模式下系统 app 置灰提示 */
    if ([self.mode isEqualToString:@"add"] && [app[@"isStock"] boolValue])
    {
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
    }
    else
    {
        cell.textLabel.textColor = [UIColor labelColor];
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSDictionary *app = _appList[indexPath.row];
    NSString *bid = app[@"bundleID"];
    NSString *listKey = [self.mode isEqualToString:@"add"] ? @"excludedApps" : @"removedApps";

    BOOL currentlyOn = [self appIsOn:bid];
    BOOL newOn = !currentlyOn;   /* 点击即取反 */

    /* add 模式：行 OFF = 进 excludedApps；remove 模式：行 ON = 进 removedApps */
    BOOL shouldInList = [self.mode isEqualToString:@"add"] ? (!newOn) : newOn;

    NSMutableArray *list = [[CPXPrefsStore valueForKey:listKey] mutableCopy] ?: [NSMutableArray array];
    if (shouldInList && ![list containsObject:bid])
    {
        [list addObject:bid];
    }
    else if (!shouldInList)
    {
        [list removeObject:bid];
    }
    else
    {
        return;
    }

    [CPXPrefsStore setValue:list forKey:listKey];
    [CPXPrefsStore postPrefsChangedWithObject:kPrefsAppLibraryChanged];
    CPXPrefsLog(@"[App] %@ 列表更新: %@ -> %@", listKey, bid, shouldInList ? @"加入名单" : @"移出名单");

    /* 行内开关同步 */
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    if ([cell.accessoryView isKindOfClass:[UISwitch class]])
    {
        ((UISwitch *)cell.accessoryView).on = [self appIsOn:bid];
    }
}

@end
