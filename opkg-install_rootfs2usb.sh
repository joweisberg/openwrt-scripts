#!/bin/sh
#
# Create and moving Rootfs & Swap on USB storage (create partitions, format, copy, mount)
#

FILE_PATH=$(readlink -f $(dirname $0))  #/root
FILE_NAME=$(basename $0)                #opkg-install.sh
FILE_NAME=${FILE_NAME%.*}               #opkg-install
FILE_DATE=$(date +'%Y%m%d-%H%M%S')
FILE_LOG="/var/log/$FILE_NAME.log"

###############################################################################
### Functions
###############################################################################

function fCmd() {
  local cmd=$@
  $cmd > /dev/null
  if [ $? -ne 0 ]; then
    echo "* "
    echo "* $cmd" | xargs
    echo -n "* Do you want to retry? [Y/n] "
    read answer
    [ -n "$(echo $answer | grep -i '^y')" ] || [ -z "$answer" ] && fCmd $cmd
  fi
}

function fInstallUsbPackages() {
  if [ -z "$(opkg list-installed | grep 'block-mount')" ]; then
    echo "* Package USB 3.0 disk management"
    fCmd opkg install kmod-usb-core kmod-usb2 kmod-usb3 kmod-usb-storage kmod-usb-storage-uas
    echo "* Package ext4/FAT"
    fCmd opkg install kmod-fs-ext4 kmod-fs-vfat
    echo "* Package mounted partitions"
    fCmd opkg install block-mount
    
    echo "* Package exFAT/ntfs"
#    echo "* Do not install packages WPA3, SQM QoS, Acme, uHTTPd, IKEv2/IPsec with strongSwan, Collectd/Stats, Adblock, Watchcat, mSMTP!"
    fCmd opkg install kmod-fs-exfat libblkid ntfs-3g
    echo "* Package hd-idle"
    fCmd opkg install luci-app-hd-idle
#    if [ $WWAN -eq 1 ]; then
#      echo "* Package USB Huawei Modem 4G/LTE with NCM protocol"
#      opkg install kmod-usb-net-rndis usb-modeswitch
#      opkg install comgt-ncm kmod-usb-net-huawei-cdc-ncm luci-proto-ncm usb-modeswitch
#    fi
#    if [ $WPA3 -eq 1 ]; then
#      echo "* Package WPA2/WPA3 Personal (PSK/SAE) mixed mode"
#      opkg remove --autoremove wpad-basic > /dev/null 2>&1
#      opkg install wpad-openssl
#    fi
    echo "* Package SFTP fileserver"
    fCmd opkg install openssh-sftp-server
#    opkg install luci-app-samba4
#    opkg install luci-app-ddns
#    opkg install ipset
#    opkg install kmod-ipt-nathelper-rtsp kmod-ipt-raw
#    if [ $SQM -eq 1 ]; then
#      echo "* Package SQM QoS (aka Smart Queue Management)"
#      opkg install luci-app-sqm
#    fi
#    if [ $STATS -eq 1 ]; then
#      echo "* Package Satistics with collectd"
#      opkg install luci-app-statistics collectd-mod-rrdtool collectd-mod-processes collectd-mod-sensors
#    fi
#    opkg install luci-ssl-openssl curl ca-bundle
#    opkg install luci-app-acme
#    opkg install luci-app-uhttpd
#    opkg install strongswan-full
#    opkg install luci-app-adblock
#    opkg install luci-app-watchcat
#    opkg install msmtp
    echo "* Package wget"
    fCmd opkg install wget
  fi
}

function fMountPartitions() {
  local USBDEV="$1" DEVSWAP="${USBDEV}1" DEVROOT="${USBDEV}2" DEVDATA="${USBDEV}3"

  echo "* UCI config fstab"
  uci -q del fstab.@swap[-1]
  uci add fstab swap
  uci set fstab.@swap[-1]=swap
  uci set fstab.@swap[-1].enabled='1'
  uci set fstab.@swap[-1].device="$DEVSWAP"

  # fstab.@mount[1].target='/overlay'
  if [ -n "$(uci show | grep 'fstab.*/overlay')" ]; then
    I=$(echo "$(uci show | grep 'fstab.*/overlay')" | awk -F'[][]' '{print $2}')
    uci -q del fstab.@mount[$I]
  fi
  eval $(block info "$DEVROOT" | grep -o -e "UUID=\S*")
  uci add fstab mount
  uci set fstab.@mount[-1]=mount
  uci set fstab.@mount[-1].enabled='1'
  #uci set fstab.@mount[-1].device="$DEVROOT"
  uci set fstab.@mount[-1].uuid="$UUID"
  uci set fstab.@mount[-1].target='/overlay'
  uci set fstab.@mount[-1].options='rw,sync,noatime'
  uci set fstab.@mount[-1].enabled_fsck='1'

  # fstab.@mount[2].target='/mnt/data'
  if [ -n "$(uci show | grep -E 'fstab.*/mnt/data')" ]; then
    I=$(echo "$(uci show | grep -E 'fstab.*/mnt/data')" | awk -F'[][]' '{print $2}')
    uci -q del fstab.@mount[$I]
  fi
  eval $(block info "$DEVDATA" | grep -o -e "UUID=\S*")
  uci add fstab mount
  uci set fstab.@mount[-1]=mount
  uci set fstab.@mount[-1].enabled='1'
  #uci set fstab.@mount[-1].device="$DEVDATA"
  uci set fstab.@mount[-1].uuid="$UUID"
  uci set fstab.@mount[-1].target="/mnt/data"
  uci set fstab.@mount[-1].options='rw,noatime'
  
  uci commit fstab


  echo "* Enable all mounted partitions"
  for L in $(uci show fstab); do
    # fstab.@swap[0].enabled='0'
    # fstab.@mount[1].enabled='0'
    I=$(echo "$L" | awk -F'[][]' '{print $2}')
    if [ $(echo "$L" | grep 'swap' | grep 'enable') ]; then
      uci set fstab.@swap[$I].enabled='1'
    elif [ $(echo "$L" | grep 'mount' | grep 'enable') ]; then
      uci set fstab.@mount[$I].enabled='1'
    fi
  done
  uci commit fstab
  echo "* Please check mounted partitions http://$HOSTNAME/cgi-bin/luci/admin/system/mounts"
}

###############################################################################
### Environment Variables
###############################################################################

# Do not interprate sapce in variable
SAVEIFS=$IFS
IFS=$'\n'

# Source under this script directory
cd $(readlink -f $(dirname $0))
source ./.env
LOCAL_DOMAIN="${DOMAIN%%.*}"
NETADDR=${IPADDR%.*}

# Create and moving Rootfs & Swap on new USB storage
USBWIPE=0
USBBUILT=0


###############################################################################
### Script
###############################################################################

echo -n "* Create and moving Rootfs & Swap on new USB storage? [y/N] "
read answer
if [ -n "$(echo $answer | grep -i '^y')" ]; then
  echo -n "* Please unplug USB storage <enter to continue>..."
  read answer

  if [ -z "$(opkg list-installed | grep lsblk)" ]; then
    echo "* Checking for updates, please wait..."
    fCmd opkg update
    
    fInstallUsbPackages
    echo "* Package disk utilities"
    fCmd opkg install usbutils e2fsprogs dosfstools wipefs fdisk lsblk
  fi

  echo -n "* Please plug back in USB storage <enter to continue>..."
  read answer

  echo "* "
  echo "* List of available USB devices: "
  echo "* "
  fdisk -l /dev/sd[a-d] | grep -e "^Disk" -e "^Device" -e "^\/" | grep -v "identifier"
  echo "* "
  lsblk -f /dev/sd[a-d]
  echo "* "
  
  if [ -z "$USBDEV" ]; then
    USBDEV="/dev/sda"
  fi
  echo -n "* Enter USB device? <$USBDEV> "
  read answer
  if [ -n "$answer" ]; then
    USBDEV=$answer
  fi
  DEVSWAP="${USBDEV}1"
  DEVROOT="${USBDEV}2"
  DEVDATA="${USBDEV}3"




  echo -n "* Built-in USB device for $USBDEV? [Y/n] "
  read answer
  if [ -n "$(echo $answer | grep -i '^y')" ] || [ -z "$answer" ]; then

    echo "* Wiping all signatures for $USBDEV"
    wipefs --all --force $USBDEV > /dev/null
    sleep 2
    echo "* "
    echo -n "* Please unplug and plug back in $USBDEV <enter to continue>..."
    read answer

    (
    echo o # Create a new empty DOS partition table
    echo w # Write changes
    ) | fdisk $USBDEV > /dev/null
    sleep 2
  
    SIZE=$(($(free | grep Mem | awk '{print $2}') / 1024))
    echo "* Info: Double RAM for machines with 512MB of RAM or less than, and same with more."
    echo "* Current RAM: ${SIZE}MB"
    if [ $SIZE -lt 499 ]; then
      SIZE=$((SIZE * 2))
    else
      SIZE=512
    fi
    echo -n "* Enter swap partition size? <${SIZE}MB> "
    read answer
    if [ -n "$answer" ]; then
      SIZE=$answer
    fi
    FSRAM=$SIZE
    (
    echo o # Create a new empty DOS partition table
    echo n # Add a new partition
    echo p # Primary partition
    echo   # Partition number
    echo   # First sector (Accept default: 1)
    echo "+${SIZE}M"  # Last sector (Accept default: varies)
    echo w # Write changes
    ) | fdisk $USBDEV > /dev/null
    sleep 2

    SIZE=4
    echo -n "* Enter root partition size? <${SIZE}GB> "
    read answer
    if [ -n "$answer" ]; then
      SIZE=$answer
    fi
    FSROOT=$SIZE
    SIZE=$((SIZE * 1024))
    (
    echo n # Add a new partition
    echo p # Primary partition
    echo   # Partition number
    echo   # First sector (Accept default: 1)
    echo "+${SIZE}M"  # Last sector (Accept default: varies)
    echo w # Write changes
    ) | fdisk $USBDEV > /dev/null
    sleep 2

    FSDATA=$(($(fdisk -l $USBDEV | grep "^Disk $USBDEV" | cut -d' ' -f3 | cut -d'.' -f1) - $FSROOT))
    echo "* Create data partition of <${FSDATA}GB>"
    (
    echo n # Add a new partition
    echo p # Primary partition
    echo   # Partition number
    echo   # First sector (Accept default: 1)
    echo   # Last sector (Accept default: varies)
    echo w # Write changes
    ) | fdisk $USBDEV > /dev/null
    sleep 2

    echo "* "
    echo "* Partitions detail for $USBDEV:"
    fdisk -l $USBDEV | grep  -e "^Disk" -e "^Device" -e "^\/" | grep -v "identifier"
    echo "* "
    echo -n "* Please unplug and plug back in $USBDEV <enter to continue>..."
    read answer

    echo "* "
    echo "* Format partitions with swap/ext4/fat32"
    mkswap $DEVSWAP > /dev/null 2>&1
    mkfs.ext4 -F -L "rootfs" $DEVROOT > /dev/null 2>&1
    mkfs.fat -F 32 -n "data" $DEVDATA > /dev/null 2>&1
    
    echo "* "
    echo "* Partitions detail for $USBDEV:"
    lsblk -f $USBDEV
    echo "* "

    echo "* Remove Package disk utilities"
    opkg remove --autoremove usbutils e2fsprogs dosfstools wipefs fdisk lsblk > /dev/null 2>&1

    echo "* "
    echo "* Add swap of ${FSRAM}MB on $DEVSWAP"
    echo "* Move overlayfs:/overlay to ${FSROOT}GB on $DEVROOT"
    echo "* Add free storage of ${FSDATA}GB on $DEVDATA"
    echo "* "
    
    # Rollback overlay partition
    # /dev/ubi0_1: UUID="e14f77d3-5564-4d4d-b708-842837dc9905" VERSION="w4r0" MOUNT="/overlay" TYPE="ubifs"
    #mount -t ubifs /dev/ubi0_1 /overlay
    
    # Mount swap partition
    swapon $DEVSWAP
    
    # Mount data partition
    mkdir -p /mnt/data
    mount -t vfat $DEVDATA /mnt/data > /dev/null

    fMountPartitions $USBDEV

    # Copy rootfs partition
    echo "* Copy /overlay on $DEVROOT partition..."
    mkdir -p /mnt/rootfs
    mount -t ext4 $DEVROOT /mnt/rootfs > /dev/null
    # Remove existing data
    rm -Rf /mnt/rootfs/*
    #tar -C /overlay -cvf - . | tar -C /mnt/rootfs -xf -
    cp -a -f /overlay/. /mnt/rootfs
    umount /mnt/rootfs
    block umount > /dev/null
    rm -Rf /mnt/rootfs
    
    echo "* "
    echo "* "
    echo "* "
    echo -n "* Reboot to complete \"Rootfs & Swap on USB Storage\" <enter to continue>..."
    read answer
    reboot
    
    # Interrupted system call should be restarted
    exit 85
  fi
else




  echo -n "* Rebuild Rootfs on existing USB storage? [y/N] "
  read answer
  if [ -n "$(echo $answer | grep -i '^y')" ]; then
    echo -n "* Please unplug USB storage <enter to continue>..."
    read answer
    
    if [ -z "$(opkg list-installed | grep lsblk)" ]; then
      echo "* Checking for updates, please wait..."
      fCmd opkg update

      fInstallUsbPackages
      echo "* Package disk utilities"
      fCmd opkg install usbutils e2fsprogs dosfstools wipefs fdisk lsblk
    fi

    echo -n "* Please plug back in USB storage <enter to continue>..."
    read answer

    echo "* "
    echo "* List of available USB devices: "
    echo "* "
    lsblk -f /dev/sd[a-d]
    echo "* "
    
    DEVSWAP=$(block info | grep 'swap' | cut -d':' -f1)
    echo -n "* Enter swap device? <$DEVSWAP> "
    read answer
    if [ -n "$answer" ]; then
      DEVSWAP=$answer
    fi
    DEVROOT=$(block info | grep 'rootfs' | cut -d':' -f1)
    echo -n "* Enter rootfs device? <$DEVROOT> "
    read answer
    if [ -n "$answer" ]; then
      DEVROOT=$answer
    fi
    # Remove last character
    USBDEV=${DEVROOT%?}

    echo "* "
    echo "* Format partitions with swap/ext4"
    mkswap $DEVSWAP > /dev/null 2>&1
    mkfs.ext4 -F -L "rootfs" $DEVROOT > /dev/null 2>&1
    
    echo "* Remove Package disk utilities"
    opkg remove --autoremove usbutils e2fsprogs dosfstools wipefs fdisk lsblk > /dev/null 2>&1

    fMountPartitions $USBDEV

    # Copy rootfs partition
    echo "* Copy /overlay on $DEVROOT partition..."
    mkdir -p /mnt/rootfs
    mount -t ext4 $DEVROOT /mnt/rootfs > /dev/null
    # Remove existing data
    rm -Rf /mnt/rootfs/*
    #tar -C /overlay -cvf - . | tar -C /mnt/rootfs -xf -
    cp -a -f /overlay/. /mnt/rootfs
    umount /mnt/rootfs
    block umount > /dev/null
    rm -Rf /mnt/rootfs

    echo "* "
    echo "* "
    echo "* "
    echo -n "* Reboot to complete \"Rootfs & Swap on USB Storage\" <enter to continue>..."
    read answer
    reboot
    
    # Interrupted system call should be restarted
    exit 85
  fi
fi

# Rollback Internal Field Separator
IFS=$SAVEIFS

exit 0