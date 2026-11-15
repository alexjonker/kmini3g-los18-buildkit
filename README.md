# LineageOS 18.1 (Android 11) build kit for the Galaxy S5 mini (SM-G800H / kmini3g)

Sources: device + vendor trees from github.com/S3NEO (lineage-18.1), common tree, kernel
and hardware from github.com/LineageOS (lineage-18.1), common blobs from TheMuppets.

## Steps
    # 1. build the container image (once)
    docker build -t los18-builder .

    # 2. make folders for the source and the cache
    mkdir -p ./los18 ./los18-ccache

    # 3. sync + build (rerun the same command to continue after an error)
    docker run --rm -it -v ./los18:/src -v ./los18-ccache:/ccache los18-builder

    # after fixing something, rebuild without syncing again:
    docker run --rm -it -e SKIP_SYNC=1 -v ./los18:/src -v ./los18-ccache:/ccache los18-builder

    # open a shell in the build environment (to edit files / debug):
    docker run --rm -it -v ./los18:/src -v ./los18-ccache:/ccache los18-builder bash

Low on RAM? Add `-e JOBS=2` to use fewer parallel jobs.

## Result
    ./los18/out/target/product/kmini3g/lineage-18.1-<date>-UNOFFICIAL-kmini3g.zip

Flash in TWRP like the current ROM (full wipe, since you come from 16.0).
Keep your current 16.0 zip and a TWRP backup to go back.

## When it fails
The error is near the end of ./los18/build.log. Search for "FAILED:" and "error:"
and send the ~40 lines around it.
