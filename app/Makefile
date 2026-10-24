ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = CarPlayX

CarPlayX_FILES = main.m CPXAppDelegate.m CPXHomeViewController.m CPXAppListViewController.m CPXWallpaperViewController.m CPXPrefsCommon.m
CarPlayX_FRAMEWORKS = UIKit Foundation PhotosUI
CarPlayX_CFLAGS = -fobjc-arc
CarPlayX_INSTALL_PATH = /Applications
CarPlayX_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/application.mk
