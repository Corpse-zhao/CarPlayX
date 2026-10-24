#ifndef CPX_ROOT_LIST_CONTROLLER_H
#define CPX_ROOT_LIST_CONTROLLER_H

#import <PhotosUI/PhotosUI.h>

/* Preferences 私有类手动声明（不链接 Preferences.framework，dynamic_lookup 运行时解析） */

@interface PSSpecifier : NSObject
- (id)propertyForKey:(NSString *)key;
- (void)setProperty:(id)property forKey:(NSString *)key;
+ (id)groupSpecifierWithTitle:(NSString *)title;
+ (id)preferenceSpecifierNamed:(NSString *)name target:(id)target set:(SEL)set get:(SEL)get detail:(Class)detail cell:(NSInteger)cellType edit:(NSString *)edit;
- (void)setTarget:(id)target action:(SEL)action;      /* 部分版本提供 */
- (void)setButtonAction:(SEL)action;                  /* 部分版本提供，调用前 respondsToSelector */
@end

@interface PSListController : UIViewController <UITableViewDataSource, UITableViewDelegate> {
    @protected
    NSArray *_specifiers;
}
- (id)initForContentSize:(CGSize)size;
- (id)initWithSpecifier:(PSSpecifier *)specifier;
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (void)reloadSpecifiers;
- (id)readPreferenceValue:(PSSpecifier *)specifier;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
@end

/* PSPCellType 常量（与 Preferences.framework 一致） */
static const NSInteger kCPXCellGroup = 0;
static const NSInteger kCPXCellStaticText = 2;
static const NSInteger kCPXCellLink = 3;
static const NSInteger kCPXCellSwitch = 10;
static const NSInteger kCPXCellButton = 11;

/* 主页 */
@interface CPXRootListController : PSListController
@end

/* 应用列表页（mode 由子类决定） */
@interface CPXAppListController : PSListController
- (NSString *)mode;
@end

@interface CPXAddListController : CPXAppListController
@end

@interface CPXRemoveListController : CPXAppListController
@end

/* 壁纸设置页 */
@interface CPXWallpaperController : PSListController <PHPickerViewControllerDelegate>
@end

#endif
