ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = carplayx

carplayx_FILES = $(wildcard src/hooks/*.xm) $(wildcard src/*.mm)
carplayx_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

after-carplayx-stage::
	mkdir -p $(THEOS_STAGING_DIR)/DEBIAN/
	cp postinst_postrm $(THEOS_STAGING_DIR)/DEBIAN/postinst
	cp postinst_postrm $(THEOS_STAGING_DIR)/DEBIAN/postrm

SUBPROJECTS += app

include $(THEOS_MAKE_PATH)/aggregate.mk
