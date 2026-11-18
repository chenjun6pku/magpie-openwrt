include $(TOPDIR)/rules.mk

PKG_VERSION:=2.0.0
PKG_RELEASE:=1

LUCI_TITLE:=LuCI support for Magpie AI gateway
LUCI_DEPENDS:=+luci-base +rpcd-mod-ucode +magpie
LUCI_PKGARCH:=all

PKG_LICENSE:=MIT
PKG_MAINTAINER:=magpie-openwrt contributors

include $(TOPDIR)/feeds/luci/luci.mk

# The RPC plugin is discovered when rpcd starts; reload it after installation.
define Package/luci-app-magpie/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || /etc/init.d/rpcd reload
endef
