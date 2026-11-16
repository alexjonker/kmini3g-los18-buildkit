#!/bin/bash
# Runs inside the container. /src = source tree (~150 GB), /ccache = compiler cache.
#
# Options (docker run -e NAME=value):
#   JOBS=n       parallel jobs (default: all CPU cores; use fewer if you run out of RAM)
#   SKIP_SYNC=1  don't run "repo sync" (rebuild what you already have)
#   LOWRAM=0     build without low-RAM mode
#   FINGERPRINT=1  build the (not working) fingerprint service in
#   RESET=1      throw away all local changes in the patched projects before applying the fixes
#                (gets your tree back to exactly what a fresh clone of this kit builds)
set -e
cd /src
JOBS=${JOBS:-$(nproc)}
export JOBS
ccache -M 50G >/dev/null

if [ ! -d .repo ]; then
  echo "== repo init lineage-18.1"
  repo init -u https://github.com/LineageOS/android.git -b lineage-18.1 --git-lfs --depth=1
fi
mkdir -p .repo/local_manifests
cp /kit/kmini3g.xml .repo/local_manifests/kmini3g.xml

if [ "${SKIP_SYNC:-0}" != "1" ]; then
  echo "== repo sync"
  repo sync -c -j"$JOBS" --force-sync --no-clone-bundle --no-tags
fi

if [ "${RESET:-0}" = "1" ]; then
  echo "== reset patched projects to their synced state"
  repo forall device/samsung/kmini3g vendor/samsung/kmini3g kernel/samsung/msm8226 \
    -c 'git reset -q --hard && git clean -fdq'
fi

echo "== apply kmini3g fixes"
bash /kit/apply-fixes.sh

echo "== build"
source build/envsetup.sh
lunch lineage_kmini3g-userdebug
mka bacon -j"$JOBS" 2>&1 | tee /src/build.log
test "${PIPESTATUS[0]}" = 0
ls -lh out/target/product/kmini3g/lineage-18.1-*.zip
