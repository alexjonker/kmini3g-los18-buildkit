#!/bin/bash
# Fix 04: libfmjni.so is built from source (vendor/qcom/opensource/libfmjni),
# so drop the prebuilt copy from the kmini3g blobs (like s3ve3g 18.1).
set -e
sed -i '\|proprietary/lib/libfmjni.so:system/lib/libfmjni.so|d' /src/vendor/samsung/kmini3g/kmini3g-vendor.mk
sed -i '\|^lib/libfmjni.so|d' /src/device/samsung/kmini3g/device-proprietary-files.txt
echo "--- check (should print nothing):"
grep -n "libfmjni" /src/vendor/samsung/kmini3g/kmini3g-vendor.mk /src/device/samsung/kmini3g/device-proprietary-files.txt || true
echo "fix-04 applied"