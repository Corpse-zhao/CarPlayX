ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = carplayxprefs

carplayxprefs_FILES = CPXPrefsCommon.m CPXListControllers.m
carplayxprefs_INSTALL_PATH = /Library/PreferenceBundles
carplayxprefs_FRAMEWORKS = UIKit Foundation PhotosUI
carplayxprefs_CFLAGS = -fobjc-arc
carplayxprefs_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/carplayxprefs.plist$(ECHO_END)
