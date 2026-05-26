# SPDX-License-Identifier: MIT

include $(TOPDIR)/rules.mk

PKG_NAME:=ipregion
PKG_VERSION:=2026.5.26
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=Roman Ilyin <https://github.com/romanilyin>

include $(INCLUDE_DIR)/package.mk

define Package/ipregion
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Multi-source IP geolocation tester for OpenWrt
  URL:=https://github.com/vernette/ipregion
  DEPENDS:=+curl +ca-bundle +ucode +ucode-mod-fs +ucode-mod-uci
  PKGARCH:=all
endef

define Package/ipregion/description
  Checks how GeoIP, streaming and CDN services detect router IPv4/IPv6 region.
endef

define Build/Compile
endef

define Package/ipregion/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/usr/bin/ipregion $(1)/usr/bin/ipregion
	$(INSTALL_DIR) $(1)/usr/share/ipregion
	$(INSTALL_DATA) ./files/usr/share/ipregion/*.uc $(1)/usr/share/ipregion/
	$(INSTALL_DATA) ./files/usr/share/ipregion/services.json $(1)/usr/share/ipregion/services.json
	$(INSTALL_DATA) ./files/usr/share/ipregion/services-ai.json $(1)/usr/share/ipregion/services-ai.json
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/ipregion $(1)/etc/config/ipregion
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/etc/uci-defaults/90_ipregion $(1)/etc/uci-defaults/90_ipregion
endef

$(eval $(call BuildPackage,ipregion))
