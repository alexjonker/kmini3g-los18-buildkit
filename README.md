# LineageOS 18.1 (Android 11) for the Galaxy S5 mini (SM-G800H / kmini3g)

A build kit that turns the existing S3NEO / LineageOS sources into a working, bootable
LineageOS 18.1 for the Samsung Galaxy S5 mini (3G, SM-G800H). Everything runs inside Docker,
so you don't have to install an Android build environment on your PC.

Unofficial. Not affiliated with LineageOS or Samsung. Flash at your own risk.

## Status

| Works | Not tested yet |
|-------|----------------|
| Boot, display, touch, setup wizard | Camera |
| Correct screen density | Wi-Fi, Bluetooth, GPS |
| SELinux enforcing | Calls / mobile data |
| | Sound, fingerprint, IR blaster |

Kernel: 3.4 (msm8226, LineageOS). Security patch level: 2024-02-05.

## What you need

- Linux PC (or Windows with WSL2) with Docker
- 16 GB RAM or more (less works with fewer jobs, see below)
- At least 250 GB free disk space (sources ~150 GB, build output, compiler cache)
- The phone with a custom recovery (TWRP or LineageOS recovery)
- A few hours for the first download and build

## Build

```bash
git clone https://github.com/alexjonker/kmini3g-los18-buildkit
cd kmini3g-los18-buildkit

# 1. build the container image (once, and again after you change one of the scripts)
docker build -t los18-builder .

# 2. folders for the source tree and the compiler cache
mkdir -p ./los18 ./los18-ccache

# 3. download the sources, apply the fixes and build
docker run --rm -it -v ./los18:/src -v ./los18-ccache:/ccache los18-builder
```

The result is `./los18/out/target/product/kmini3g/lineage-18.1-<date>-UNOFFICIAL-kmini3g.zip`.

The first run downloads about 100 GB. If the download or build stops (network, rate limits),
just run the same command again: it continues where it stopped.

### Options

Add these to the `docker run` command as `-e NAME=value`:

| Option | Effect |
|--------|--------|
| `JOBS=4` | Use 4 parallel jobs instead of all CPU cores. Lower it if the build runs out of RAM. |
| `SKIP_SYNC=1` | Don't download updates, only rebuild. Much faster for a second build. |
| `RESET=1` | Throw away all local changes in the patched projects first, so your tree is exactly what a fresh clone builds. |

Example rebuild without syncing:

```bash
docker run --rm -it -e SKIP_SYNC=1 -v ./los18:/src -v ./los18-ccache:/ccache los18-builder
```

Open a shell in the build environment (to look around or debug):

```bash
docker run --rm -it -v ./los18:/src -v ./los18-ccache:/ccache los18-builder bash
```

## Flash

The first install of this ROM needs a factory reset (also when coming from LineageOS 16/17
or another ROM). Back up anything you need first.

**TWRP:** Wipe → Advanced Wipe → Dalvik/ART Cache, Cache, Data, System → Install the zip → Reboot.

**LineageOS recovery:** Factory reset → Format data/factory reset, then Apply update →
Apply from ADB, and on the PC:

```bash
adb sideload los18/out/target/product/kmini3g/lineage-18.1-*-UNOFFICIAL-kmini3g.zip
```

"Signature verification failed" is expected for a self-built ROM; choose Yes. The PC stops
around 47% with `failed to read command: Success`; that is normal.

The first boot takes a few minutes. The ROM never replaces your recovery: the
"Update Lineage Recovery" option is hidden on purpose, so TWRP stays installed.

**Updates:** flash the new zip over the old one, no reset needed.
If you use Magisk, flash or patch it again after every update.

## What the fixes do

The S3NEO device tree for lineage-18.1 doesn't build or boot as-is. `apply-fixes.sh` changes
the synced sources (it's safe to run more than once):

| # | Problem | Fix |
|---|---------|-----|
| 01 | init library uses the old Make build | Ported to Soong, like the official S3 Neo (s3ve3gds) tree |
| 02 | fstab / init.target.rc in old locations | Moved to `/vendor`, `latemount` for `/data` |
| 03 | Duplicate libraries break the build | Dropped prebuilt libfmjni, libprotobuf-cpp-lite, libtime_genoff |
| 04 | ril.h lacks a define 18.1 needs | Added `MAX_BROADCAST_SMS_CONFIG_INFO` |
| 05 | recovery.img too big for its partition | XZ-compressed ramdisks |
| 06 | Kernel config out of date | Aligned with the official S3 Neo 18.1 kernel (Wi-Fi as module, XZ, …) |
| 07 | Fingerprint HAL declared twice: Android rejects the whole HAL manifest, boot hangs on the logo | Removed the duplicate declaration |
| 08 | Old IR blaster library no longer exists: system_server crashes, "Can't load Android system" | Switched to the 18.1 Samsung IR service + SELinux rules |
| 09 | LiveDisplay HAL only partly declared: boot stops on a black screen | Declared all three interfaces |
| 10 | Screen density set twice (320, then 160): everything half size | Density 320 |
| 11 | Setup asks to replace your recovery | Option hidden |

## Known limitations

- **Only userdebug builds.** Qualcomm's shared policy for older chips (`device/qcom/sepolicy-legacy`)
  only passes Android 11's SELinux checks with those checks disabled, which Android allows for
  userdebug builds only. A `user` build fails with ~120,000 neverallow errors. Official
  LineageOS builds are userdebug too; root over adb is off until you enable it in Developer options.
- **Signed with the public test keys.** LineageOS Trust warns about it. Builds signed with your
  own keys are possible (`sign_target_files_apks`), but need a factory reset when switching.
- **Power menu covers the screen in black.** That's Android 11's full-screen power menu, not a bug.
- **Old kernel.** 3.4 gets no upstream security fixes anymore; keep SELinux enforcing.

## When the build fails

The log is `./los18/build.log`. Search for `FAILED:` and `error:` and look at the lines around
the first one. Out of memory (the build gets killed, or the PC freezes): use `-e JOBS=4` or lower.

## Credits

- Device and vendor trees: [S3NEO](https://github.com/S3NEO)
- Kernel, common trees, hardware: [LineageOS](https://github.com/LineageOS)
- Common blobs: [TheMuppets](https://github.com/TheMuppets)