#ifndef CPX_PREFERENCES_H
#define CPX_PREFERENCES_H

#include <Foundation/Foundation.h>
#include <UIKit/UIKit.h>

@interface CPXPreferences : NSObject

@property (nonatomic, retain) NSDictionary *cachedPreferences;

+ (instancetype)sharedInstance;

- (void)reloadPreferences;
- (void)updateValue:(id)value forPreferenceKey:(NSString *)key;

- (BOOL)masterEnabled;
- (NSArray *)excludedApplications;   /* user apps NOT forced into CarPlay */
- (NSArray *)removedApplications;    /* any apps (incl. defaults) hidden from CarPlay */
- (BOOL)wallpaperEnabled;
- (NSString *)wallpaperResourceOverride; /* optional specific asset name to replace */
- (BOOL)fiveColumnIconLayout;
- (UIImage *)customWallpaperImage;   /* user's wallpaper from /var/mobile/Documents/CarPlayX */

@end

#endif
