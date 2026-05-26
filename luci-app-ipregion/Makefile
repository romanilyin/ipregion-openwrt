# SPDX-License-Identifier: MIT

include $(TOPDIR)/rules.mk

PKG_VERSION:=2026.5.26
PKG_RELEASE:=2
LUCI_TITLE:=LuCI support for IPRegion
LUCI_DEPENDS:=+ipregion +luci-base +rpcd +rpcd-mod-ucode
LUCI_PKGARCH:=all
PKG_LICENSE:=MIT
PKG_MAINTAINER:=Roman Ilyin <https://github.com/romanilyin>

define Build/Prepare/luci-app-ipregion
	$(FIND) $(PKG_BUILD_DIR) -type f -print0 | $(XARGS) -0 chmod 0644
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
