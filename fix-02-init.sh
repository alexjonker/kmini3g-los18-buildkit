#!/bin/bash
# Fix 02: port libinit_kmini3g to Soong (Android.bp) for LineageOS 18.1,
# modelled on the official s3ve3gds 18.1 tree.
set -e
D=/src/device/samsung/kmini3g
cd $D

# 1. Soong namespace for the device tree (like s3ve3gds)
cat > Android.bp <<'EOF'
//
// Copyright (C) 2020 The LineageOS Project
//
// SPDX-License-Identifier: Apache-2.0
//

soong_namespace {
    imports: ["device/samsung/msm8226-common"],
}
EOF
grep -q 'PRODUCT_SOONG_NAMESPACES' device.mk || printf "\n# Soong namespaces\nPRODUCT_SOONG_NAMESPACES += device/samsung/kmini3g\n" >> device.mk

# 2. init library as a Soong module
rm -f init/Android.mk
cat > init/Android.bp <<'EOF'
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

# 3. init code using the 18.1 helper functions (G800HQ checked first, it never matched before)
cat > init/init_kmini3g.cpp <<'EOF'
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

# 4. point the build at the namespaced module
sed -i 's|^TARGET_INIT_VENDOR_LIB := .*|TARGET_INIT_VENDOR_LIB := //$(DEVICE_PATH):libinit_kmini3g|' BoardConfig.mk

echo "--- check:"
grep -n "TARGET_INIT_VENDOR_LIB" BoardConfig.mk
grep -n -A2 "SOONG_NAMESPACES" device.mk
ls init/
echo "fix-02 applied"