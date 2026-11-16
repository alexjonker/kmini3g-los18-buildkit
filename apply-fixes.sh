#!/bin/bash
# apply-fixes.sh: everything needed to build and boot LineageOS 18.1 on the Galaxy S5 mini
# (SM-G800H, kmini3g) from the S3NEO / LineageOS / TheMuppets sources in kmini3g.xml.
#
# Runs inside the build container on a freshly synced tree (/src). Safe to run more than
# once: every fix checks whether it is already applied. Leaves no backup files behind.
# build.sh calls it automatically after "repo sync".
set -e
SRC=${SRC:-/src}
DEV=$SRC/device/samsung/kmini3g
VEN=$SRC/vendor/samsung/kmini3g
KCFG=$SRC/kernel/samsung/msm8226/arch/arm/configs/lineage_kmini3g_defconfig
OUT=$SRC/out/target/product/kmini3g

for d in $DEV $VEN $SRC/device/samsung/msm8226-common $SRC/hardware/samsung $(dirname $KCFG); do
  [ -d $d ] || { echo "missing $d (run repo sync first)"; exit 1; }
done
step() { echo "== $*"; }

# ---------------------------------------------------------------------------------------------
step "01 init library: port libinit_kmini3g to Soong (like the official s3ve3gds 18.1 tree)"
cat > $DEV/Android.bp <<'EOF'
//
// Copyright (C) 2020 The LineageOS Project
//
// SPDX-License-Identifier: Apache-2.0
//

soong_namespace {
    imports: ["device/samsung/msm8226-common"],
}
EOF
grep -q 'PRODUCT_SOONG_NAMESPACES' $DEV/device.mk || \
  printf "\n# Soong namespaces\nPRODUCT_SOONG_NAMESPACES += device/samsung/kmini3g\n" >> $DEV/device.mk
rm -f $DEV/init/Android.mk
cat > $DEV/init/Android.bp <<'EOF'
//
// Copyright (C) 2020 The LineageOS Project
//
// SPDX-License-Identifier: Apache-2.0
//

cc_library_static {
    name: "libinit_kmini3g",
    recovery_available: true,
    srcs: ["init_kmini3g.cpp"],
    include_dirs: [
        "device/samsung/msm8226-common/init",
        "system/core/base/include",
        "system/core/init",
    ],
    shared_libs: [
        "libbase",
    ],
    whole_static_libs: ["libinit_helpers_sam8226"]
}
EOF
# G800HQ is checked before G800H (with the old order it could never match)
cat > $DEV/init/init_kmini3g.cpp <<'EOF'
/*
 * Copyright (C) 2020 The LineageOS Project
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <android-base/logging.h>
#include <android-base/properties.h>

#include "property_service.h"

#include "init_msm8226.h"

using android::base::GetProperty;

void vendor_load_properties()
{
    std::string bootloader = GetProperty("ro.bootloader", "");

    if (bootloader.find("G800HQ") == 0) {
        /* kmini3g turkish version */
        property_override("ro.build.description", "kmini3gxx-user 4.4.2 KOT49H G800HXXU1ANL1 release-keys");
        set_ro_build_prop("fingerprint", "samsung/kmini3gxx/kmini3g:4.4.2/KOT49H/G800HXXU1ANL1:user/release-keys");
        set_ro_product_prop("device", "kmini3g");
        set_ro_product_prop("model", "SM-G800HQ");
        set_ro_product_prop("name", "kmini3gxx");
        gsm_properties("3", "0");
    } else if (bootloader.find("G800H") == 0) {
        /* kmini3g */
        property_override("ro.build.description", "kmini3gxx-user 6.0.1 MMB29M G800HXXU1CRJ1 release-keys");
        set_ro_build_prop("fingerprint", "samsung/kmini3gxx/kmini3g:6.0.1/MMB29M/G800HXXU1CRJ1:user/release-keys");
        set_ro_product_prop("device", "kmini3g");
        set_ro_product_prop("model", "SM-G800H");
        set_ro_product_prop("name", "kmini3gxx");
        gsm_properties("3", "0");
    } else {
        gsm_properties("3", "0");
    }

    std::string device = GetProperty("ro.product.device", "");
    LOG(ERROR) << "Found bootloader id " << bootloader << " setting build properties for "
        << device << " device" << std::endl;
}
EOF
sed -i 's|^TARGET_INIT_VENDOR_LIB := .*|TARGET_INIT_VENDOR_LIB := //$(DEVICE_PATH):libinit_kmini3g|' $DEV/BoardConfig.mk

# ---------------------------------------------------------------------------------------------
step "02 rootdir: fstab -> /vendor/etc, init.target.rc -> /vendor/etc/init/hw, latemount /data"
R=$DEV/rootdir
sed -i 's/^LOCAL_MODULE_TAGS  := optional eng/LOCAL_MODULE_TAGS  := optional/' $R/Android.mk
awk '
  /LOCAL_MODULE *:= *fstab.qcom/     {m="fstab"}
  /LOCAL_MODULE *:= *init.target.rc/ {m="init"}
  /^LOCAL_MODULE_PATH/ {
    if (m=="fstab") $0="LOCAL_MODULE_PATH  := $(TARGET_OUT_VENDOR_ETC)"
    if (m=="init")  $0="LOCAL_MODULE_PATH  := $(TARGET_OUT_VENDOR_ETC)/init/hw"
  }
  {print}' $R/Android.mk > $R/Android.mk.new && mv $R/Android.mk.new $R/Android.mk
sed -i '/by-name\/userdata/ s/wait,check,formattable,encryptable/wait,check,formattable,latemount,encryptable/' $R/etc/fstab.qcom

# ---------------------------------------------------------------------------------------------
step "03 duplicate blobs: libfmjni (built from source), libprotobuf-cpp-lite (built by Android 11), libtime_genoff (in msm8226-common)"
PF=$DEV/device-proprietary-files.txt
sed -i '\|proprietary/lib/libfmjni.so:system/lib/libfmjni.so|d' $VEN/kmini3g-vendor.mk
sed -i '\|^lib/libfmjni.so|d' $PF
sed -i '\|proprietary/vendor/lib/libprotobuf-cpp-lite.so:|d' $VEN/kmini3g-vendor.mk
sed -i '\|^vendor/lib/libprotobuf-cpp-lite.so|d' $PF
python3 - "$VEN/Android.mk" <<'EOF'
import sys
p = sys.argv[1]; s = open(p).read()
blocks = s.split("include $(CLEAR_VARS)\n")
keep = [b for b in blocks if "LOCAL_MODULE := libtime_genoff\n" not in b]
open(p, "w").write("include $(CLEAR_VARS)\n".join(keep))
EOF
sed -i '/^    libtime_genoff \\$/d' $VEN/kmini3g-vendor.mk
sed -i '\|^-vendor/lib/libtime_genoff.so|d' $PF

# ---------------------------------------------------------------------------------------------
step "04 ril.h: add MAX_BROADCAST_SMS_CONFIG_INFO (needed by 18.1 libril; struct layout untouched)"
H=$DEV/include/telephony/ril.h
grep -q "MAX_BROADCAST_SMS_CONFIG_INFO" $H || \
  sed -i 's/^#define MAX_RADIO_ACCESS_NETWORKS 8$/&\n#define MAX_BROADCAST_SMS_CONFIG_INFO 25/' $H
grep -q "MAX_BROADCAST_SMS_CONFIG_INFO" $H || { echo "ril.h: could not add define"; exit 1; }

# ---------------------------------------------------------------------------------------------
step "05 XZ ramdisks (recovery.img no longer fits its 13 MiB partition otherwise)"
B=$DEV/BoardConfig.mk
sed -i '/^LZMA_RAMDISK_TARGETS := recovery$/d' $B
grep -q "^BOARD_RAMDISK_USE_XZ := true" $B || echo "BOARD_RAMDISK_USE_XZ := true" >> $B

# ---------------------------------------------------------------------------------------------
step "06 kernel config: align with the official s3ve3g 18.1 kernel (wlan as module, XZ, ...)"
set_cfg() { # NAME VALUE
  sed -i -e "/^CONFIG_$1=/d" -e "/^# CONFIG_$1 is not set/d" $KCFG
  echo "CONFIG_$1=$2" >> $KCFG
}
set_cfg PRONTO_WLAN m          # msm8226-common 18.1 loads /vendor/lib/modules/wlan.ko
set_cfg XZ_DEC y
set_cfg XZ_DEC_ARM y
set_cfg XZ_DEC_BCJ y
set_cfg DECOMPRESS_XZ y
set_cfg RD_XZ y
set_cfg BLK_DEV_LOOP_MIN_COUNT 16
set_cfg EXT4_FS_POSIX_ACL y
set_cfg MEMCG_SWAP_ENABLED y
set_cfg SDFAT_UEVENT y

# ---------------------------------------------------------------------------------------------
step "07 VINTF: drop the duplicate fingerprint HAL entry (otherwise Android 11 rejects the whole manifest)"
# the 18.1 fingerprint@2.1-service ships its own VINTF fragment
sed -i '/^DEVICE_MANIFEST_FILE.*fingerprint\/manifest.xml/d' $DEV/fingerprint/board.mk

# ---------------------------------------------------------------------------------------------
step "08 IR blaster: use the 18.1 Samsung IR service (system_server crashes without an IR HAL)"
python3 - $DEV/device.mk <<'EOF'
import sys, re
p=sys.argv[1]; s=open(p).read()
new = "# IR Blaster\nPRODUCT_PACKAGES += \\\n    android.hardware.ir@1.0-service.samsung\n"
s2 = re.sub(r"# IR Blaster\nPRODUCT_PACKAGES \+= \\\n\s*android\.hardware\.ir@1\.0-impl \\\n\s*consumerir\.msm8226\n", new, s)
if s2 == s and "ir@1.0-service.samsung" not in s:
    sys.exit("device.mk: IR block not found")
open(p,"w").write(s2)
EOF
IRSVC=$SRC/hardware/samsung/hidl/consumerir
if grep -rqs "VINTF_FRAGMENTS\|vintf_fragments" $IRSVC/Android.*; then
  # the service declares itself: remove ours to avoid another duplicate entry
  python3 - $DEV/manifest.xml <<'EOF'
import sys, re
p=sys.argv[1]; s=open(p).read()
s=re.sub(r'\s*<hal format="hidl">\s*<name>android\.hardware\.ir</name>.*?</hal>', '', s, count=1, flags=re.S)
open(p,"w").write(s)
EOF
else
  python3 - $DEV/manifest.xml <<'EOF'
import sys, re
p=sys.argv[1]; s=open(p).read()
s=re.sub(r'(<name>android\.hardware\.ir</name>\s*)<transport arch="32">passthrough</transport>', r'\1<transport>hwbinder</transport>', s, count=1)
open(p,"w").write(s)
EOF
fi
SEP=$DEV/sepolicy/common
OTHER_SEP="$SRC/device/samsung/msm8226-common/sepolicy $SRC/hardware/samsung"
# label the service binary, unless another policy already does
if ! grep -rqs 'ir@1\\.0-service\\.samsung' $OTHER_SEP --include=file_contexts && \
   ! grep -qs 'ir@1\\.0-service\\.samsung' $SEP/file_contexts; then
  printf '\n# IR blaster\n/(vendor|system/vendor)/bin/hw/android\\.hardware\\.ir@1\\.0-service\\.samsung u:object_r:hal_ir_default_exec:s0\n' >> $SEP/file_contexts
fi
# the IR sysfs node is labelled sysfs_sec_ir elsewhere; allow the service to write it if needed
if ! grep -rqs "allow hal_ir_default sysfs_sec_ir" $OTHER_SEP --include=*.te; then
  printf '# IR blaster\nallow hal_ir_default sysfs_sec_ir:dir search;\nallow hal_ir_default sysfs_sec_ir:file rw_file_perms;\n' > $SEP/hal_ir_default.te
fi

# ---------------------------------------------------------------------------------------------
step "09 VINTF: declare all three LiveDisplay interfaces (otherwise boot stops on a black screen)"
python3 - $DEV/manifest.xml <<'EOF'
import sys, re
p=sys.argv[1]; s=open(p).read()
ifaces=["IAdaptiveBacklight","IDisplayColorCalibration","IReadingEnhancement"]
block=('    <hal format="hidl">\n        <name>vendor.lineage.livedisplay</name>\n'
       '        <transport>hwbinder</transport>\n        <version>2.0</version>\n' +
       "".join('        <interface>\n            <name>%s</name>\n            <instance>default</instance>\n        </interface>\n' % i for i in ifaces) +
       '    </hal>')
s2,n=re.subn(r'[ \t]*<hal format="hidl">\s*<name>vendor\.lineage\.livedisplay</name>.*?</hal>', block, s, count=1, flags=re.S)
if n!=1: sys.exit("livedisplay entry not found in manifest.xml")
open(p,"w").write(s2)
EOF

# ---------------------------------------------------------------------------------------------
step "10 screen density 320 (system.prop also set 160, which made everything half size)"
sed -i '/^ro\.sf\.lcd_density=160$/d' $DEV/system.prop
grep -q '^ro\.sf\.lcd_density=320$' $DEV/system.prop || echo "ro.sf.lcd_density=320" >> $DEV/system.prop

# ---------------------------------------------------------------------------------------------
step "11 never offer to replace the user's recovery (hide 'Update Lineage Recovery')"
OV=$DEV/overlay-lineage/packages/apps/Updater/res/values/config.xml
mkdir -p "$(dirname $OV)"
cat > $OV <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<!-- keep whatever recovery the user has installed (e.g. TWRP) -->
<resources>
    <bool name="config_hideRecoveryUpdate">true</bool>
</resources>
EOF

# ---------------------------------------------------------------------------------------------
# The swipe sensor (Validity VFS61xx) doesn't work on 18.1 yet. Without the fingerprint service
# and the android.hardware.fingerprint feature, Android sees no sensor: no fingerprint step in
# the setup wizard and no fingerprint options in Settings. FINGERPRINT=1 builds it in again.
FP_LINE='$(call inherit-product, device/samsung/kmini3g/fingerprint/product.mk)'
if [ "${FINGERPRINT:-0}" = "1" ]; then
  step "12 fingerprint: enabled (FINGERPRINT=1)"
  sed -i "s|^#nofp# ||" $DEV/device.mk
else
  step "12 fingerprint: disabled (sensor doesn't work yet; FINGERPRINT=1 to build it in)"
  sed -i "s|^\(\$(call inherit-product, device/samsung/kmini3g/fingerprint/product.mk)\)|#nofp# \1|" $DEV/device.mk
fi

# ---------------------------------------------------------------------------------------------
# Low-RAM mode (Android Go style memory handling) suits the 1.5 GB of RAM. LOWRAM=0 turns it off.
if [ "${LOWRAM:-1}" = "1" ]; then
  step "13 low-RAM mode: on (LOWRAM=0 to turn off)"
  grep -q '^ro\.config\.low_ram=' $DEV/system.prop || printf '\n# Low-RAM mode\nro.config.low_ram=true\n' >> $DEV/system.prop
  sed -i 's/^ro\.config\.low_ram=.*/ro.config.low_ram=true/' $DEV/system.prop
else
  step "13 low-RAM mode: off (LOWRAM=0)"
  sed -i '/^# Low-RAM mode$/d; /^ro\.config\.low_ram=/d' $DEV/system.prop
fi

# ---------------------------------------------------------------------------------------------
# a changed manifest is only picked up when the merged one is regenerated
rm -rf $OUT/obj/ETC/vendor_manifest.xml_intermediates $OUT/system/vendor/etc/vintf/manifest.xml
echo "== all fixes applied"