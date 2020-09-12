FROM ubuntu:groovy

# The repository should be mounted at /app.
WORKDIR /app

RUN set -xe \
    && apt-get update \
    && apt-get install -y \
        binutils \
        dosfstools \
        jq \
        p7zip-full \
        parted \
        sudo \
        u-boot-tools \
        wget \
        udev \
        xz-utils \
 && rm -rf /var/lib/apt/lists/*

COPY build-image.sh /app/build-image.sh
COPY init.preinit /app/init.preinit
COPY init.resizefs /app/init.resizefs

CMD /app/build-image.sh $TARGET
