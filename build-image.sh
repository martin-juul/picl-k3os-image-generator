#!/bin/bash

set -e pipefail

# Set this to default to a KNOWN GOOD pi firmware (e.g. 1.20200811 or 1.20200819); this is used if RASPBERRY_PI_FIRMWARE env variable is not specified
DEFAULT_GOOD_PI_VERSION="1.20200811"

# Set this to default to a KNOWN GOOD k3os (e.g. v0.11.0); this is used if K3OS_VERSION env variable is not specified
DEFAULT_GOOD_K3OS_VERSION="v0.11.0"

## Check if we have any configs
if [ -z "$(ls config/*.yaml)" ]; then
	echo "There are no .yaml files in config/, please create them." >&2
	echo "Their name must be the MAC address of eth0, e.g.:" >&2
	echo "  config/dc:a6:32:aa:bb:cc.yaml" >&2
	exit 1
fi

## Check if we have the necessary tools
assert_tool() {
	if [ "x$(which $1)" = "x" ]; then
		echo "Missing required dependency: $1" >&2
		exit 1
	fi
}

get_pifirmware() {
    #  Uses RASPBERRY_PI_FIRMWARE env variable to allow the user to control which pi firmware version to use.
    # - 1. unset, in which case it is initialized to a known good version (DEFAULT_GOOD_PI_VERSION)
    # - 2. set to "latest" in which case it pulls the latest firmware from git repo.
    # - 3. set by the user to desired version

    if [ -z "${RASPBERRY_PI_FIRMWARE}" ]; then
        echo "RASPBERRY_PI_FIRMWARE env variable was not set - defaulting to known good firmware [${DEFAULT_GOOD_PI_VERSION}]"
        dl_dep raspberrypi-firmware.tar.gz https://github.com/raspberrypi/firmware/archive/"${DEFAULT_GOOD_PI_VERSION}".tar.gz
    elif [ "${RASPBERRY_PI_FIRMWARE}" = "latest" ]; then
        echo "RASPBERRY_PI_FIRMWARE env variable set to 'latest' - using latest pi firmware release"
        dl_dep raspberrypi-firmware.tar.gz "$(wget -qO - https://api.github.com/repos/raspberrypi/firmware/tags | jq -r '.[0].tarball_url')"
    else
        # set to requested version, but first check if it is a valid version
        for i in $(wget -qO - https://api.github.com/repos/raspberrypi/firmware/tags | jq  --arg RASPBERRY_PI_FIRMWARE "${RASPBERRY_PI_FIRMWARE}" -r '.[].tarball_url | contains($RASPBERRY_PI_FIRMWARE)')
        do
            if [ "$i" = "true" ]; then FOUND=true; break; fi
        done
        if [ "${FOUND}" = true ]; then
            echo "RASPBERRY_PI_FIRMWARE env variable set to [${RASPBERRY_PI_FIRMWARE}] - will use this firmware."
            dl_dep raspberrypi-firmware.tar.gz https://github.com/raspberrypi/firmware/archive/"${RASPBERRY_PI_FIRMWARE}".tar.gz
        else
            echo "Requested raspberry pi firmware [${RASPBERRY_PI_FIRMWARE}] is not valid (does not exist in pi firmware repo)! Exiting Build!"
            exit 1;
        fi
    fi
}

assert_tool wget
assert_tool mktemp
assert_tool truncate
assert_tool parted
assert_tool partprobe
assert_tool losetup
assert_tool mkfs.fat
assert_tool mkfs.ext4
assert_tool tune2fs
assert_tool e2label
assert_tool mktemp
assert_tool ar
assert_tool blkid
assert_tool realpath
assert_tool 7z
assert_tool dd
assert_tool jq

echo "Building an image for the Raspberry Pi model 3B+/4."

## Download dependencies
echo "== Checking or downloading dependencies... =="

function dl_dep() {
	if [ ! -f "deps/$1" ]; then
		wget -O deps/$1 $2
	fi
}

mkdir -p deps

get_pifirmware

if [ -z "${K3OS_VERSION}" ]; then
    echo "K3OS_VERSION env variable was not set - defaulting to known version [${DEFAULT_GOOD_K3OS_VERSION}]"
    dl_dep k3os-rootfs-arm64.tar.gz https://github.com/rancher/k3os/releases/download/${DEFAULT_GOOD_K3OS_VERSION}/k3os-rootfs-arm64.tar.gz
else
    echo "K3OS_VERSION env variable set to ${K3OS_VERSION}"
    dl_dep k3os-rootfs-arm64.tar.gz https://github.com/rancher/k3os/releases/download/${K3OS_VERSION}/k3os-rootfs-arm64.tar.gz
fi

# To find the URL for these packages:
# - Go to https://launchpad.net/ubuntu/bionic/arm64/<package name>/
# - Under 'Publishing history', click the version number in the top row
# - Under 'Downloadable files', use the URL of the .deb file
# - Change http to https

dl_dep libc6-arm64.deb https://launchpadlibrarian.net/365857916/libc6_2.27-3ubuntu1_arm64.deb
dl_dep busybox-arm64.deb https://launchpadlibrarian.net/414117084/busybox_1.27.2-2ubuntu3.2_arm64.deb
dl_dep libcom-err2-arm64.deb https://launchpadlibrarian.net/444344115/libcom-err2_1.44.1-1ubuntu1.2_arm64.deb
dl_dep libblkid1-arm64.deb https://launchpadlibrarian.net/438655401/libblkid1_2.31.1-0.4ubuntu3.4_arm64.deb
dl_dep libuuid1-arm64.deb https://launchpadlibrarian.net/438655406/libuuid1_2.31.1-0.4ubuntu3.4_arm64.deb
dl_dep libext2fs2-arm64.deb https://launchpadlibrarian.net/444344116/libext2fs2_1.44.1-1ubuntu1.2_arm64.deb
dl_dep e2fsprogs-arm64.deb https://launchpadlibrarian.net/444344112/e2fsprogs_1.44.1-1ubuntu1.2_arm64.deb
dl_dep parted-arm64.deb https://launchpadlibrarian.net/415806982/parted_3.2-20ubuntu0.2_arm64.deb
dl_dep libparted2-arm64.deb https://launchpadlibrarian.net/415806981/libparted2_3.2-20ubuntu0.2_arm64.deb
dl_dep libreadline7-arm64.deb https://launchpadlibrarian.net/354246199/libreadline7_7.0-3_arm64.deb
dl_dep libtinfo5-arm64.deb https://launchpadlibrarian.net/371711519/libtinfo5_6.1-1ubuntu1.18.04_arm64.deb
dl_dep libdevmapper1-arm64.deb https://launchpadlibrarian.net/431292125/libdevmapper1.02.1_1.02.145-4.1ubuntu3.18.04.1_arm64.deb
dl_dep libselinux1-arm64.deb https://launchpadlibrarian.net/359065467/libselinux1_2.7-2build2_arm64.deb
dl_dep libudev1-arm64.deb https://launchpadlibrarian.net/444834685/libudev1_237-3ubuntu10.31_arm64.deb
dl_dep libpcre3-arm64.deb https://launchpadlibrarian.net/355683636/libpcre3_8.39-9_arm64.deb
dl_dep util-linux-arm64.deb https://launchpadlibrarian.net/438655410/util-linux_2.31.1-0.4ubuntu3.4_arm64.deb
dl_dep rpi-firmware-nonfree-master.zip https://github.com/RPi-Distro/firmware-nonfree/archive/master.zip

## Make the image (capacity in MB, not MiB)
echo "== Making image and filesystems... =="
IMAGE=$(mktemp picl-k3os-build.iso.XXXXXX)

# Create two partitions: boot and root.
BOOT_CAPACITY=60
# Initial root size. The partition will be resized to the SD card's maximum on first boot.
ROOT_CAPACITY=1000
IMAGE_SIZE=$(($BOOT_CAPACITY + $ROOT_CAPACITY))

truncate -s ${IMAGE_SIZE}M $IMAGE
parted -s $IMAGE mklabel msdos
parted -s $IMAGE unit MB mkpart primary fat32 1 $BOOT_CAPACITY
parted -s $IMAGE unit MB mkpart primary $(($BOOT_CAPACITY+1)) $IMAGE_SIZE
parted -s $IMAGE set 1 boot on

LOOPDEV=$(losetup --find --show --partscan ${IMAGE})

# drop the first line, as this is our LOOPDEV itself, but we only want the child partitions
PARTITIONS=$(lsblk --raw --output "MAJ:MIN" --noheadings ${LOOPDEV} | tail -n +2)
COUNTER=1
for i in $PARTITIONS; do
    MAJ=$(echo $i | cut -d: -f1)
    MIN=$(echo $i | cut -d: -f2)
    if [ ! -e "${LOOPDEV}p${COUNTER}" ]; then mknod ${LOOPDEV}p${COUNTER} b $MAJ $MIN; fi
    COUNTER=$((COUNTER + 1))
done

sudo partprobe -s $LOOPDEV
sleep 1

LOOPDEV_BOOT=${LOOPDEV}p1
LOOPDEV_ROOT=${LOOPDEV}p2
sudo mkfs.fat $LOOPDEV_BOOT

sudo mkfs.ext4 -F $LOOPDEV_ROOT
sudo tune2fs -i 1m $LOOPDEV_ROOT
sudo e2label $LOOPDEV_ROOT "root"

## Initialize root
echo "== Initializing root... =="
mkdir root
sudo mount $LOOPDEV_ROOT root
sudo mkdir root/bin root/boot root/dev root/etc root/home root/lib root/media
sudo mkdir root/mnt root/opt root/proc root/root root/sbin root/sys
sudo mkdir root/tmp root/usr root/var
sudo chmod 0755 root/*
sudo chmod 0700 root/root
sudo chmod 1777 root/tmp
sudo ln -s /proc/mounts root/etc/mtab
sudo mknod -m 0666 root/dev/null c 1 3

## Initialize boot
echo "== Initializing boot... =="

PITEMP="$(mktemp -d)"
sudo tar -xf deps/raspberrypi-firmware.tar.gz --strip 1 -C $PITEMP

mkdir boot
sudo mount $LOOPDEV_BOOT boot
sudo cp -R $PITEMP/boot/* boot
sudo cp -R $PITEMP/modules root/lib

cat <<EOF | sudo tee boot/config.txt >/dev/null
dtoverlay=vc4-fkms-v3d
gpu_mem=16
arm_64bit=1

boot_delay=1
disable_splash=1

dtparam=sd_overclock=99
dtparam=audio=off

over_voltage=2

arm_freq=1400
core_freq=450
sdram_freq=520
sdram_schmoo=0x00000000

temp_limit=80
initial_turbo=0
EOF

PARTUUID=$(sudo blkid -o export $LOOPDEV_ROOT | grep PARTUUID)
echo "dwc_otg.lpm_enable=0 root=$PARTUUID rootfstype=ext4 elevator=deadline cgroup_memory=1 cgroup_enable=memory rootwait init=/sbin/init.resizefs ro" | sudo tee boot/cmdline.txt >/dev/null
sudo rm -rf $PITEMP

## Install k3os, busybox and resize dependencies
echo "== Unpacking rootfs =="
sudo tar -xf deps/k3os-rootfs-arm64.tar.gz --strip 1 -C root
# config.yaml will be created by init.resizefs based on MAC of eth0
sudo cp -R config root/k3os/system
for filename in root/k3os/system/config/*.*; do [ "$filename" != "${filename,,}" ] && sudo mv "$filename" "${filename,,}" ; done
K3OS_VERSION=$(ls --indicator-style=none root/k3os/system/k3os | grep -v current | head -n1)

## Install busybox
unpack_deb() {
	ar x deps/$1
	sudo tar -xf data.tar.[gx]z -C $2
	rm -f data.tar.gz data.tar.xz control.tar.gz control.tar.xz debian-binary
}

unpack_deb "libc6-arm64.deb" "root"
unpack_deb "busybox-arm64.deb" "root"

for i in \
	ar \
	awk \
	basename \
	cat \
	chmod \
	dirname \
	dmesg \
	echo \
	fdisk \
	find \
	grep \
	ln \
	ls \
	lsmod \
	mkdir \
	mknod \
	modprobe \
	mount \
	mv \
	poweroff \
	readlink \
	reboot \
	rm \
	rmdir \
	sed \
	sh \
	sleep \
	sync \
	tail \
	tar \
	touch \
	umount \
	uname \
	wget \
; do
	sudo ln -s busybox root/bin/$i
done

BRCMTMP=$(mktemp -d)
7z e -y deps/rpi-firmware-nonfree-master.zip -o"$BRCMTMP" "firmware-nonfree-master/brcm/*" > /dev/null
sudo mkdir -p root/lib/firmware/brcm/
sudo cp "$BRCMTMP"/brcmfmac43455* root/lib/firmware/brcm/
sudo cp "$BRCMTMP"/brcmfmac43430* root/lib/firmware/brcm/
rm -rf "$BRCMTMP"

## Add libraries and binaries needed to resize root FS & fsck every boot
unpack_deb "libcom-err2-arm64.deb" "root"
unpack_deb "libblkid1-arm64.deb" "root"
unpack_deb "libuuid1-arm64.deb" "root"
unpack_deb "libext2fs2-arm64.deb" "root"
unpack_deb "e2fsprogs-arm64.deb" "root"
unpack_deb "util-linux-arm64.deb" "root"

## Add tarball for the libraries and binaries needed only to resize root FS
# TODO: replace parted by fdisk/sfdisk if simpler?
mkdir root-resize
unpack_deb "parted-arm64.deb" "root-resize"
unpack_deb "libparted2-arm64.deb" "root-resize"
unpack_deb "libreadline7-arm64.deb" "root-resize"
unpack_deb "libtinfo5-arm64.deb" "root-resize"
unpack_deb "libdevmapper1-arm64.deb" "root-resize"
unpack_deb "libselinux1-arm64.deb" "root-resize"
unpack_deb "libudev1-arm64.deb" "root-resize"
unpack_deb "libpcre3-arm64.deb" "root-resize"

sudo tar -cJf root/root-resize.tar.xz "root-resize"
sudo rm -rf root-resize

## Write a resizing init and a pre-init
sudo install -m 0755 -o root -g root init.preinit init.resizefs root/sbin

## Clean up
sync
sudo umount boot
rmdir boot
sudo umount root
rmdir root
sync
sleep 1
sudo losetup -d $LOOPDEV

IMAGE_FINAL=out/picl-k3os-${K3OS_VERSION}-rpi3bplus.img
mv $IMAGE $IMAGE_FINAL
echo ""
echo "== $IMAGE_FINAL created. =="
