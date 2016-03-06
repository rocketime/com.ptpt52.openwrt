#
# Copyright (C) 2014-2015 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:=natcap
PKG_VERSION:=2.0.1
PKG_RELEASE:=$(PKG_SOURCE_VERSION)

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.xz
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_VERSION)
PKG_SOURCE_URL:=https://dl.dropboxusercontent.com/u/2146530/git/natcap.git
PKG_SOURCE_PROTO:=git
PKG_SOURCE_VERSION:=61272b79767e57cbc7675758665e40c7ca5faeda
PKG_MAINTAINER:=Chen Minqiang <ptpt52@gmail.com>
PKG_LICENSE:=GPL-2.0

include $(INCLUDE_DIR)/package.mk

define Package/natcapd/Default
  CATEGORY:=Ptpt52
  SUBMENU:=Natcap Support
  AUTOLOAD:=$(call AutoProbe,natcapd)
  DEPENDS:= +kmod-natcap
endef

define Package/natcapd
  $(call Package/natcapd/Default)
  TITLE:=Natcapd agent for natcap
endef

define Package/natcapd/description
 Natcapd agent for natcap
endef

define Build/Configure
endef

define Package/natcapd/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/natcapd.init $(1)/etc/init.d/natcapd
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DATA) ./files/natcapd.config $(1)/etc/config/natcapd
endef

define Package/natcapd/conffiles
endef

define KernelPackage/natcap
  CATEGORY:=Ptpt52
  SUBMENU:=Natcap Support
  TITLE:=Natcap kernel driver
  FILES:=$(PKG_BUILD_DIR)/natcap.ko
  AUTOLOAD:=$(call AutoProbe,natcap)
  KCONFIG:=
  DEPENDS:=+kmod-nf-conntrack +kmod-nf-nat
endef

define KernelPackage/natcap/description
  Driver for natcap packet proxy to avoid inspection
endef

include $(INCLUDE_DIR)/kernel-defaults.mk

MAKE_KMOD := $(MAKE) -C "$(LINUX_DIR)" \
		CROSS_COMPILE="$(TARGET_CROSS)" \
		ARCH="$(LINUX_KARCH)" \
		PATH="$(TARGET_PATH)" \
		SUBDIRS="$(PKG_BUILD_DIR)" \

define Build/Compile
	$(MAKE_KMOD) \
		MODFLAGS="-DMODULE" \
		modules
	pwd
endef

$(eval $(call KernelPackage,natcap))
$(eval $(call BuildPackage,natcapd))