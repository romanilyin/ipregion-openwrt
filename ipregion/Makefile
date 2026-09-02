# SPDX-License-Identifier: MIT

include $(TOPDIR)/rules.mk

PKG_NAME:=ipregion
PKG_VERSION:=2026.9.2
PKG_RELEASE:=3
PKG_LICENSE:=MIT
PKG_MAINTAINER:=Roman Ilyin <https://github.com/romanilyin>
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)
PKG_BUILD_DEPENDS:=curl

include $(INCLUDE_DIR)/package.mk

define Package/ipregion
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Multi-source IP geolocation tester for OpenWrt
  URL:=https://github.com/vernette/ipregion
  DEPENDS:=+curl +ipregion-dns-helper +ca-bundle +ucode +ucode-mod-fs +ucode-mod-uci
  PKGARCH:=all
endef

define Package/ipregion-dns-helper
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Native DNS transport helper for IPRegion
  URL:=https://github.com/romanilyin/ipregion-openwrt
  DEPENDS:=+ca-bundle +libcurl
endef

define Package/ipregion/description
  Checks router region, services and UDP/TCP/DoH/DoT DNS response integrity.
endef

define Package/ipregion-dns-helper/description
  Sends raw DNS queries over UDP, TCP and certificate-verified DNS-over-TLS.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/dns-helper.c $(PKG_BUILD_DIR)/dns-helper.c
endef

define Build/Compile
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_CPPFLAGS) -Wall -Wextra \
		-o $(PKG_BUILD_DIR)/ipregion-dns-helper $(PKG_BUILD_DIR)/dns-helper.c \
		$(TARGET_LDFLAGS) -lcurl
endef

define Package/ipregion/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/usr/bin/ipregion $(1)/usr/bin/ipregion
	$(INSTALL_DIR) $(1)/usr/share/ipregion
	$(INSTALL_DATA) ./files/usr/share/ipregion/*.uc $(1)/usr/share/ipregion/
	$(INSTALL_DATA) ./files/usr/share/ipregion/services.json $(1)/usr/share/ipregion/services.json
	$(INSTALL_DATA) ./files/usr/share/ipregion/services-ai.json $(1)/usr/share/ipregion/services-ai.json
	$(INSTALL_DATA) ./files/usr/share/ipregion/services-dns.json $(1)/usr/share/ipregion/services-dns.json
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/ipregion $(1)/etc/config/ipregion
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/etc/uci-defaults/90_ipregion $(1)/etc/uci-defaults/90_ipregion
endef

define Package/ipregion-dns-helper/install
	$(INSTALL_DIR) $(1)/usr/libexec/ipregion
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/ipregion-dns-helper $(1)/usr/libexec/ipregion/dns-helper
endef

$(eval $(call BuildPackage,ipregion))
$(eval $(call BuildPackage,ipregion-dns-helper))
