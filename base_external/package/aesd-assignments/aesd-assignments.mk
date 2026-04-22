
##############################################################
#
# AESD-ASSIGNMENTS
#
##############################################################

AESD_ASSIGNMENTS_VERSION = da3e1eb4a474d17bba201735032d032bc13620b0
# Note: Be sure to reference the *ssh* repository URL here (not https) to work properly
# with ssh keys and the automated build/test system.
AESD_ASSIGNMENTS_SITE = git@github.com:mohamed-soubhi/Assignment5Part1_MSoubhi.git
AESD_ASSIGNMENTS_SITE_METHOD = git
AESD_ASSIGNMENTS_GIT_SUBMODULES = YES

define AESD_ASSIGNMENTS_BUILD_CMDS
	$(MAKE) $(TARGET_CONFIGURE_OPTS) -C $(@D)/server all
endef

define AESD_ASSIGNMENTS_INSTALL_TARGET_CMDS
	$(INSTALL) -m 0755 $(@D)/server/aesdsocket $(TARGET_DIR)/usr/bin/aesdsocket
	$(INSTALL) -d 0755 $(TARGET_DIR)/etc/init.d
	$(INSTALL) -m 0755 $(AESD_ASSIGNMENTS_PKGDIR)/S99aesdsocket $(TARGET_DIR)/etc/init.d/S99aesdsocket
endef

$(eval $(generic-package))
