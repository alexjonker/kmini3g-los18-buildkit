#!/bin/bash
# sign-build.sh: build a ROM zip signed with YOUR OWN keys instead of the public AOSP test keys
# (fixes LineageOS Trust's "build is signed with public keys" warning).
#
# Keys are created once in /src/.android-certs (= los18/.android-certs on your PC).
# KEEP THAT FOLDER PRIVATE AND BACKED UP: anyone with these keys can sign "updates" your phone
# trusts, and if you lose them, every future update needs a clean flash (data wipe).
#
# Builds userdebug (like official LineageOS; "user" can't build on this device because
# device/qcom/sepolicy-legacy only passes Android 11's neverallow checks with them disabled).
# Run inside the build container:
#   docker run --rm -i -v ./los18:/src -v ./los18-ccache:/ccache -e JOBS=12 los18-builder bash -s < sign-build.sh
# Output: los18/lineage-18.1-kmini3g-signed.zip
set -e
cd /src
KEYS=/src/.android-certs
J=${JOBS:-12}
ZIP=/src/lineage-18.1-kmini3g-signed.zip

# 1) one-time key generation (no passwords, so builds can run unattended)
if [ ! -f $KEYS/releasekey.pk8 ]; then
  echo "=== generating signing keys in $KEYS (one time) ==="
  mkdir -p $KEYS && chmod 700 $KEYS
  subject='/C=NL/ST=None/L=None/O=kmini3g-los18/OU=kmini3g-los18/CN=kmini3g-los18'
  for x in releasekey platform shared media networkstack testkey; do
    printf '\n' | ./development/tools/make_key $KEYS/$x "$subject" || true
    [ -f $KEYS/$x.pk8 ] || { echo "failed to create $x"; exit 1; }
  done
  chmod 600 $KEYS/*
fi

# 2) build the target-files package and the signing tools
source build/envsetup.sh
lunch lineage_kmini3g-userdebug
mka target-files-package otatools -j$J

# 3) sign it and make the flashable zip
TF=$(ls -t $OUT/obj/PACKAGING/target_files_intermediates/lineage_kmini3g-target_files-*.zip | head -1)
unzip -p "$TF" SYSTEM/build.prop | grep -q "^ro.build.type=userdebug$" || { echo "target-files is not a userdebug build: $TF"; exit 1; }
echo "=== signing $TF ==="
sign_target_files_apks -o -d $KEYS "$TF" /src/signed-target_files.zip
ota_from_target_files -k $KEYS/releasekey --block --backup=true \
  /src/signed-target_files.zip $ZIP
rm -f /src/signed-target_files.zip
ls -l $ZIP
echo "done: los18/$(basename $ZIP)"