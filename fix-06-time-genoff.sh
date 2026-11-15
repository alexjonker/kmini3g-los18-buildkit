#!/bin/bash
# Fix 06: libtime_genoff is shipped by both vendor/samsung/kmini3g (as a module)
# and vendor/samsung/msm8226-common (TheMuppets 18.1, as a copy). Keep the common one.
set -e
V=/src/vendor/samsung/kmini3g
python3 - "$V/Android.mk" <<'EOF'
import re, sys
p = sys.argv[1]
s = open(p).read()
blocks = s.split("include $(CLEAR_VARS)\n")
keep = [b for b in blocks if "LOCAL_MODULE := libtime_genoff\n" not in b]
open(p, "w").write("include $(CLEAR_VARS)\n".join(keep))
EOF
sed -i '/^    libtime_genoff \\$/d' $V/kmini3g-vendor.mk
sed -i '\|^-vendor/lib/libtime_genoff.so|d' /src/device/samsung/kmini3g/device-proprietary-files.txt
echo "--- check (should print nothing):"
grep -n "libtime_genoff" $V/Android.mk $V/kmini3g-vendor.mk /src/device/samsung/kmini3g/device-proprietary-files.txt || true
echo "--- remaining modules / packages:"
grep -n "LOCAL_MODULE :=" $V/Android.mk
grep -n -A3 "^PRODUCT_PACKAGES" $V/kmini3g-vendor.mk
echo "fix-06 applied"