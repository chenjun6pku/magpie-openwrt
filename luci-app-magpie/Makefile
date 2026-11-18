include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-magpie
PKG_VERSION:=2.0.0
PKG_RELEASE:=1

PKG_LICENSE:=MIT
PKG_MAINTAINER:=magpie-openwrt contributors

include $(INCLUDE_DIR)/package.mk

# File-only package: the default Build/Compile would run make in an empty
# build directory.
define Build/Compile
endef

define Package/luci-app-magpie
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI support for Magpie AI gateway
  DEPENDS:=+luci-base +rpcd-mod-ucode +magpie
  PKGARCH:=all
  URL:=https://github.com/chenjun6pku/magpie-openwrt
  MAINTAINER:=magpie-openwrt contributors
endef

define Package/luci-app-magpie/description
LuCI service-management page for the Magpie AI provider/model gateway.
Provider and model administration remains in Magpie's Web Console.
endef

define Package/luci-app-magpie/install
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/magpie
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/magpie/overview.js $(1)/www/luci-static/resources/view/magpie/overview.js
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-magpie.json $(1)/usr/share/luci/menu.d/luci-app-magpie.json
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-magpie.json $(1)/usr/share/rpcd/acl.d/luci-app-magpie.json
	$(INSTALL_DIR) $(1)/usr/share/rpcd/ucode
	$(INSTALL_BIN) ./root/usr/share/rpcd/ucode/magpie $(1)/usr/share/rpcd/ucode/magpie
endef

define Package/luci-app-magpie/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	rm -f /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	/etc/init.d/rpcd reload
}
endef

$(eval $(call BuildPackage,luci-app-magpie))
