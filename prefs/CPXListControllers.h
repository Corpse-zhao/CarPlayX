#ifndef CPX_ROOT_LIST_CONTROLLER_H
#define CPX_ROOT_LIST_CONTROLLER_H

#import <PhotosUI/PhotosUI.h>

/* Preferences 私有基类手动声明（prefs bundle 不链接 Preferences.framework，靠 dynamic_lookup） */
@interface PSSpecifier : NSObject
- (id)propertyForKey:(NSString *)key;
@end

@interface PSListController : UIViewController <UITableViewDataSource, UITableViewDelegate> {
    @protected
    NSArray *_specifiers;   /* 必须声明在基类接口里：PSListController 数据源直接访问自己的 ivar */
}
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (void)reloadSpecifiers;
@end

@interface CPXRootListController : PSListController
@property (nonatomic, retain) UITableView *rootTable;
@property (nonatomic, retain) NSArray *appList;   /* SpringBoard 提供的全量 app 清单 */
- (void)requestAppList;
@end

/* 应用列表页：mode = @"add" 加入/排除 | @"remove" 移除默认应用 */
@interface CPXAppListController : UIViewController <UITableViewDataSource, UITableViewDelegate>
- (id)initWithAppList:(NSArray *)appList mode:(NSString *)mode;
@end

/* 壁纸设置页 */
@interface CPXWallpaperController : UIViewController <UITableViewDataSource, UITableViewDelegate, PHPickerViewControllerDelegate>
@property (nonatomic, retain) UITableView *table;
@end

#endif
