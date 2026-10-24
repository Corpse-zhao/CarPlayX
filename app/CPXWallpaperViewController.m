#import "CPXWallpaperViewController.h"

@implementation CPXWallpaperViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"自定义壁纸";
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return section == 0 ? 1 : 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return section == 0 ? @"壁纸" : @"操作";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == 1)
    {
        return @"建议使用横版图片（如 1280×720），保存后重新连接 CarPlay 即可看到新壁纸。壁纸同时作用于 CarPlay 主屏与应用托管窗口背景。";
    }
    return nil;
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
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    else
    {
        cell = [tableView dequeueReusableCellWithIdentifier:cellId];
        if (!cell)
        {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellId];
        }
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = indexPath.row == 1 ? [UIColor systemRedColor] : [UIColor systemBlueColor];
        cell.textLabel.text = indexPath.row == 0 ? @"从相册选择壁纸图片" : @"恢复默认壁纸（删除自定义壁纸）";
        cell.accessoryType = UITableViewCellAccessoryNone;
    }

    return cell;
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

    NSItemProvider *provider = result.itemProvider;
    NSString *dir = CPX_WALLPAPER_DIR;

    __block void (^loadType)(int);
    NSArray *types = @[@"public.png", @"public.jpeg", @"public.heic", @"public.image"];
    loadType = ^(int idx) {
        if (idx >= (int)types.count)
        {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导入失败" message:@"无法读取所选图片，请换一张普通 JPG/PNG 图片试试。" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
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
                    CPXPrefsLog(@"[App] 壁纸导入 %@ (%lu 字节, 类型 %@)", ok ? @"成功" : @"失败", (unsigned long)pngData.length, type);

                    NSString *msg = ok ? @"壁纸已保存。重新连接 CarPlay（或杀掉 CarPlay 进程）后生效。" : @"保存失败：无法写入 /var/mobile/Documents/CarPlayX/";
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:ok ? @"完成" : @"失败" message:msg preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:alert animated:YES completion:nil];
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
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"完成" message:existed ? @"自定义壁纸已删除，将恢复系统默认壁纸。" : @"当前没有自定义壁纸。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
    if (existed)
    {
        [CPXPrefsStore postPrefsChangedWithObject:kPrefsWallpaperChanged];
    }
}

@end
