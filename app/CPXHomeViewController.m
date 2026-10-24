#import <UIKit/UIKit.h>
#import "CPXPrefsCommon.h"
#import "CPXAppListViewController.h"
#import "CPXWallpaperViewController.h"

@interface CPXHomeViewController : UITableViewController
@end

@implementation CPXHomeViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"板栗仁CarPlay";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.clearsSelectionOnViewWillAppear = NO;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    /* 向 SpringBoard 请求最新 app 清单（会写入 applist.plist） */
    [[objc_getClass("NSDistributedNotificationCenter") defaultCenter] postNotificationName:CPX_NOTIFICATION_APP_DATA object:kPrefsAppDataRequesting userInfo:nil deliverImmediately:YES];
    [self.tableView reloadData];
}

#pragma mark - 数据

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section)
    {
        case 0: return 2;   /* 总开关 / 自定义壁纸开关 */
        case 1: return 3;   /* 加入应用 / 移除默认应用 / 自定义壁纸 */
        case 2: return 1;   /* 五列布局 */
        case 3: return 1;   /* 复制诊断日志 */
    }
    return 0;
}

- (NSString *)keyForRowSection0:(NSInteger)row
{
    return row == 0 ? @"masterEnabled" : @"wallpaperEnabled";
}

#pragma mark - Cell

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *switchId = @"CPXSwitchCell";
    static NSString *linkId = @"CPXLinkCell";
    static NSString *buttonId = @"CPXButtonCell";
    UITableViewCell *cell;

    if (indexPath.section == 0 || indexPath.section == 2)
    {
        cell = [tableView dequeueReusableCellWithIdentifier:switchId];
        if (!cell)
        {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:switchId];
        }
        cell.textLabel.text = (indexPath.section == 0 && indexPath.row == 0) ? @"启用 CarPlay 功能"
                            : (indexPath.section == 0) ? @"自定义壁纸"
                            : @"五列图标布局";

        UISwitch *sw = (UISwitch *)cell.accessoryView;
        if (![sw isKindOfClass:[UISwitch class]])
        {
            sw = [[UISwitch alloc] initWithFrame:CGRectZero];
            cell.accessoryView = sw;
        }
        NSString *key = indexPath.section == 2 ? @"fiveColumnIconLayout" : [self keyForRowSection0:indexPath.row];
        id v = [CPXPrefsStore valueForKey:key];
        sw.on = v ? [v boolValue] : NO;
        sw.tag = indexPath.section * 10 + indexPath.row;
        [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    else if (indexPath.section == 1)
    {
        cell = [tableView dequeueReusableCellWithIdentifier:linkId];
        if (!cell)
        {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:linkId];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        cell.imageView.image = nil;
        cell.detailTextLabel.text = nil;
        cell.textLabel.textColor = [UIColor labelColor];
        switch (indexPath.row)
        {
            case 0:
                cell.textLabel.text = @"加入 / 排除应用";
                cell.detailTextLabel.text = @"强制把 App 加进 CarPlay";
                break;
            case 1:
                cell.textLabel.text = @"移除默认应用";
                cell.detailTextLabel.text = @"从 CarPlay 隐藏默认 App";
                break;
            case 2:
                cell.textLabel.text = @"自定义壁纸设置";
                cell.detailTextLabel.text = @"从相册导入 / 恢复默认";
                break;
        }
    }
    else
    {
        cell = [tableView dequeueReusableCellWithIdentifier:buttonId];
        if (!cell)
        {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:buttonId];
        }
        cell.textLabel.text = @"复制诊断日志";
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = [UIColor systemBlueColor];
        cell.accessoryType = UITableViewCellAccessoryNone;
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
    if (section == 0)
    {
        return @"开关改动即时生效，无需注销。设置 CarPlay 自定义壁纸后，重新连接 CarPlay（或杀掉 CarPlay 进程）即可看到新壁纸。";
    }
    if (section == 3)
    {
        return @"板栗仁CarPlay · 基于开源项目 CarPlayEnable (Apache-2.0, Ethan Arbuckle) 移植扩展\n连接车机后把诊断日志发给开发者，便于排查问题。";
    }
    return nil;
}

#pragma mark - 交互

- (void)switchChanged:(UISwitch *)sender
{
    NSInteger section = sender.tag / 10;
    NSInteger row = sender.tag % 10;
    NSString *key = section == 2 ? @"fiveColumnIconLayout" : (row == 0 ? @"masterEnabled" : @"wallpaperEnabled");
    [CPXPrefsStore setValue:@(sender.on) forKey:key];
    NSString *notify = [key isEqualToString:@"wallpaperEnabled"] ? kPrefsWallpaperChanged : kPrefsAppLibraryChanged;
    [CPXPrefsStore postPrefsChangedWithObject:notify];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 1)
    {
        if (indexPath.row == 0)
        {
            CPXAppListViewController *vc = [[CPXAppListViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
            vc.mode = @"add";
            [self.navigationController pushViewController:vc animated:YES];
        }
        else if (indexPath.row == 1)
        {
            CPXAppListViewController *vc = [[CPXAppListViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
            vc.mode = @"remove";
            [self.navigationController pushViewController:vc animated:YES];
        }
        else
        {
            [self.navigationController pushViewController:[[CPXWallpaperViewController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
        }
    }
    else if (indexPath.section == 3)
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
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已复制到剪贴板" message:@"最近 20KB 诊断日志已复制，直接粘贴发给开发者即可。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

@end
