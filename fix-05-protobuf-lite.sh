#!/bin/bash
# Fix 05: Android 11 builds libprotobuf-cpp-lite for vendor itself.
# No kmini3g blob links against the prebuilt copy (checked with readelf), so drop it.
set -e
sed -i '\|proprietary/vendor/lib/libprotobuf-cpp-lite.so:|d' /src/vendor/samsung/kmini3g/kmini3g-vendor.mk
sed -i '\|^vendor/lib/libprotobuf-cpp-lite.so|d' /src/device/samsung/kmini3g/device-proprietary-files.txt
echo "--- check (should print nothing):"
grep -n "libprotobuf-cpp-lite" /src/vendor/samsung/kmini3g/kmini3g-vendor.mk /src/device/samsung/kmini3g/device-proprietary-files.txt || true
echo "fix-05 applied"