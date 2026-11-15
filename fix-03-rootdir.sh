#!/bin/bash
# Fix 03: rootdir for LineageOS 18.1 (modelled on s3ve3g-common 18.1)
#  - LOCAL_MODULE_TAGS "eng" is obsolete
#  - fstab.qcom -> vendor/etc, init.target.rc -> vendor/etc/init/hw
#  - /data entries get "latemount" like s3ve3g 18.1
set -e
cd /src/device/samsung/kmini3g/rootdir

sed -i 's/^LOCAL_MODULE_TAGS  := optional eng/LOCAL_MODULE_TAGS  := optional/' Android.mk
awk '
  /LOCAL_MODULE *:= *fstab.qcom/     {m="fstab"}
  /LOCAL_MODULE *:= *init.target.rc/ {m="init"}
  /^LOCAL_MODULE_PATH/ {
    if (m=="fstab") $0="LOCAL_MODULE_PATH  := $(TARGET_OUT_VENDOR_ETC)"
    if (m=="init")  $0="LOCAL_MODULE_PATH  := $(TARGET_OUT_VENDOR_ETC)/init/hw"
  }
  {print}' Android.mk > Android.mk.new && mv Android.mk.new Android.mk

sed -i '/by-name\/userdata/ s/wait,check,formattable,encryptable/wait,check,formattable,latemount,encryptable/' etc/fstab.qcom

echo "--- check:"
grep -n "LOCAL_MODULE \|LOCAL_MODULE_TAGS\|LOCAL_MODULE_PATH" Android.mk
grep -n "userdata" etc/fstab.qcom
echo "fix-03 applied"