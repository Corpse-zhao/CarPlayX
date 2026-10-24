#import <UIKit/UIKit.h>

@interface CPXAppListViewController : UITableViewController
@property (nonatomic, copy) NSString *mode;   /* @"add" 加入/排除 | @"remove" 移除默认 */
@end
