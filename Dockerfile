# Build environment for LineageOS 18.1 (Ubuntu 20.04, as used by LineageOS for 18.1)
FROM ubuntu:20.04
ENV DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8 LANG=C.UTF-8
RUN apt-get update && apt-get install -y \
    bc bison build-essential ccache curl flex g++-multilib gcc-multilib git git-lfs gnupg gperf \
    imagemagick lib32ncurses5-dev lib32readline-dev lib32z1-dev liblz4-tool libncurses5 \
    libncurses5-dev libsdl1.2-dev libssl-dev libxml2 libxml2-utils lzop pngcrush rsync \
    schedtool squashfs-tools xsltproc zip unzip zlib1g-dev python3 python-is-python3 \
    openssh-client ca-certificates nano && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o /usr/local/bin/repo \
    && chmod a+x /usr/local/bin/repo
RUN git config --global user.name "kmini3g builder" && git config --global user.email "builder@localhost" \
    && git config --global color.ui false && git lfs install
ENV USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache CCACHE_DIR=/ccache
WORKDIR /src
COPY kmini3g.xml build.sh /kit/
CMD ["/bin/bash", "/kit/build.sh"]
