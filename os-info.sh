#!/bin/sh
#
# Change welcome message
#

###############################################################################
### Functions

function fOpkgUpgradable() {
  local PRINT_MSG=${1:-0}
  
  local CHK_DT=/tmp/opkgCheckDate.txt
  local CHK_MSG=/tmp/opkgCheckMsg.txt
  local CHK_PKG=/tmp/opkgUpgradable.txt
  # Check daily
  if [ ! -f $CHK_DT ] || [ $(cat $CHK_DT) -ne $(date +'%Y%m%d') ]; then

    wget -q --spider --timeout=5 http://www.google.com 2> /dev/null
    if [ $? -eq 0 ]; then  # if Google website is available we update
      opkg update > /dev/null
      opkgInstalled="$(opkg list-installed 2> /dev/null | wc -l)"
      opkgUpgradable="$(opkg list-upgradable 2> /dev/null | wc -l)"

      if [ $opkgUpgradable -gt 0 ]; then
        opkgDowngradeList=""
        opkgDowngradeNb=0
        if [ -f ./opkg-downgrade.conf ]; then
          opkgDowngradeList=$(cat ./opkg-downgrade.conf | grep -v '^#' | cut -d' ' -f1 | xargs | sed -e 's/ /|/g')
          opkgDowngradeNb=$(cat ./opkg-downgrade.conf | grep -v '^#' | cut -d' ' -f1 | wc -l)
        fi
        opkgUpgradable=$(opkg list-upgradable 2> /dev/null | wc -l)
        opkgUpgradable=$(($opkgUpgradable - $opkgDowngradeNb))
      fi

      rm -f $CHK_MSG
      echo "$opkgInstalled packages are installed." >> $CHK_MSG
      echo "$opkgUpgradable packages can be upgraded." >> $CHK_MSG
      echo $opkgUpgradable > $CHK_PKG
      
      memLimit=32000 # in bytes
      if [ "$(grep MemFree /proc/meminfo | awk '{print $2}')" -lt $memLimit ]; then
        rm -f $CHK_DT

        for opkg_package_lists in /var/opkg-lists/*
        do
          if [ -f "$opkg_package_lists" ]; then #prevent error if opkg update fails
            rm -Rf /var/opkg-lists/*
            opkg update > /dev/null
            opkgUpgradable="$(opkg list-upgradable 2> /dev/null | wc -l)"
            opkgUpgradable=$(($opkgUpgradable - $opkgDowngradeNb))
            
            echo "Warning: Memory limit $memLimit bytes. Removed downloaded package lists to save memory."
            echo #only remove when free RAM is less than uci set memory limit (default 32 MiB)
          fi
        done
      fi

#      if [ $opkgUpgradable -gt 0 ]; then
#        echo "Upgrade all installed packages:" | tee -a $CHK_MSG
#        echo "* ~/opkg-upgrade.sh" | tee -a $CHK_MSG
#        echo "" | tee -a $CHK_MSG
#      fi

      # Save current date, check daily
      date +'%Y%m%d' > $CHK_DT

    fi
#  else
#    cat $CHK_MSG
  fi
  
  if [ $PRINT_MSG -eq 1 ]; then
    cat $CHK_MSG
  else
    cat $CHK_PKG
  fi
}

function fShowStatus() {
  local CURR=$1 MAX=$2
  echo "[$(if [ $CURR -eq $MAX ]; then echo $(echogreen "OK"); else echo $(echoyellow "!!"); fi)]"
}

###############################################################################
### Environment Variables

. ~/opkg-install.env
. ~/.bash_colors
. /etc/os-release
export DISPLAY=:0

###############################################################################
### Script

# Do not interprate space in variable during for loop
SAVEIFS=$IFS
IFS=$(echo -en "\n\b")

echo
# Welcome to Ubuntu 20.04.1 LTS (GNU/Linux 5.4.0-52-generic x86_64)
printf "Welcome to %s (%s %s %s)\n" "$PRETTY_NAME" "$(uname -o)" "$(uname -r)" "$(uname -m)"

echo
echo "GENERAL SYSTEM INFORMATION"
# media@htpc.home
# OS: Ubuntu 20.04.1 LTS (Focal Fossa)
# Kernel: x86_64 Linux 5.4.0-52-generic
# Uptime: 4d 17h 9m
# Packages: 1303
# Shell: bash 5.0.17
# CPU: Intel(R) Core(TM) i5-4590T @ 4x 3GHz [39.5°C]
# GPU: Xeon E3-1200 v3/4th Gen Core Processor Integrated Graphics (i915)
# Resolution: 1920x1080
# GTK Theme: Adwaita [GTK-3.24.20-0ubuntu1]
# RAM: 3.01G / 15.71G (19%)
# SWAP: 0.00G / 0.00G (0%)
# Processes: 332
# Users account: 51 / 51 [OK]
# Users shell: 2 / 2 [OK]
# Users logged in: 1
# IPsec logged in: 2
# OpenVPN logged in: 3

echo "$(echored " $(id -un)")@$HOSTNAME.$(cat /etc/resolv.conf | grep '^search' | awk '{print $2}')"
echo "$(echored " OS: ")$NAME $VERSION $OPENWRT_BOARD $BUILD_ID"
echo "$(echored " Kernel: ")$(if [ $(uname -i) == "unknown" ]; then echo "x86"; else echo $(uname -i); fi) $(uname -sr)"
echo "$(echored " Uptime: ")$(uptime | awk -F'( |,|:)+' '{d=h=m=0; if ($7=="min") m=$6; else {if ($7~/^day/) {d=$6;h=$8;m=$9} else {h=$6;m=$7}}} {print d+0"d",h+0"h",m+0"m"}')"
echo "$(echored " Packages installed: ")$(opkg list-installed 2> /dev/null | wc -l)"
echo "$(echored " Packages upgradable: ")$(fOpkgUpgradable) $(fShowStatus $(fOpkgUpgradable) 0)"
#echo "$(echored " Shell: ")$(echo "bash $BASH_VERSION" | cut -d'(' -f1)"

if [ -n "$(cat /proc/cpuinfo | grep '^Hardware' | head -n1)" ]; then
  CPU_NAME=$(cat /proc/cpuinfo | grep '^Hardware' | head -n1 | awk -F':' '{print $2}' | awk -F'CPU' '{print $1}' | sed 's/ *$//g' | sed 's/^ *//g')
elif [ -n "$(cat /proc/cpuinfo | grep '^model name' | head -n1)" ]; then
  CPU_NAME=$(cat /proc/cpuinfo | grep '^model name' | head -n1 | awk -F':' '{print $2}' | awk -F'CPU' '{print $1}' | sed 's/ *$//g' | sed 's/^ *//g')
elif [ -n "$(cat /proc/cpuinfo | grep '^Model' | head -n1)" ]; then
  CPU_NAME=$(cat /proc/cpuinfo | grep '^Model' | head -n1 | awk -F':' '{print $2}' | awk -F'CPU' '{print $1}' | sed 's/ *$//g' | sed 's/^ *//g')
elif [ -n "$(cat /proc/cpuinfo | grep '^system type' | head -n1)" ]; then
  CPU_NAME=$(cat /proc/cpuinfo | grep '^system type' | head -n1 | awk -F':' '{print $2}' | awk -F'CPU' '{print $1}' | sed 's/ *$//g' | sed 's/^ *//g')
fi
# Remove the trailing and leading spaces 
#CPU_NAME=$(echo $CPU_NAME | sed 's/ *$//g' | sed 's/^ *//g')
CPU_NCORE=$(cat /proc/cpuinfo | grep '^processor' | wc -l)
#CPU_SPEED=$(lshw -C CPU 2> /dev/null | grep "capacity:" | head -n1 | awk '{print $2}' | cut -d'@' -f1)
CPU_SPEED=$(echo "$(cat /proc/cpuinfo | grep '^BogoMIPS' | head -n1 | awk -F':' '{print $2}') 1000" | awk '{printf "%.2fGHz", $1/$2}')
if [ $(sensors > /dev/null 2>&1; echo $?) -eq 0 ]; then
  CPU_TEMP=$(sensors armada_thermal-virtual-0 | grep '^temp1' | awk '{print $2}' | awk -vx=0 '{sum+=$1} END {print sum/NR}')
  CPU_TEXT="[$CPU_TEMP°C]"
fi
echo "$(echored " CPU: ")$CPU_NAME @ ${CPU_NCORE}x $CPU_SPEED $CPU_TEXT"

echo "$(echored " RAM: ")$(free -m | grep Mem | awk '{printf("%.2fM / %.2fM (%.0f%%)",$3/1024,$2/1024,$2!=0?$3*100/$2:0)}')"
echo "$(echored " SWAP: ")$(free -m | grep Swap | awk '{printf("%.2fM / %.2fM (%.0f%%)",$3/1024,$2/1024,$2!=0?$3*100/$2:0)}')"
echo "$(echored " Processes: ")$(ps | wc -l)"
echo "$(echored " Users account: ")$(cat /etc/passwd | wc -l) / $OS_USER_MAX $(fShowStatus $(cat /etc/passwd | wc -l) $OS_USER_MAX)"
echo "$(echored " Users shell: ")$(cat /etc/passwd | grep "$(cat /etc/shells)" | wc -l) / $OS_SHELL_MAX $(fShowStatus $(cat /etc/passwd | grep "$(cat /etc/shells)" | wc -l) $OS_SHELL_MAX)"
echo "$(echored " Users logged in: ")$(ls /dev/pts/* | grep -v "/dev/pts/ptmx" | wc -l)"
echo "$(echored " IPsec logged in: ")$(ipsec leases | sed 1d | grep online | wc -l)"
OPVPN_UP=$(cat /var/log/openvpn.log 2> /dev/null | grep "$(date +"%a %b %e")" | grep "$(date +"%Y")" | grep 'client/' | grep 'IPv4=' | wc -l)
OPVPN_DN=$(cat /var/log/openvpn.log 2> /dev/null | grep "$(date +"%a %b %e")" | grep "$(date +"%Y")" | grep 'client/' | grep SIGTERM | wc -l)
echo "$(echored " OpenVPN logged in: ")$(expr $OPVPN_UP - $OPVPN_DN)"

echo
echo "DISKS USAGE"
# Disk: /boot/efi [vfat] 7.8M / 504M (2%)
df -hT | grep -E '^/dev|/mnt' | awk '{print $7" ["$2"] "$4" / "$3" ("$6")"}' | sed "s/^/$(echored ' Disk: ')/"

echo
echo "NETWORK INFORMATION"
ETH_DEV="br-lan"
ETH_ADR=$(ip -4 address show $ETH_DEV | grep inet | awk '{print $2}')
ETH_DNS=$(ip route | grep '^default' | grep $ETH_DEV | awk '{print $3}')
if [ -z $ETH_DNS ]; then
  ETH_DNS=$(ip route | grep -v '^default' | grep "$ETH_DEV proto kernel" | awk '{print $9}')
fi
ETH_GTW=$(curl -4s wgetip.com)
echo "$(echored " Local domain: ")$(cat /etc/resolv.conf | grep '^search' | awk '{print $2}')"
echo "$(echored " IPv4 network: ")$ETH_ADR $ETH_DNS [$ETH_DEV]"
echo "$(echored " IPv4 outside: ")$ETH_GTW [$(uci get ddns.myddns_ipv4.lookup_host)]"
echo "$(echored " Devices connected: ")"
# Get all mac address from dhcp leases
interface="br-lan"
# Sort dhcp leases by IP address and get all mac address
cat /tmp/dhcp.leases | sort -t . -k 4n | awk '{print toupper($2)}' | sed "s/^/$interface /g"  > /tmp/mac-lan.list
# for each interface, count wireless devices
rm -f /tmp/mac-wlan.list
wifidevice=0
for interface in $(iwinfo | awk '/ESSID/{print $1}'); do
  wifidevice=$(( $wifidevice + $(iwinfo $interface assoclist | grep dBm | wc -l) ))
  # Add mac address from wlan devices
  iwinfo $interface assoclist | awk '/dBm/{print toupper($1)}' | sed "s/^/$interface /g" >> /tmp/mac-wlan.list
done
# Remove from dhcp leases mac address from wlan devices
for mac in $(cat /tmp/mac-wlan.list | awk '{print $2}'); do
  sed -i "/$mac/d" /tmp/mac-lan.list
done
# Sort mac address as uniq list
#cat /tmp/mac-lan.list | sort -f | uniq -i > /tmp/mac-lan.list.tmp
#mv /tmp/mac-lan.list.tmp /tmp/mac-lan.list

# for lan interface, count devices
interface="br-lan"
echo -e " * $interface: $(cat /tmp/mac-lan.list | wc -l)"
# for each wirless interface, count devices
for interface in $(iwinfo | awk '/ESSID/{print $1}'); do
  type=$(iwinfo $interface info | awk '/Type/{print $5}')
  channel=$(iwinfo $interface info | awk '/Master  Channel/{print $4}')
  essid=$(iwinfo $interface info | awk -F'"' '/ESSID/{print $2}')
  echo -e " * $interface\t[$type]\tChannel: $channel\t($essid): $(iwinfo $interface assoclist | grep dBm | wc -l) "
done

echo
echo "NETWORK DEVICES"
printf ' %-7s %-9s %-17s %-15s %s [%s]\n' "# Int." "[Exp.]" "MAC address" "IP address" "Name" "Vendor"
# Get connected devices on lan and wireless network with expired dhpc leases
for L in $(cat /tmp/mac-lan.list /tmp/mac-wlan.list); do
  interface="$(echo $L | awk '{print $1}')"
  mac="$(echo $L | awk '{print $2}')"
  # Leasetime remaining => [06h 57m]
  leasetime="[$(date -d @$(($(cat /tmp/dhcp.leases | grep -i "$mac" | awk '{print $1}') - $(date +"%s"))) +"%Hh %Mm")]"
  # Find ip in dhpc dynamic leases
  ip=$(cat /tmp/dhcp.leases | grep -i $mac | cut -d' ' -f3)
  # Find ip in dhpc static lease
  if [ -z "$ip" ]; then
    # dhcp.@host[2].mac='DE:0D:17:C0:51:9F'
    dhcpmac=$(uci show dhcp | grep -i ".mac='$mac'" | cut -d'=' -f1)
    # dhcp.@host[2].mac
    # uci get dhcp.@host[2].ip
    ip="$(uci -q get ${dhcpmac%.*}.ip)"
  fi
  if [ -z "$ip" ]; then
    ip="UKWN"
  fi
  host=$(cat /tmp/dhcp.leases | grep -i $mac | cut -d' ' -f4)
  # Find host name in dhpc static lease
  if [ -z "$host" ]; then
    # dhcp.@host[2].mac='DE:0D:17:C0:51:9F'
    dhcpmac=$(uci show dhcp | grep -i ".mac='$mac'" | cut -d'=' -f1)
    # dhcp.@host[2].mac
    # uci get dhcp.@host[2].name
    host="$(uci -q get ${dhcpmac%.*}.name)"
  fi
  if [ -z "$host" ]; then
    host="*"
  fi
  vendor=$(sleep 1 && curl --silent https://api.maclookup.app/v2/macs/$mac | cut -d',' -f4 | cut -d'"' -f4)

  # br-lan [08h 53m] 70:fc:8f:73:b7:90 192.168.10.254 fbx-player [FREEBOX SAS]
  printf ' %-7s %-9s %-17s %-15s %s [%s]\n' "$interface" "$leasetime" "$mac" "$ip" "$host" "$vendor" | sed "s/[!!]/$(echoyellow "!!")/g"
done

if [ $(ipsec leases | sed 1d | grep online | wc -l) -gt 0 ]; then
  echo
  echo "IPSEC CONNECTED USERS"
  #    192.168.10.41   online   'Jonathan'
  #    192.168.10.42   online   'Jonathan'
  #ipsec leases | sed 1d | grep online
  # ikev2-eap[18]: 192.168.10.41 50 minutes ago, 78.192.120.23[ejw.root.sx]...192.168.10.244[Jonathan]
  # ikev2-eap[17]: 192.168.10.42 50 minutes ago, 78.192.120.23[ejw.root.sx]...92.184.105.173[Jonathan]
  i=1
  for l in $(ipsec status | grep ESTABLISHED); do
    user=$(echo $l | awk -F '[][]' '{print $6}')
    pool_ip=$(ipsec leases | sed 1d | grep online | grep $user | sed -n ${i}p | awk '{print $1}')
    # Local lan connection
    if [ $(echo "$user" | grep "\." | wc -l) -gt 0 ]; then
      lan_ip=$user
      lan_host=$(cat /tmp/dhcp.leases | grep $lan_ip | awk '{print $4"|"$5}')
      user=$(ipsec leases | sed 1d | grep online | sed -n ${i}p | awk -F"'" '{print $2}')
      pool_ip=$(ipsec leases | sed 1d | grep online | sed -n ${i}p | awk '{print $1}')

      #echo $l | sed "s/ESTABLISHED/$pool_ip/g" | sed "s/\[$lan_ip\]/\[$user\]/g" | sed "s/$lan_ip/$lan_ip...$lan_host/g"
      echo $l | sed "s/ESTABLISHED/$pool_ip/g" | sed "s/\[$lan_ip\]/\[$user\]/g"
    # Outside connection
    else
      echo $l | sed "s/ESTABLISHED/$pool_ip/g"
    fi
    i=$((i+1))
  done
fi

if [ $(expr $OPVPN_UP - $OPVPN_DN) -gt 0 ]; then
  echo
  echo "OPENVPN CONNECTED USERS"
  #      client/92.184.116.249:46047 IPv4=10.10.1.2
  #      client/92.184.107.82:49333 IPv4=10.10.1.2
  #      client/92.184.116.249:46047 SIGTERM[soft,remote-exit]
  #      client/92.184.107.82:49333 SIGTERM[soft,remote-exit]
  #      92.184.116.249:46047 TLS: Username/Password authentication succeeded for username 'Jonathan'
  cat /var/log/openvpn.log | grep 'client/' | grep 'IPv4=' | awk '{print "    "$4" "$6" "$10}' | sed 's/,$//g' 2> /dev/null > /tmp/openvpn-users.log
  # Add username
  #      client/92.184.116.249:46047 IPv4=10.10.1.2 'Jonathan'
  cat /var/log/openvpn.log | grep 'Username/Password authentication succeeded' | while read line; do ip=$(echo "$line" | awk '{print $6}'); login=$(echo "$line" | awk -F"'" '{print $2}'); sed -i "/$ip/ s/$/ \t'$login'/" /tmp/openvpn-users.log 2> /dev/null; done
  echo "$(cat /var/log/openvpn.log | grep 'client/' | grep SIGTERM | awk '{print $6}' | awk -F'/' '{print $2}')" | while read line; do [ -n "$line" ] && sed -i "/$line/d" /tmp/openvpn-users.log; done
  cat /tmp/openvpn-users.log
  rm -f /tmp/openvpn-users.log
fi

if [ $(cat /etc/passwd | grep "$(cat /etc/shells)" | wc -l) -ne $OS_SHELL_MAX ]; then
  echo
  echo "ACTIVE USERS SHELL"
  cat /etc/passwd | grep "$(cat /etc/shells)" | sed 's/^/ /'
fi

if [ $(fOpkgUpgradable) -gt 0 ]; then
  echo
  echo "KEEP SYSTEM UP TO DATE"
  echo "$(echored " Packages installed: ")$(opkg list-installed 2> /dev/null | wc -l)"
  echo "$(echored " Packages upgradable: ")$(echopurple $(fOpkgUpgradable))"
  echo " * $(echopurple "/root/opkg-upgrade.sh")"
fi

echo

# Restore Internal Field Separator
IFS=$SAVEIFS
