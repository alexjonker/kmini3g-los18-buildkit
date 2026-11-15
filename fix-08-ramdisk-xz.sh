#!/bin/bash
# Fix 08: LZMA_RAMDISK_TARGETS (Lineage 16/17) is ignored in 18.1, so recovery.img
# grew past the 13 MiB partition. Use Android 11's BOARD_RAMDISK_USE_XZ like s3ve3g-common 18.1.
# Kernel has CONFIG_RD_XZ=y.
set -e
B=/src/device/samsung/kmini3g/BoardConfig.mk
sed -i 's/^LZMA_RAMDISK_TARGETS := recovery$/BOARD_RAMDISK_USE_XZ := true/' $B
grep -q "^BOARD_RAMDISK_USE_XZ := true" $B || echo "BOARD_RAMDISK_USE_XZ := true" >> $B
echo "--- check:"
grep -n "RAMDISK" $B
echo "fix-08 applied"