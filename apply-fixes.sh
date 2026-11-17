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
step "00 shipping API level: move from BoardConfig.mk (read-only there in Android 11) to device.mk, like the S3 Neo"
# Without it the build treats the phone as an Android 11 launch device and leaves out legacy
# services such as ConfigStore: surfaceflinger then waits forever and boot hangs on the logo.
sed -i '/^# Shipping API Level$/d; /^PRODUCT_SHIPPING_API_LEVEL :=/d' $DEV/BoardConfig.mk
grep -q 'product_launched_with_k.mk' $DEV/device.mk || \
  printf '\n# Shipping API level (launched with Android 4.4)\n$(call inherit-product, $(SRC_TARGET_DIR)/product/product_launched_with_k.mk)\n' >> $DEV/device.mk

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
# Fingerprint (Validity VFS61xx swipe sensor in the home button), patched for Android 11.
# the sensor is in the home button: Settings should say "front", not "back of your phone"
SOV=$DEV/overlay-lineage/packages/apps/Settings/res/values/config.xml
mkdir -p "$(dirname $SOV)"
cat > $SOV <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- fingerprint sensor location: 0 = back, 1 = front (home button), 2 = left, 3 = right -->
    <integer name="config_fingerprintSensorLocation">1</integer>
</resources>
EOF
step "12 fingerprint: HAL patched for Android 11, SELinux rule, sensor on the front"
  sed -i "s|^#nofp# ||" $DEV/device.mk   # undo the old "fingerprint off" edit in existing trees
  sed -i 's/^#define LOG_NDEBUG 0$/#define LOG_NDEBUG 1/' $DEV/fingerprint/*.c   # undo old debug logging edit
  # qseecomd stores the TrustZone app's data on /data and has to open /data itself
  grep -qs "system_data_root_file" $DEV/sepolicy/common/tee.te || \
    printf '\n# fingerprint TrustZone app: qseecomd opens /data for its file service\nallow tee system_data_root_file:dir r_dir_perms;\n' >> $DEV/sepolicy/common/tee.te
  # log the TrustZone return codes when a command fails (the HAL only printed "error")
  sed -i -E 's/ALOGE\("(send EnrollBegin error|%s:send vfmEnrollAddImage error|Send vfmEnrollFinish error|Send vfmPayloadBind error|Send vfmEnrollmentPasswordSet error)"(, __FUNCTION__)?\);/ALOGE("\1 (ret=%d result=%d)"\2, ret, resp->result);/' $DEV/fingerprint/fingerprint_tz.c
  # The HAL predates Android 8: enumerate() only returns a count and removal events carry no
  # "remaining" count. Android 11's FingerprintService runs an enumerate cleanup at every boot and
  # waits for the "0 remaining" event forever, so enrolling never starts.
  python3 - $DEV/fingerprint/fingerprint.c <<'EOF'
import sys, re
p = sys.argv[1]; s = open(p).read()
if "kmini3g: Android 8+ enumerate" not in s:
    new_enum = '''static int fingerprint_enumerate(struct fingerprint_device *device) {
    /* kmini3g: Android 8+ enumerate: one TEMPLATE_ENUMERATING event per finger, the last one
     * with remaining_templates = 0 (or a single empty event if nothing is enrolled). */
    ALOGV("----------------> %s ----------------->", __FUNCTION__);
    if (device == NULL) {
        ALOGE("Cannot enumerate saved fingerprints with uninitialized params");
        return -1;
    }

    vcs_fingerprint_device_t* vdev = (vcs_fingerprint_device_t*)device;
    fingerprint_msg_t msg;
    int idx, remaining;

    pthread_mutex_lock(&vdev->lock);
    remaining = vcs_get_enrolled_finger_num();
    if (remaining == 0) {
        memset(&msg, 0, sizeof(msg));
        msg.type = FINGERPRINT_TEMPLATE_ENUMERATING;
        msg.data.enumerated.finger.gid = vdev->active_gid;
        msg.data.enumerated.finger.fid = 0;
        msg.data.enumerated.remaining_templates = 0;
        if (vdev->device.notify) vdev->device.notify(&msg);
    } else {
        for (idx = 1; idx <= MAX_NUM_FINGERS; idx++) {
            if (!tz.finger[idx].exist) continue;
            remaining--;
            memset(&msg, 0, sizeof(msg));
            msg.type = FINGERPRINT_TEMPLATE_ENUMERATING;
            msg.data.enumerated.finger.gid = vdev->active_gid;
            msg.data.enumerated.finger.fid = idx;
            msg.data.enumerated.remaining_templates = remaining;
            if (vdev->device.notify) vdev->device.notify(&msg);
        }
    }
    pthread_mutex_unlock(&vdev->lock);

    return 0;
}
'''
    s, n = re.subn(r'static int fingerprint_enumerate\(struct fingerprint_device \*device\) \{.*?\n\}\n', new_enum, s, count=1, flags=re.S)
    if n != 1: sys.exit("fingerprint.c: enumerate() not found")

    old_rm = '''    fingerprint_msg_t msg;
    msg.type = FINGERPRINT_TEMPLATE_REMOVED;
    msg.data.removed.finger.fid = fid;
'''
    new_rm = '''    fingerprint_msg_t msg;
    memset(&msg, 0, sizeof(msg));
    msg.type = FINGERPRINT_TEMPLATE_REMOVED;
    msg.data.removed.finger.gid = vdev->active_gid;
    msg.data.removed.finger.fid = fid;
    msg.data.removed.remaining_templates = vcs_get_enrolled_finger_num(); /* kmini3g: Android 8+ */
'''
    if s.count(old_rm) != 1: sys.exit("fingerprint.c: send_remove_notice() not as expected")
    s = s.replace(old_rm, new_rm)

    old_all = '''    if (fid == 0) {
        // Delete all fingerprints
'''
    new_all = '''    if (fid == 0) {
        // Delete all fingerprints
        if (vcs_get_enrolled_finger_num() == 0)
            send_remove_notice(vdev, 0); /* kmini3g: Android 8+ expects an event even when empty */
'''
    if s.count(old_all) != 1: sys.exit("fingerprint.c: remove() not as expected")
    s = s.replace(old_all, new_all)
    open(p, "w").write(s)

if "kmini3g: Android 8+ cancel" not in s:
    # cancel() must confirm with FINGERPRINT_ERROR_CANCELED; Settings waits for it before it
    # moves from "locate the sensor" to the actual enrollment screen
    m = re.search(r'static int fingerprint_cancel\(struct fingerprint_device \*device\) \{.*?\n    return ret;\n\}\n', s, flags=re.S)
    if not m: sys.exit("fingerprint.c: cancel() not as expected")
    body = m.group(0).replace("\n    return ret;\n}\n",
        "\n    send_error_notice(vdev, FINGERPRINT_ERROR_CANCELED); /* kmini3g: Android 8+ cancel */\n\n    return ret;\n}\n")
    s = s[:m.start()] + body + s[m.end():]
    open(p, "w").write(s)
EOF

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
step "14 sensors: label the motion sensor's sysfs folder (SELinux blocked it, so auto-rotate had no data)"
# msm8226-common only labels IIO devices on an SPI bus; the S5 mini's MPU6515 sits elsewhere, so
# its sysfs files stay plain "sysfs" and the sensor HAL may not read them.
FC=$DEV/sepolicy/common/file_contexts
grep -q '^/sys/devices/\.\*/iio' $FC || \
  printf '\n# motion sensor (MPU6515) via IIO, on any bus\n/sys/devices/.*/iio:device[0-9](/.*)?    u:object_r:sysfs_iio:s0\n' >> $FC
# init.target.rc hands the sensor's sysfs files (incl. dmp_firmware) to "system" in "on boot", but
# the sensor HAL (class hal) is started by init.rc's own "on boot", which runs first. On some
# boots the HAL then can't upload the motion sensor's firmware (firmware_loaded stays 0) and
# auto-rotate gets no data. Move those lines to "on early-boot", which always runs before.
python3 - $DEV/rootdir/etc/init.target.rc <<'EOF'
import sys
p = sys.argv[1]; lines = open(p).read().split("\n")
if "# kmini3g: sensor permissions before the sensor HAL starts" in lines:
    sys.exit()
out, moved, sec = [], [], None
for l in lines:
    if l.startswith("on "):
        sec = l.strip()
    if sec == "on boot" and "iio" in l and l.strip():
        moved.append(l)
    else:
        out.append(l)
if not moved:
    sys.exit("init.target.rc: no iio lines found in 'on boot'")
out += ["", "# kmini3g: sensor permissions before the sensor HAL starts", "on early-boot"] + moved + [""]
open(p, "w").write("\n".join(out))
EOF
# same for the sensors' input devices (magnetometer etc.), which msm8226-common only labels on some buses
grep -q '^/sys/devices/\.\*/input/input' $FC || \
  printf '/sys/devices/.*/input/input[0-9]+(/.*)?   u:object_r:sysfs_input:s0\n' >> $FC

# ---------------------------------------------------------------------------------------------
step "15 F-Droid preinstalled (latest APK from f-droid.org)"
# must be one folder below the device tree: its Android.mk only includes */Android.mk
FD=$DEV/FDroid
[ -s $DEV/prebuilt/FDroid/FDroid.apk ] && [ ! -s $FD/FDroid.apk ] && mkdir -p $FD && mv $DEV/prebuilt/FDroid/FDroid.apk $FD/
rm -rf $DEV/prebuilt/FDroid; rmdir $DEV/prebuilt 2>/dev/null || true
mkdir -p $FD
if [ ! -s $FD/FDroid.apk ]; then
  curl -fsSL --retry 3 -o $FD/FDroid.apk.tmp https://f-droid.org/F-Droid.apk || { echo "F-Droid download failed"; exit 1; }
  mv -f $FD/FDroid.apk.tmp $FD/FDroid.apk
fi
cat > $FD/Android.mk <<'EOF'
LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
LOCAL_MODULE := FDroid
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_TAGS := optional
LOCAL_SRC_FILES := FDroid.apk
LOCAL_MODULE_SUFFIX := .apk
LOCAL_CERTIFICATE := PRESIGNED
LOCAL_DEX_PREOPT := false
# install the APK byte-for-byte: re-aligning or uncompressing it would break its v2/v3 signature
LOCAL_REPLACE_PREBUILT_APK_INSTALLED := $(LOCAL_PATH)/FDroid.apk
include $(BUILD_PREBUILT)
EOF
grep -q '^    FDroid$' $DEV/device.mk || printf '\n# F-Droid\nPRODUCT_PACKAGES += \\\n    FDroid\n' >> $DEV/device.mk

# ---------------------------------------------------------------------------------------------
step "16 RIL shim: add strdup8to16/strdup16to8 for Samsung's libsec-ril (rild crashed every 5 s)"
# Android 11's libcutils no longer has these; the kmini3g RIL blobs still call them.
SH=$DEV/libshim_secril
mkdir -p $SH
cat > $SH/Android.mk <<'EOF'
LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
LOCAL_SRC_FILES := strdup16.c
LOCAL_MODULE := libshim_secril
LOCAL_MODULE_TAGS := optional
LOCAL_VENDOR_MODULE := true
LOCAL_MULTILIB := 32
include $(BUILD_SHARED_LIBRARY)
EOF
cat > $SH/strdup16.c <<'EOF'
/* strdup8to16 / strdup16to8, removed from libcutils, still used by Samsung's libsec-ril */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef uint16_t char16_t_;

/* UTF-8 -> UTF-16. *out_len = number of UTF-16 units (no terminator). */
char16_t_ *strdup8to16(const char *s, size_t *out_len) {
    if (s == NULL) return NULL;
    size_t n = strlen(s);
    char16_t_ *out = malloc((n + 1) * 2 * sizeof(char16_t_));
    if (out == NULL) return NULL;
    const unsigned char *p = (const unsigned char *)s, *end = p + n;
    size_t o = 0;
    while (p < end) {
        uint32_t c = *p++;
        int extra = 0;
        if (c >= 0xF0) { c &= 0x07; extra = 3; }
        else if (c >= 0xE0) { c &= 0x0F; extra = 2; }
        else if (c >= 0xC0) { c &= 0x1F; extra = 1; }
        else if (c >= 0x80) { c = 0xFFFD; }
        while (extra-- > 0 && p < end && (*p & 0xC0) == 0x80) c = (c << 6) | (*p++ & 0x3F);
        if (c > 0xFFFF) {
            c -= 0x10000;
            out[o++] = (char16_t_)(0xD800 | (c >> 10));
            out[o++] = (char16_t_)(0xDC00 | (c & 0x3FF));
        } else {
            out[o++] = (char16_t_)c;
        }
    }
    out[o] = 0;
    if (out_len) *out_len = o;
    return out;
}

/* UTF-16 -> UTF-8, NUL-terminated. */
char *strdup16to8(const char16_t_ *s, size_t len) {
    if (s == NULL) return NULL;
    char *out = malloc(len * 3 + 1);
    if (out == NULL) return NULL;
    size_t o = 0;
    for (size_t i = 0; i < len; i++) {
        uint32_t c = s[i];
        if (c >= 0xD800 && c < 0xDC00 && i + 1 < len && s[i + 1] >= 0xDC00 && s[i + 1] < 0xE000) {
            c = 0x10000 + ((c - 0xD800) << 10) + (s[++i] - 0xDC00);
        }
        if (c < 0x80) out[o++] = (char)c;
        else if (c < 0x800) { out[o++] = 0xC0 | (c >> 6); out[o++] = 0x80 | (c & 0x3F); }
        else if (c < 0x10000) { out[o++] = 0xE0 | (c >> 12); out[o++] = 0x80 | ((c >> 6) & 0x3F); out[o++] = 0x80 | (c & 0x3F); }
        else { out[o++] = 0xF0 | (c >> 18); out[o++] = 0x80 | ((c >> 12) & 0x3F); out[o++] = 0x80 | ((c >> 6) & 0x3F); out[o++] = 0x80 | (c & 0x3F); }
    }
    out[o] = 0;
    return out;
}
EOF
grep -q 'libsec-ril.so|libshim_secril.so' $DEV/BoardConfig.mk || printf '\n# RIL shim (strdup8to16)\nTARGET_LD_SHIM_LIBS += \\\n    /system/vendor/lib/libsec-ril.so|libshim_secril.so \\\n    /system/vendor/lib/libsec-ril-dsds.so|libshim_secril.so\n' >> $DEV/BoardConfig.mk
grep -q '^    libshim_secril$' $DEV/device.mk || printf '\n# RIL shim\nPRODUCT_PACKAGES += \\\n    libshim_secril\n' >> $DEV/device.mk

# ---------------------------------------------------------------------------------------------
step "17 GPS: add libdsi_netctrl + libqdi from the S3 Neo blobs (GPS backend couldn't load without them)"
# libloc_api_v02 -> libloc_ds_api -> libdsi_netctrl (-> libqdi). The kmini3g blobs lack the last
# two, so the GPS backend fails to load and every GPS request goes to an empty default.
S3B=vendor/samsung/s3ve3g-common/proprietary/vendor/lib
for f in libdsi_netctrl.so libqdi.so; do
  [ -f $SRC/$S3B/$f ] || { echo "missing $S3B/$f (repo sync incomplete?)"; exit 1; }
  grep -q "$S3B/$f" $DEV/device.mk || \
    printf '\n# GPS data-service blob from the S3 Neo\nPRODUCT_COPY_FILES += \\\n    %s/%s:$(TARGET_COPY_OUT_VENDOR)/lib/%s\n' "$S3B" "$f" "$f" >> $DEV/device.mk
done

# ---------------------------------------------------------------------------------------------
# a changed manifest is only picked up when the merged one is regenerated
rm -rf $OUT/obj/ETC/vendor_manifest.xml_intermediates $OUT/system/vendor/etc/vintf/manifest.xml
echo "== all fixes applied"