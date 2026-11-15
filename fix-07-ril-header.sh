#!/bin/bash
# Fix 07: device/samsung/kmini3g/include/telephony/ril.h overrides the common ril.h
# but lacks MAX_BROADCAST_SMS_CONFIG_INFO (added in 18.1 libril). Add only that define,
# same value/place as s3ve3g-common 18.1. Struct layout stays untouched (modem blob ABI).
set -e
H=/src/device/samsung/kmini3g/include/telephony/ril.h
grep -q "MAX_BROADCAST_SMS_CONFIG_INFO" $H || \
  sed -i 's/^#define MAX_RADIO_ACCESS_NETWORKS 8$/&\n#define MAX_BROADCAST_SMS_CONFIG_INFO 25/' $H
echo "--- check:"
grep -n "MAX_RADIO_ACCESS_NETWORKS\|MAX_BROADCAST_SMS_CONFIG_INFO" $H
echo "fix-07 applied"