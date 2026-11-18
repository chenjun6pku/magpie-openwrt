include $(TOPDIR)/rules.mk

PKG_NAME:=magpie
PKG_VERSION:=0.1.4444
PKG_RELEASE:=1

# Pin the upstream Git object rather than relying on an unverified source
# archive. CI resolves the upstream tag and confirms it matches this commit.
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/yetone/magpie.git
PKG_SOURCE_DATE:=2026-11-18
PKG_SOURCE_VERSION:=42181fdd27faadebd6d0bcf4d44322e404291ba8
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_VERSION)
PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz

# modernc.org/sqlite in the pinned upstream Magpie release does not support
# MIPS/MIPSel/MIPS64/MIPS64el or big-endian PPC64. Fail early on those targets.
MAGPIE_UNSUPPORTED_ARCHES:=mips% mipsel% mips64% mips64el% ppc64
ifneq ($(filter $(MAGPIE_UNSUPPORTED_ARCHES),$(ARCH) $(ARCH_PACKAGES)),)
  $(error Magpie is not supported on this target architecture: $(ARCH)/$(ARCH_PACKAGES))
endif

PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=magpie-openwrt contributors
PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/yetone/magpie
GO_PKG_BUILD_PKG:=github.com/yetone/magpie
GO_PKG_INSTALL_ALL:=1
GO_PKG_INSTALL_BIN_PATH:=/usr/bin
GO_PKG_TAGS:=nogui
GO_PKG_LDFLAGS:=-s -w
GO_PKG_LDFLAGS_X:=main.version=$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

# Match the upstream headless build; Wails/GTK/WebKit desktop UI is excluded.
GO_PKG_TARGET_VARS += CGO_ENABLED=0
GO_PKG_DEFAULT_LDFLAGS:=

define Package/magpie
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Magpie AI provider and model gateway
  URL:=https://github.com/yetone/magpie
  DEPENDS:=$(GO_ARCH_DEPENDS) +ca-bundle +busybox
  USERID:=magpie:magpie
endef

define Package/magpie/description
Magpie AI provider/model gateway, built in upstream nogui mode. The package
runs `magpie serve --web` under procd with loopback-only listeners by default.
endef

define Package/magpie/conffiles
/etc/config/magpie
endef

define Package/magpie/install
	$(call GoPackage/Package/Install/Bin,$(1))
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/magpie.config $(1)/etc/config/magpie
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/magpie.init $(1)/etc/init.d/magpie
endef

define Package/magpie/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/magpie enable
	/etc/init.d/magpie start
}
endef

define Package/magpie/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || /etc/init.d/magpie stop
endef

$(eval $(call BuildPackage,magpie))
