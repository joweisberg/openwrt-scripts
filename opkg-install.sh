#!/bin/sh
#
# ssh root@openwrt
# /root/opkg-install.sh 2>&1 | tee /var/log/opkg-install.log
#
# Generate backup config: 
# source /etc/os-release && rm -f /mnt/data/backup-$VERSION-$HOSTNAME* && sysupgrade -b /mnt/data/backup-$VERSION-$HOSTNAME.$(uci get dhcp.@dnsmasq[0].domain)-$(date +%F).tar.gz
#
# Restore backup config:
# cp -p /mnt/data/openwrt-owncloud*.tar.gz /tmp && sysupgrade -r /tmp/openwrt-owncloud*.tar.gz
#
# Soft factory reset:
# firstboot -y && reboot now
#
# Flash the new OpenWrt firmware:
# mkdir /mnt/data; mount /dev/sda3 /mnt/data
# sysupgrade -v /mnt/data/openwrt-19.07.7-ath79-generic-tplink_archer-c7-v2-squashfs-sysupgrade.bin
# 
FILE_PATH=$(readlink -f $(dirname $0))  #/root
FILE_NAME=$(basename $0)                #opkg-install.sh
FILE_NAME=${FILE_NAME%.*}               #opkg-install
FILE_DATE=$(date +'%Y%m%d-%H%M%S')
FILE_LOG="/var/log/$FILE_NAME.log"

HELP=0
sleep 1 # Time to write on disk the file log
if [ ! -f $FILE_LOG ] || [ $(cat $FILE_LOG | wc -l) -gt 0 ] || [ "$(ls --full-time $FILE_LOG | awk '{print $6" "$7}')" != "$(date +'%Y-%m-%d %H:%M:%S' --date="@$(($(date +%s) - 1))")" ]; then
  HELP=1
  echo "* "
  echo "* $FILE_LOG file not found!"
fi
if [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ $HELP -eq 1 ]; then
  echo "* "
  echo "* Usage:"
  echo "* $FILE_PATH/$FILE_NAME.sh 2>&1 | tee $FILE_LOG"
  exit 1
fi


###############################################################################
##### Default environment variables
###############################################################################

# Do not interprate space in variable
SAVEIFS=$IFS
IFS=$'\n'

source /etc/os-release

ENV=0
DOMAIN="${1:-sub.domain.com}"   ## This domain must actually point to your router
LOCAL_DOMAIN="${DOMAIN%%.*}"
WIFI_SSID="Box-$(cat /dev/urandom | tr -dc A-Z | head -c4)"
WIFI_KEY="$(cat /dev/urandom | tr -dc A-Za-z0-9 | head -c13)"
MESH_SSID="$(echo $WIFI_SSID | sed 's/Box-/Mesh-/g')"
MESH_KEY="$WIFI_KEY"
WIFI_GUEST_KEY="Guest$(date +'%Y')"
IPADDR="192.168.1.1"
NETADDR=${IPADDR%.*}
NETADDR_GUEST="10.10.10"
WIFI_80211R=0                   ## Enable 802.11r Fast Transition
MESH=0                          ## Enable Mesh support like with dedicated SSID to connect wifi repeater
FBXTV=0                         ## QoS advices Smart TV for Freebox
UWAN=0                          ## USB tethering connection
WWAN=0                          ## USB Modem 4G/LTE with NCM protocol
AD_REBOOT=0
SQM=0
STATS=0
FW_FWD_NAS_CERTS=0

# Create and moving Rootfs & Swap on new USB storage
USBREBOOT=0
USBWIPE=0
USBBUILT=0




###############################################################################
##### Environment variables
###############################################################################

# Source under this script directory
cd $(readlink -f $(dirname $0))
if [ -f .env ]; then
  ENV=1
  source ./.env
  LOCAL_DOMAIN="${DOMAIN%%.*}"
  NETADDR=${IPADDR%.*}
fi




###############################################################################
### Pre-Script
###############################################################################

echo "* Set access rights on uploaded files"
find /root -type d -exec chmod 755 "{}" \;
find /root -type f -exec chmod 644 "{}" \;
find /root -type f -name "*.sh" -exec chmod +x "{}" \;
mkdir -p /etc/acme
find /etc/acme -type d -exec chmod 755 "{}" \;
find /etc/acme -type f -exec chmod 644 "{}" \;
find /etc/acme -type f -name "*.sh" -exec chmod +x "{}" \;
chmod 644 /etc/shadow




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




###############################################################################
##### Check internet connection
###############################################################################

H_WIFI_SSID="${H_WIFI_SSID:-AndroidAP}"
H_WIFI_KEY="${H_WIFI_KEY:-android}"
wget -q --spider --timeout=5 http://www.google.com 2> /dev/null
if [ $? -eq 0 ]; then  # if Google website is available we update
  echo "* "
  echo "* You are connected to the internet."
  echo "* "
else
  echo "* "
  echo "* You are not connected to the internet, default wan interface is down!"
  echo "* "

  echo -n "* Enter Hotspot SSID <$H_WIFI_SSID>? "
  read answer
  if [ -n "$answer" ]; then
    H_WIFI_SSID=$answer
  fi
  echo -n "* Enter Hotspot key <$H_WIFI_KEY>? "
  read answer
  if [ -n "$answer" ]; then
    H_WIFI_KEY=$answer
  fi

  # /etc/config/firewall
  # Connect Hotspot client from radio1 to wan zone
  #for L in $(uci show firewall); do
  #  # firewall.@zone[1].name='wan'
  #  if [ -n "$(echo "$L" | grep 'zone' | grep 'name' | grep 'wan')" ]; then
  #    I=$(echo "$L" | awk -F'[][]' '{print $2}')
  #    uci add_list firewall.@zone[$I].network='hwan'
  #    break
  #  fi
  #done
  #uci add_list firewall.@zone[1].network='hwan'
  sed -i 's/wan wan6/wan wan6 hwan/g' /etc/config/firewall
  uci commit firewall
  # /etc/config/network
  uci set network.hwan=interface
  uci set network.hwan.proto='dhcp'
  uci commit network
  # /etc/config/wireless
  uci set wireless.wifinet10=wifi-iface
  uci set wireless.wifinet10.device='radio1'
  uci set wireless.wifinet10.mode='sta'
  uci set wireless.wifinet10.network='hwan'
  uci set wireless.wifinet10.ssid="$H_WIFI_SSID"
  uci set wireless.wifinet10.key="$H_WIFI_KEY"
  uci set wireless.wifinet10.encryption='psk-mixed'

  # Enable radio1 devices for hotspot connection
  uci set wireless.radio1.disabled='0'
  # uci set wireless.default_radio1.disabled='0'
  # uci set wireless.wifinet0.disabled='0'
  for UCI_DEV in $(uci show wireless | grep ".device='radio1'" | cut -d'=' -f1 | sed 's/.device//g'); do uci set $UCI_DEV.disabled='0'; done
  uci commit wireless
  wifi down radio1 && sleep 3 && wifi up radio1
  echo "* Hotspot <$H_WIFI_SSID> as of wan zone is setup."
  echo "* Please check wireless network http://$HOSTNAME/cgi-bin/luci/admin/network/wireless"
  
  echo "* "
  echo -n "* Press <enter> to test internet connection..."
  read answer
  
  wget -q --spider --timeout=5 http://www.google.com 2> /dev/null
  if [ $? -eq 0 ]; then  # if Google website is available we update
    echo "* "
    echo "* You are connected to the internet."
    echo "* "
  else
    echo "* "
    echo "* Please check internet connection and try again!"
    echo "* "
    exit 0
  fi
fi




###############################################################################
##### Create and moving Rootfs & Swap on USB storage (create partitions, format, copy, mount)
###############################################################################

~/opkg-install_rootfs2usb.sh
[ $? -ne 0 ] && exit $?




###############################################################################
##### Environment variables (loaded or entered)
###############################################################################

if [ $ENV -eq 1 ]; then
  echo "* "
  echo "* The current setup: "
  echo "* "
  cat .env | grep -v "^#"
  echo "* "
  echo -n "* Do you accept this setup? [Y/n] "
  read answer
  if [ -n "$(echo $answer | grep -i '^n')" ]; then
    ENV=0
    echo "* "
  fi
fi

if [ $ENV -eq 0 ]; then
  echo -n "* Enter domain name? <$DOMAIN> "
  read answer
  if [ -n "$answer" ]; then
    DOMAIN=$answer
    LOCAL_DOMAIN="${DOMAIN%%.*}"
  fi
  echo -n "* Enter Wi-Fi name? <$WIFI_SSID> "
  read answer
  if [ -n "$answer" ]; then
    WIFI_SSID=$answer
  fi
  echo -n "* Enter Wi-Fi key? <$WIFI_KEY> "
  read answer
  if [ -n "$answer" ]; then
    WIFI_KEY=$answer
  fi
  echo -n "* Enter Wi-Fi Guest key? <$KEY_GUEST> "
  read answer
  if [ -n "$answer" ]; then
    WIFI_GUEST_KEY=$answer
  fi
  echo -n "* Enter this router ip address? <$IPADDR> "
  read answer
  if [ -n "$answer" ]; then
    IPADDR=$answer
    NETADDR=${IPADDR%.*}
  fi
  echo -n "* Enter Guest ip address mask? <$NETADDR_GUEST> "
  read answer
  if [ -n "$answer" ]; then
    NETADDR_GUEST=$answer
  fi
  echo -n "* Enable Freebox TV QoS advices config? [y/N] "
  read answer
  if [ -n "$(echo $answer | grep -i '^y')" ]; then
    FBXTV=1
  fi
  echo -n "* Enable usb tethering config? [y/N] "
  read answer
  if [ -n "$(echo $answer | grep -i '^y')" ]; then
    UWAN=1
  fi
  echo -n "* Enable wwan config? [y/N] "
  read answer
  if [ -n "$(echo $answer | grep -i '^y')" ]; then
    WWAN=1
  fi
  echo -n "* Enable Advanced Reboot? [y/N] "
  read answer
  if [ -n "$(echo $answer | grep -i '^y')" ]; then
    AD_REBOOT=1
  fi
  echo -n "* Enable SQM QoS? [y/N] "
  read answer
  if [ -n "$(echo $answer | grep -i '^y')" ]; then
    SQM=1
    echo "* "
    echo "* Please check internet speed with https://www.speedtest.net/"
    
    SQM_DL=500
    echo -n "* Enter max donwload speed? <${SQM_DL}Mbps> "
    read answer
    if [ -n "$answer" ]; then
      SQM_DL=$answer
    fi
    #SQM_DL=$(($SQM_DL * 1000 * 95/100))
    SQM_DL=$(($SQM_DL * 1000))

    SQM_UL=500
    echo -n "* Enter max upload speed? <${SQM_UL}Mbps> "
    read answer
    if [ -n "$answer" ]; then
      SQM_UL=$answer
    fi
    #SQM_UL=$(($SQM_UL * 1000 * 95/100))
    SQM_UL=$(($SQM_UL * 1000))
  fi
  echo -n "* Enable statistics collectd? [y/N] "
  read answer
  if [ -n "$(echo $answer | grep -i '^y')" ]; then
    STATS=1
  fi
  echo -n "* Get ACME certificates with NAS by default? [y/N] "
  read answer
  if [ -n "$(echo $answer | grep -i '^y')" ]; then
    FW_FWD_NAS_CERTS=1
  fi

  # Save environment variables
  cat << EOF > .env
DOMAIN="$DOMAIN"
WIFI_SSID="$WIFI_SSID"
WIFI_KEY="$WIFI_KEY"
WIFI_GUEST_KEY="$WIFI_GUEST_KEY"
IPADDR="$IPADDR"
FBXTV=$FBXTV
UWAN=$UWAN
WWAN=$WWAN
AD_REBOOT=$AD_REBOOT
SQM=$SQM
SQM_DL=$SQM_DL
SQM_UL=$SQM_UL
STATS=$STATS
FW_FWD_NAS_CERTS=$FW_FWD_NAS_CERTS
EOF

fi


runstart=$(date +%s)
echo "* "
echo "* Start time: $(date)"
echo "* "


###############################################################################
##### Base config luci/system/interface/dhcp/network/firewall/wireless
###############################################################################

echo "* UCI config luci"
uci set luci.main.mediaurlbase='/luci-static/bootstrap'
uci commit luci

echo "* UCI config hostname"
HOSTNAME=${HOSTNAME:-OpenWrt}
uci set system.@system[0].hostname="$HOSTNAME"
uci commit system

echo "* UCI config timezone"
uci set system.@system[0].zonename="$TZ_NAME"
uci set system.@system[0].timezone="$TZ"
uci commit system

echo "* UCI config lan network"
uci set network.lan.ipaddr="$IPADDR"
uci set network.lan.netmask='255.255.255.0'
# Cloudflare and APNIC
# Primary DNS: 1.1.1.1
# Secondary DNS: 1.0.0.1
uci -q del network.lan.dns
uci add_list network.lan.dns='9.9.9.9'
uci add_list network.lan.dns='149.112.112.112'
uci -q del network.lan.ip6assign
uci set network.wan.metric='10'
uci commit network

echo "* UCI config Guest network"
uci -q del network.guest_dev
uci set network.guest_dev=device
uci set network.guest_dev.type=bridge
uci set network.guest_dev.name=br-guest
uci -q del network.guest
uci set network.guest=interface
uci set network.guest.device='br-guest'
uci set network.guest.proto='static'
uci set network.guest.ipaddr="$NETADDR_GUEST.1"
uci set network.guest.netmask='255.255.255.0'
uci -q del network.guest.dns
uci add_list network.guest.dns='9.9.9.9'
uci add_list network.guest.dns='149.112.112.112'
uci commit network

echo "* UCI config dhcp"
uci set dhcp.@dnsmasq[0].local="/$LOCAL_DOMAIN/"
uci set dhcp.@dnsmasq[0].domain="$LOCAL_DOMAIN"
uci set dhcp.lan.start='100'
uci set dhcp.lan.limit='150'
uci set dhcp.lan.leasetime='12h'
uci set dhcp.lan.force='1'
# Disable DHCPv6 Server
uci -q del dhcp.lan.dhcpv6
uci -q del dhcp.lan.ra
uci -q del dhcp.lan.ra_management
uci -q del network.lan.delegate
uci set dhcp.guest=dhcp
uci set dhcp.guest.interface='guest'
uci set dhcp.guest.start='100'
uci set dhcp.guest.limit='50'
uci set dhcp.guest.leasetime='1h'
uci commit dhcp
uci commit network

echo "* UCI config firewall"
uci set firewall.@defaults[0].synflood_protect='1'
uci set firewall.@defaults[0].drop_invalid='1'
uci set firewall.@defaults[0].input='DROP'
uci set firewall.@defaults[0].output='ACCEPT'
uci set firewall.@defaults[0].forward='REJECT'
uci set firewall.@defaults[0].flow_offloading='1'
uci set firewall.@defaults[0].flow_offloading_hw='1'
# Remove existing config
for L in $(uci show firewall | grep "=zone"); do
  uci -q del firewall.@zone[-1]
done
uci add firewall zone
uci set firewall.@zone[-1]=zone
uci set firewall.@zone[-1].name='lan'
uci set firewall.@zone[-1].network='lan'
uci set firewall.@zone[-1].input='ACCEPT'
uci set firewall.@zone[-1].output='ACCEPT'
uci set firewall.@zone[-1].forward='ACCEPT'
uci add firewall zone
uci set firewall.@zone[-1]=zone
uci set firewall.@zone[-1].name='wan'
uci set firewall.@zone[-1].network='wan wan6'
uci set firewall.@zone[-1].input='DROP'
uci set firewall.@zone[-1].output='ACCEPT'
uci set firewall.@zone[-1].forward='REJECT'
uci set firewall.@zone[-1].masq='1'
uci set firewall.@zone[-1].mtu_fix='1'
uci add firewall zone
uci set firewall.@zone[-1]=zone
uci set firewall.@zone[-1].name='guest'
uci set firewall.@zone[-1].network='guest'
uci set firewall.@zone[-1].input='DROP'
uci set firewall.@zone[-1].output='ACCEPT'
uci set firewall.@zone[-1].forward='REJECT'
# Remove existing config
for L in $(uci show firewall | grep "=forwarding"); do
  uci -q del firewall.@forwarding[-1]
done
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='lan'
uci set firewall.@forwarding[-1].dest='wan'
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='guest'
uci set firewall.@forwarding[-1].dest='wan'


# Remove existing config
for L in $(uci show firewall | grep "=redirect"); do
  uci -q del firewall.@redirect[-1]
done
# Add automatically firewall forward redirection
if [ -f .env ]; then
  echo "* UCI config firewall redirect"
  # FW_FWD="name|proto|src_dport|dest_ip|dest_port|enabled"
  # FW_FWD="Allow-http|tcp-udp|80|$NETADDR.10|8080|off"
  for L in $(cat .env | grep "^FW_FWD="); do
    # Get the value after =
    V=${L#*=}
    # Evaluate variable inside the line
    V=$(eval echo $V)
    # Remove " from string
    #V=${V//\"}
    
    uci add firewall redirect
    uci set firewall.@redirect[-1]=redirect
    uci set firewall.@redirect[-1].name="$(echo $V | cut -d'|' -f1)"
    uci set firewall.@redirect[-1].target='DNAT'
    if [ "$(echo $V | cut -d'|' -f2)" == "tcp" ]; then
      uci set firewall.@redirect[-1].proto='tcp'
    elif [ "$(echo $V | cut -d'|' -f2)" == "udp" ]; then
      uci set firewall.@redirect[-1].proto='udp'
    elif [ "$(echo $V | cut -d'|' -f2)" == "tcp-udp" ]; then
      uci -q del firewall.@redirect[-1].proto
      uci add_list firewall.@redirect[-1].proto='tcp'
      uci add_list firewall.@redirect[-1].proto='udp'
    else
      uci set firewall.@redirect[-1].proto='all'
    fi
    uci set firewall.@redirect[-1].src='wan'
    uci set firewall.@redirect[-1].dest='lan'
    uci set firewall.@redirect[-1].src_dport="$(echo $V | cut -d'|' -f3)"
    uci set firewall.@redirect[-1].dest_ip="$(echo $V | cut -d'|' -f4)"
    if [ -n "$(echo $V | cut -d'|' -f5)" ]; then
      uci set firewall.@redirect[-1].dest_port="$(echo $V | cut -d'|' -f5)"
    fi
    if [ -n "$(echo $V | cut -d'|' -f6)" ] && [ "$(echo $V | cut -d'|' -f6)" == "off" ]; then
      uci set firewall.@redirect[-1].enabled='0'
    fi
  done
fi
uci commit firewall

echo "* UCI config firewall rule"
uci add firewall rule
uci set firewall.@rule[-1]=rule
uci set firewall.@rule[-1].name='Guest-DHCP'
uci set firewall.@rule[-1].src='guest'
uci set firewall.@rule[-1].dest_port='67-68'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].target='ACCEPT'
uci add firewall rule
uci set firewall.@rule[-1]=rule
uci set firewall.@rule[-1].name='Guest-DNS'
uci set firewall.@rule[-1].src='guest'
uci set firewall.@rule[-1].dest_port='53'
uci -q del firewall.@rule[-1].proto
uci add_list firewall.@rule[-1].proto='tcp'
uci add_list firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall

echo "* UCI config wireless"
uci set wireless.radio0.hwmode='11a'
uci set wireless.radio0.htmode='VHT80'
uci -q del wireless.radio0.legacy_rates
uci set wireless.radio0.country='FR'
uci set wireless.radio0.bursting='1'
uci set wireless.radio0.ff='1'
uci set wireless.radio0.compression='1'
uci set wireless.radio0.turbo='1'
uci set wireless.radio0.channel='52'
uci set wireless.radio0.cell_density='0'
uci set wireless.radio0.disabled='0'
uci set wireless.default_radio0.mode='ap'
uci set wireless.default_radio0.ssid="$WIFI_SSID"
uci set wireless.default_radio0.key="$WIFI_KEY"
uci set wireless.default_radio0.encryption='psk-mixed+ccmp'
uci set wireless.default_radio0.network='lan'
uci set wireless.radio1.hwmode='11g'
uci set wireless.radio1.htmode='HT40'
uci -q del wireless.radio1.legacy_rates
uci set wireless.radio1.country='FR'
uci set wireless.radio1.bursting='1'
uci set wireless.radio1.ff='1'
uci set wireless.radio1.compression='1'
uci set wireless.radio1.turbo='1'
uci set wireless.radio1.channel='auto'
uci set wireless.radio1.cell_density='0'
uci set wireless.radio1.disabled='0'
uci set wireless.default_radio1.mode='ap'
uci set wireless.default_radio1.ssid="$WIFI_SSID"
uci set wireless.default_radio1.key="$WIFI_KEY"
uci set wireless.default_radio1.encryption='psk-mixed+ccmp'
uci set wireless.default_radio1.network='lan'

if [ $MESH -eq 1 ]; then
  uci set wireless.wifinet0=wifi-iface
  uci set wireless.wifinet0.device='radio0'
  uci set wireless.wifinet0.mode='ap'
  uci set wireless.wifinet0.network='lan'
  uci set wireless.wifinet0.ssid="$MESH_SSID"
  uci set wireless.wifinet0.key="$MESH_KEY"
  uci set wireless.wifinet0.encryption='psk-mixed+ccmp'
  uci set wireless.wifinet1=wifi-iface
  uci set wireless.wifinet1.device='radio1'
  uci set wireless.wifinet1.mode='ap'
  uci set wireless.wifinet1.network='lan'
  uci set wireless.wifinet1.ssid="$MESH_SSID"
  uci set wireless.wifinet1.key="$MESH_KEY"
  uci set wireless.wifinet1.encryption='psk-mixed+ccmp'
fi

uci set wireless.wifinet5=wifi-iface
uci set wireless.wifinet5.device='radio1'
uci set wireless.wifinet5.mode='ap'
uci set wireless.wifinet5.network='guest'
uci set wireless.wifinet5.ssid="${WIFI_SSID}_Guest"
uci set wireless.wifinet5.key="$WIFI_GUEST_KEY"
uci set wireless.wifinet5.encryption='psk-mixed'
uci set wireless.wifinet5.isolate='1'

if [ $WIFI_80211R -eq 1 ]; then
  # Enable 802.11r Fast Transition
  # Enable fast roaming among access points that belong to the same Mobility Domain
  uci set wireless.default_radio0.ieee80211r='1'
  uci set wireless.default_radio0.ft_over_ds='1'
  uci set wireless.default_radio0.ft_psk_generate_local='1'
  uci set wireless.default_radio1.ieee80211r='1'
  uci set wireless.default_radio1.ft_over_ds='1'
  uci set wireless.default_radio1.ft_psk_generate_local='1'
  # Disassociate On Low Acknowledgement
  uci set wireless.default_radio0.disassoc_low_ack='1'
  uci set wireless.default_radio1.disassoc_low_ack='1'
fi
uci commit wireless

# Add automatically dhcp static leases
echo "* UCI config dhcp static leases"
# Remove existing config
for L in $(uci show dhcp | grep "=host"); do
  uci -q del dhcp.@host[-1]
done
# DHCP_STATIC="nas|DC:A6:32:40:87:93 DC:A6:32:40:87:94|$NETADDR.10"
for L in $(cat .env | grep "^DHCP_STATIC="); do
  # Get the value after =
  V=${L#*=}
  # Evaluate variable inside the line
  V=$(eval echo $V)
  # Remove " from string
  #V=${V//\"}
  
  uci add dhcp host
  uci set dhcp.@host[-1]=host
  uci set dhcp.@host[-1].name="$(echo $V | cut -d'|' -f1)"
  uci set dhcp.@host[-1].dns='1'
  #uci set dhcp.@host[-1].mac="$(echo $V | cut -d'|' -f2)"
  # Interprate space in variable
  SAVEIFS2=$IFS
  IFS=$' '
  # mac_list="DC:A6:32:40:87:93 DC:A6:32:40:87:94"
  for mac in $(echo "$V" | cut -d'|' -f2); do uci add_list dhcp.@host[-1].mac="$mac"; done
  # Rollback Internal Field Separator
  IFS=$SAVEIFS2
  uci set dhcp.@host[-1].ip="$(echo $V | cut -d'|' -f3)"
done
uci commit dhcp

# Add automatically domain host
echo "* UCI config dhcp host"
if [ -n "$(cat .env | grep "^DOMAIN_HOST=")" ]; then
  echo "* UCI config dhcp domain"
  # Remove existing config
  for L in $(uci show dhcp | grep "=domain"); do
    uci -q del dhcp.@domain[-1]
  done
  
  # DOMAIN_HOST="openwrt.nas|$NETADDR.10"
  for L in $(cat .env | grep "^DOMAIN_HOST="); do
    # Get the value after =
    V=${L#*=}
    # Evaluate variable inside the line
    V=$(eval echo $V)
    # Remove " from string
    #V=${V//\"}
    
    uci add dhcp domain
    uci set dhcp.@domain[-1]=domain
    uci set dhcp.@domain[-1].name="$(echo $V | cut -d'|' -f1).$LOCAL_DOMAIN"
    uci set dhcp.@domain[-1].ip="$(echo $V | cut -d'|' -f2)"
  done
fi
uci commit dhcp




###############################################################################
##### Package USB-3.0, UWAN, WWAN, WPA3, SFTP, SMB, NFS, DDNS, SQM QoS, Collectd/Stats, Acme, uHTTPd, OpenVPN, IKEv2/IPsec with strongSwan, Adblock, crontab, Watchcat, mSMTP
###############################################################################

echo "* Checking for updates, please wait..."
fCmd opkg update

if [ $AD_REBOOT -eq 1 ]; then
  echo "* Package Advanced Reboot UI"
  fCmd opkg install luci-app-advanced-reboot
fi

echo "* Package USB 3.0 disk management"
fCmd opkg install kmod-usb-core kmod-usb2 kmod-usb3 kmod-usb-storage kmod-usb-storage-uas
echo "* Package ext4/FAT/exFAT/ntfs"
fCmd opkg install kmod-fs-ext4 kmod-fs-vfat kmod-fs-exfat libblkid ntfs-3g

echo "* Package mounted partitions"
fCmd opkg install block-mount
echo "* UCI enable mounted partitions"
#uci set fstab.@global[0].anon_swap='0'
#uci set fstab.@global[0].anon_mount='0'
#uci set fstab.@global[0].check_fs='0'
# Enable all mounted partitions
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

if [ -n "$(cat .env | grep "^MNT_DEV=")" ]; then
  echo "* UCI mount partitions"
  # MNT_DEV="home-data|/mnt/usb|rw,noatime"
  for L in $(cat .env | grep "^MNT_DEV="); do
    # Get the value after =
    V=${L#*=}
    # Evaluate variable inside the line
    V=$(eval echo $V)
    # Remove " from string
    #V=${V//\"}

    LABEL="$(echo $V | cut -d'|' -f1)"
    DEVDATA="$(block info | grep "$LABEL" | cut -d':' -f1)"
    eval $(block info "$DEVDATA" | grep -o -e "UUID=\S*")
    if [ -n "$(block info | grep "$LABEL")" ]; then

      # Remove existing similar automount device
      for LL in $(uci show fstab | grep .uuid=); do
        # Get the value after =
        V_UUID=${LL#*=}
        # Evaluate variable inside the line
        V_UUID=$(eval echo $V_UUID)
        I=$(echo "$LL" | awk -F'[][]' '{print $2}')
        if [ "$V_UUID" == "$UUID" ]; then
          umount $(uci get fstab.@mount[$I].target) && rm -Rf $(uci get fstab.@mount[$I].target)
          uci -q del fstab.@mount[$I]
          break
        fi
      done
      
      uci add fstab mount
      uci set fstab.@mount[-1]=mount
      uci set fstab.@mount[-1].enabled='1'
      #uci set fstab.@mount[-1].device="$DEVDATA"
      #uci set fstab.@mount[-1].label="$LABEL"
      uci set fstab.@mount[-1].uuid="$UUID"
      uci set fstab.@mount[-1].target="$(echo $V | cut -d'|' -f2)"
      uci set fstab.@mount[-1].options="$(echo $V | cut -d'|' -f3)"
    else
      echo "* Mount device $V not found!"
    fi
  done
  uci commit fstab
  # Mount everything when you change your fstab configuration
  block mount
fi

echo "* Package hd-idle"
fCmd opkg install luci-app-hd-idle
echo "* UCI config hd-idle"
uci set hd-idle.@hd-idle[0]=hd-idle
uci set hd-idle.@hd-idle[0].enabled='0'
uci set hd-idle.@hd-idle[0].disk='sda'
uci set hd-idle.@hd-idle[0].idle_time_unit='minutes'
uci set hd-idle.@hd-idle[0].idle_time_interval='10'
uci commit hd-idle

if [ $UWAN -eq 1 ]; then
  echo "* UCI config network uwan"
  uci set network.uwan=interface
  uci set network.uwan.device='eth2'
  uci set network.uwan.proto='dhcp'
  uci commit network

  #uci add_list firewall.@zone[1].network='uwan'
  sed -i 's/wan wan6/wan wan6 uwan/g' /etc/config/firewall
  uci commit firewall
fi

if [ $WWAN -eq 1 ]; then
  echo "* Package USB Huawei Modem 4G/LTE with NCM protocol"
  fCmd opkg install kmod-usb-net-rndis usb-modeswitch
  fCmd opkg install comgt-ncm kmod-usb-net-huawei-cdc-ncm luci-proto-ncm usb-modeswitch
  echo "* UCI config network wwan"
  uci set network.wwan=interface
  uci set network.wwan.proto='ncm'
  uci set network.wwan.device='/dev/cdc-wdm0'
  uci set network.wwan.mode='preferlte'
  uci set network.wwan.apn='free'
  uci set network.wwan.ipv6='auto'
  uci set network.wwan.delay='30'
  uci set network.wwan.metric='20'
  uci commit network

  #uci add_list firewall.@zone[1].network='wwan'
  sed -i 's/wan wan6/wan wan6 wwan/g' /etc/config/firewall
  uci commit firewall
fi

echo "* Package WPA2/WPA3 Personal (PSK/SAE) mixed mode"
opkg remove --autoremove wpad-* > /dev/null 2>&1
fCmd opkg install wpad-basic-wolfssl
echo "* UCI config WPA2/WPA3 (PSK/SAE)"
# Fix iOS 13.1.3 connected: option auth_cache '1'
#uci set wireless.default_radio0.auth_cache='1'
#uci set wireless.default_radio0.ieee80211w='0'
uci -q del wireless.default_radio0.ieee80211w
uci set wireless.default_radio0.encryption='sae-mixed'
#uci set wireless.default_radio1.auth_cache='1'
#uci set wireless.default_radio1.ieee80211w='0'
uci -q del wireless.default_radio1.ieee80211w
uci set wireless.default_radio1.encryption='sae-mixed'

if [ $MESH -eq 1 ]; then
  uci set wireless.wifinet0.encryption='sae-mixed'
  uci set wireless.wifinet1.encryption='sae-mixed'
fi

# Keep Guest Encryption: WPA2 PSK (CCMP)
#uci set wireless.wifinet5.auth_cache='1'
#uci set wireless.wifinet5.ieee80211w='0'
uci set wireless.wifinet5.encryption='psk-mixed'
uci commit wireless

echo "* Package SFTP fileserver"
fCmd opkg install openssh-sftp-server

echo "* Package Samba SMB/CIFS fileserver"
fCmd opkg install luci-app-samba4
if [ -n "$(cat .env | grep "^SMB_SHARE=")" ]; then
  echo "* UCI config samba"
  uci set samba4.@samba[0].description="Samba on $HOSTNAME"
  uci set samba4.@samba[0].interface='lan'
  uci set samba4.@samba[0].enable_extra_tuning='1'
  
  # Remove existing config
  for L in $(uci show samba4 | grep "=sambashare"); do
    uci -q del samba4.@sambashare[-1]
  done
  
  # SMB_SHARE="Data$|/mnt/data|no|root"
  for L in $(cat .env | grep "^SMB_SHARE="); do
    # Get the value after =
    V=${L#*=}
    # Evaluate variable inside the line
    V=$(eval echo $V)
    # Remove " from string
    #V=${V//\"}

    P="$(echo $V | cut -d'|' -f2)"
    if [ -n "$(uci show fstab | grep "$P")" ] || [ -d $P ]; then
      uci add samba4 sambashare
      uci set samba4.@sambashare[-1]=sambashare
      uci set samba4.@sambashare[-1].name="$(echo $V | cut -d'|' -f1)"
      uci set samba4.@sambashare[-1].path="$(echo $V | cut -d'|' -f2)"
      [ "$(echo $V | cut -d'|' -f3)" == "yes" ] && uci set samba4.@sambashare[-1].force_root='1'
      uci set samba4.@sambashare[-1].guest_ok='yes'
      [ "$(echo $V | cut -d'|' -f3)" == "no" ] && [ -n "$(echo $V | cut -d'|' -f4)" ] && uci set samba4.@sambashare[-1].users="$(echo $V | cut -d'|' -f4)"
      uci set samba4.@sambashare[-1].create_mask='0666'
      uci set samba4.@sambashare[-1].dir_mask='0777'
    else
      echo "* Samba share $V not found!"
    fi
  done
fi
uci commit samba4
echo "* Set Samba as local master = yes"
mv /etc/samba/smb.conf /etc/samba/smb.conf.bak
sed -i 's/#local master.*/local master = yes/g' /etc/samba/smb.conf.template

if [ -n "$(cat .env | grep "^NFS_SHARE=")" ]; then
  echo "* Package NFS fileserver"
  fCmd opkg install nfs-kernel-server
  
  echo "* UCI config nfs"
  # Remove existing config
  rm -f /etc/exports
  # NFS_SHARE="/mnt/usb|nas"
  for L in $(cat .env | grep "^NFS_SHARE="); do
    # Get the value after =
    V=${L#*=}
    # Evaluate variable inside the line
    V=$(eval echo $V)
    # Remove " from string
    #V=${V//\"}

    DEVDATA="$(echo $V | cut -d'|' -f1)"
    HOSTDATA="$(echo $V | cut -d'|' -f2)"
    if [ -n "$(block info | grep "$DEVDATA")" ]; then
      echo "$DEVDATA $HOSTDATA(rw,async,no_subtree_check,no_root_squash,fsid=0)" >> /etc/exports
    else
      echo "* NFS share $V not found!"
    fi
  done
  # Apply NFS config
  exportfs -a > /dev/null 2>&1
fi

echo "* Package Dynamic DNS for external IP naming"
fCmd opkg install luci-app-ddns
echo "* UCI config ddns"
uci set ddns.myddns_ipv4.enabled='1'
uci set ddns.myddns_ipv4.lookup_host="$DOMAIN"
uci set ddns.myddns_ipv4.ip_source='web'
uci set ddns.myddns_ipv4.service_name='afraid.org-basicauth'
uci set ddns.myddns_ipv4.domain="$DOMAIN"
uci set ddns.myddns_ipv4.username="$DDNS_USR"
uci set ddns.myddns_ipv4.password="$DDNS_PWD"
uci set ddns.myddns_ipv4.force_interval='8'
if [ $UWAN -eq 1 ]; then
  uci set ddns.myddns_ipv4.interface='uwan'
elif [ $WWAN -eq 1 ]; then
  uci set ddns.myddns_ipv4.interface='wwan'
else
  uci set ddns.myddns_ipv4.interface='wan'
fi
uci commit ddns

echo "* Package firewall rtsp nat helper"
fCmd opkg install ipset
fCmd opkg install kmod-ipt-nathelper-rtsp kmod-ipt-raw
echo "* Add firewall rtsp config"
echo "" >> /etc/firewall.user
echo "# PreRouting rtsp nat helper" >> /etc/firewall.user
echo "iptables -t raw -A PREROUTING -p tcp -m tcp --dport 554 -j CT --helper rtsp" >> /etc/firewall.user
echo "net.netfilter.nf_conntrack_helper=1" >> /etc/sysctl.conf

if [ $SQM -eq 1 ]; then
  echo "* Package SQM QoS (aka Smart Queue Management)"
  fCmd opkg install luci-app-sqm
  echo "* UCI config SQM QoS"
  uci set sqm.eth1.enabled='1'
  if [ $UWAN -eq 1 ]; then
    uci set sqm.eth1.interface="$(uci get network.uwan.device)"
  elif [ $WWAN -eq 1 ]; then
    uci set sqm.eth1.interface="wwan0"
  else
    uci set sqm.eth1.interface="$(uci get network.wan.device)"
  fi
  #
  # https://forum.openwrt.org/t/qos-advices-smart-tv/57168
  #
  # https://www.speedtest.net/ --> Up/Down:
  # - 500Mbit/s - 5% = 475Mbit/s * 1000 = 475000kbit/s
  #
  uci set sqm.eth1.download="$SQM_DL"
  uci set sqm.eth1.upload="$SQM_UL"
  uci set sqm.eth1.debug_logging='0'
  uci set sqm.eth1.verbosity='5'
  uci set sqm.eth1.qdisc='cake'
  uci set sqm.eth1.script='layer_cake.qos'

  uci set sqm.eth1.linklayer='ethernet'
  uci set sqm.eth1.overhead='44'
  uci set sqm.eth1.qdisc_advanced='1'
  uci set sqm.eth1.squash_dscp='1'
  uci set sqm.eth1.squash_ingress='1'
  uci set sqm.eth1.ingress_ecn='ECN'
  uci set sqm.eth1.egress_ecn='NOECN'
  uci set sqm.eth1.qdisc_really_really_advanced='1'
  uci set sqm.eth1.iqdisc_opts='diffserv4 nat dual-dsthost'
  uci set sqm.eth1.eqdisc_opts='diffserv4 nat dual-srchost'

  uci commit sqm

  if [ $FBXTV -eq 1 ]; then
    echo "" >> /etc/firewall.user
    echo "# QoS advices Smart TV" >> /etc/firewall.user
    echo "iptables -t mangle -N dscp_mark" >> /etc/firewall.user
    echo "iptables -t mangle -F dscp_mark" >> /etc/firewall.user
    echo "iptables -t mangle -A POSTROUTING -j dscp_mark" >> /etc/firewall.user
    echo "iptables -t mangle -A dscp_mark -s mafreebox.freebox.fr -j DSCP --set-dscp-class CS6" >> /etc/firewall.user
    echo "iptables -t mangle -A dscp_mark -s fbx-player -j DSCP --set-dscp-class CS6" >> /etc/firewall.user
  fi
fi

if [ $STATS -eq 1 ]; then
  echo "* Package Satistics with collectd"
  fCmd opkg install luci-app-statistics collectd-mod-rrdtool collectd-mod-processes collectd-mod-sensors collectd-mod-ping
  echo "* UCI config statistics"
  uci set luci_statistics.collectd_network.enable='1'
  uci set luci_statistics.collectd_network.Forward='0'
  uci -q del luci_statistics.@collectd_network_listen[-1]
  uci add luci_statistics collectd_network_listen
  uci set luci_statistics.@collectd_network_listen[-1].host='0.0.0.0'
  uci set luci_statistics.@collectd_network_listen[-1].port='25826'
  uci -q del luci_statistics.@collectd_network_server[-1]
  uci add luci_statistics collectd_network_server
  uci set luci_statistics.@collectd_network_server[-1].host='0.0.0.0'
  uci set luci_statistics.@collectd_network_server[-1].port='25826'
  
  uci set luci_statistics.collectd_processes.enable='1'
  uci set luci_statistics.collectd_processes.Processes='uhttpd dnsmasq dropbear wireguard udhcpc'
  uci set luci_statistics.collectd_sensors.enable='1'
  uci -q del luci_statistics.collectd_interface.Interfaces
  uci add_list luci_statistics.collectd_interface.Interfaces='br-lan'
  uci add_list luci_statistics.collectd_interface.Interfaces='eth0.2'
  uci -q del luci_statistics.collectd_interface.IgnoreSelected
  
  uci set luci_statistics.collectd_network.enable="1"
  uci set luci_statistics.collectd_ping.enable="1"
  uci set luci_statistics.collectd_ping.Hosts="8.8.8.8 8.8.4.4"

  uci set luci_statistics.collectd_rrdtool.enable='1'
  uci set luci_statistics.collectd_rrdtool.DataDir='/mnt/data/rrd'
  uci set luci_statistics.collectd_rrdtool.RRASingle='1'
  uci -q del luci_statistics.collectd_rrdtool.RRATimespans
  uci add_list luci_statistics.collectd_rrdtool.RRATimespans='1hour'
  uci add_list luci_statistics.collectd_rrdtool.RRATimespans='1day'
  uci add_list luci_statistics.collectd_rrdtool.RRATimespans='1week'
  uci add_list luci_statistics.collectd_rrdtool.RRATimespans='1month'
  uci add_list luci_statistics.collectd_rrdtool.RRATimespans='1year'
  uci set luci_statistics.collectd_rrdtool.RRARows='100'
  uci set luci_statistics.collectd_rrdtool.CacheTimeout='100'
  uci commit luci_statistics
  
  mkdir -p /mnt/data/rrd
  /etc/init.d/luci_statistics restart
  /etc/init.d/collectd restart
  /etc/init.d/rpcd restart
fi

echo "* Package for ACME script"
fCmd opkg install wget ca-bundle
echo "* Install ACME script"
wget -qO /etc/acme/acme.sh  https://raw.githubusercontent.com/Neilpang/acme.sh/master/acme.sh
chmod a+x /etc/acme/acme.sh
/etc/acme/acme.sh --home /etc/acme --install --accountemail $MAIL_ADR
/etc/acme/acme.sh --home /etc/acme --register-account -m $MAIL_ADR
/etc/acme/acme.sh --home /etc/acme --upgrade --auto-upgrade
echo '/etc/acme #ACME certificates and scripts' >> /etc/sysupgrade.conf

echo "* Package Acme UI"
fCmd opkg install luci-app-acme
echo "* UCI config acme"
uci set acme.@acme[0].state_dir='/etc/acme'
uci set acme.@acme[0].account_email="$MAIL_ADR"
uci set acme.@acme[0].debug='0'
uci -q del acme.example
uci set acme.local=cert
uci set acme.local.enabled='1'
uci set acme.local.use_staging='1'
uci set acme.local.keylength='2048'
uci set acme.local.update_uhttpd='1'
uci set acme.local.update_nginx='1'
uci set acme.local.webroot='/www'
uci set acme.local.domains="$DOMAIN"
uci commit acme

echo "* Get ACME certificates"
/etc/init.d/uhttpd stop
if [ $FW_FWD_NAS_CERTS -eq 1 ]; then
  /root/fw-redirect.sh Allow-http=on Allow-NAS-http=off
else
  /root/fw-redirect.sh Allow-http=on
fi
/etc/acme/acme.sh --home /etc/acme --issue --standalone -d $DOMAIN -w /www --keylength 2048
if [ $FW_FWD_NAS_CERTS -eq 1 ]; then
  /root/fw-redirect.sh Allow-http=off Allow-NAS-http=on
else
  /root/fw-redirect.sh Allow-http=off
fi

echo "* Package uHTTPd UI"
fCmd opkg install luci-app-uhttpd
echo "* UCI config uHTTPd"
uci set uhttpd.main.redirect_https=0
uci set uhttpd.main.key="/etc/acme/$DOMAIN/$DOMAIN.key"
uci set uhttpd.main.cert="/etc/acme/$DOMAIN/$DOMAIN.cer"
uci commit uhttpd
chmod 777 /etc/acme/$DOMAIN
/etc/init.d/uhttpd restart



[ $(cat .env | grep "^VPN_" | wc -l) -gt 0 ] && ~/opkg-install_openvpn.sh
[ $(cat .env | grep "^VPN_USER=" | wc -l) -gt 0 ] && ~/opkg-install_strongswan.sh




echo "* Package adblock"
fCmd opkg install luci-app-adblock tcpdump
echo "* UCI config adblock"
uci set adblock.global.adb_enabled='1'
uci set adblock.global.adb_trigger='wan'
uci set adblock.global.adb_report='1'
uci set adblock.global.adb_dnsdir='/mnt/data/adblock/dns'
uci set adblock.global.adb_reportdir='/mnt/data/adblock/report'
uci set adblock.global.adb_tmpbase='/mnt/data/adblock/temp'
uci set adblock.global.adb_backupdir='/mnt/data/adblock/backup'
uci -q del adblock.global.adb_sources
uci add_list adblock.global.adb_sources='adaway'
uci add_list adblock.global.adb_sources='adguard'
uci add_list adblock.global.adb_sources='disconnect'
uci add_list adblock.global.adb_sources='reg_fr'
uci add_list adblock.global.adb_sources='yoyo'
uci commit adblock
mkdir -p /mnt/data/adblock/temp


echo "* Block ip addresses that track attacks, spyware, viruses"
fCmd opkg install ipset
cat << EOF >> /etc/config/firewall

config ipset
  option name 'dropcidr'
  option match 'src_net'
  option storage 'hash'
  option enabled '1'
  option loadfile '/etc/blocklist-ipsets.txt'
 
config rule
  option src 'wan'
  option ipset 'dropcidr'
  option target 'DROP'
  option name 'Blocklist-WAN'
  option enabled '1'
EOF

echo "* Enable crontab 'Scheduled Taks'"
/etc/init.d/cron enable
cat << 'EOF' > /etc/crontabs/root
# Backup config file every Friday @06:00
0 6 * * 5 source /etc/os-release && rm -f /mnt/data/backup-$VERSION-$HOSTNAME* && sysupgrade -b /mnt/data/backup-$VERSION-$HOSTNAME.$(uci get dhcp.@dnsmasq[0].domain)-$(date +%F).tar.gz
# Packages upgrade daily @02:00
0 2 * * * /root/opkg-upgrade.sh
# Update ip addresses list that track attacks, spyware, viruses daily @03:00
0 3 * * * wget --timeout=5 -qO /etc/blocklist-ipsets.txt https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/firehol_level3.netset
# Renew WiFi Guest password every year @00:00
0 0 1 1 * source /root/.env && wifi down radio0 && uci set wireless.wifinet5.key="$WIFI_GUEST_KEY" && uci commit wireless && sleep 2 && wifi up radio0
# Check wifi devices every 1 min
*/1 * * * * /root/healthcheck-wifi.sh
# Check url(s) status every 3 mins
#*/3 * * * * /root/healthcheck-url.sh
EOF

if [ $WWAN -eq 1 ]; then
  echo "# Check LTE connection every 1 min" >> /etc/crontabs/root
  echo "*/1 * * * * /root/healthcheck-wwan.sh" >> /etc/crontabs/root
  echo "# Restart wwan interface @02:50 (sync ip renew every 12h, next @15h00)" >> /etc/crontabs/root
  echo "50 2 * * * ifdown wwan && sleep 2 && ifup wwan" >> /etc/crontabs/root
else
  rm -f /root/healthcheck-wwan.sh
fi

if [ $FW_FWD_NAS_CERTS -eq 1 ]; then
  echo "# Check NAS status and Port Forwards http/https every 3 mins" >> /etc/crontabs/root
  echo "#*/3 * * * * /root/healthcheck-nas.sh" >> /etc/crontabs/root
  echo "# Certificates renew every 1st of the month @03:00" >> /etc/crontabs/root
  echo "0 3 1 * * /etc/init.d/uhttpd stop; /etc/acme/acme.sh --home /etc/acme --upgrade > /etc/acme/log.txt 2>&1; /root/fw-redirect.sh Allow-http=on Allow-NAS-http=off; /etc/acme/acme.sh --home /etc/acme --renew-all --standalone --force >> /etc/acme/log.txt 2>&1; /root/fw-redirect.sh Allow-http=off Allow-NAS-http=on; /etc/init.d/uhttpd restart; /etc/init.d/ipsec restart" >> /etc/crontabs/root
else
  rm -f /root/healthcheck-nas.sh
  echo "# Certificates renew every 1st of the month @03:00" >> /etc/crontabs/root
  echo "0 3 1 * * /etc/init.d/uhttpd stop; /etc/acme/acme.sh --home /etc/acme --upgrade > /etc/acme/log.txt 2>&1; /root/fw-redirect.sh Allow-http=on; /etc/acme/acme.sh --home /etc/acme --renew-all --standalone --force >> /etc/acme/log.txt 2>&1; /root/fw-redirect.sh Allow-http=off; /etc/init.d/uhttpd start; /etc/init.d/ipsec restart" >> /etc/crontabs/root
fi
if [ -f /root/dl-certs_*.sh ]; then
  fCmd opkg install sshpass
  echo "* Certificates download every 1st of the month @03:10" >> /etc/crontabs/root
  echo "10 3 1 * * $(ls /root/dl-certs_*.sh) >> /var/log/dl-certs.log" >> /etc/crontabs/root
fi

echo "* Package watchcat (periodic reboot or reboot on internet drop)"
fCmd opkg install luci-app-watchcat
echo "* UCI config watchcat"
uci -q del watchcat.@watchcat[0]
uci commit watchcat

echo "* Package mSMTP mail client"
fCmd opkg install msmtp
echo "* Set mSMTP account free,gmail"
cat << EOF > /etc/msmtprc
# A system wide configuration file is optional.
# If it exists, it usually defines a default account.
# This allows msmtp to be used like /usr/sbin/sendmail.

# Set default values for all folowwing accounts.
defaults
# Use Standard/RFC on port 25
# Use TLS on port 465
# Use STARTTLS on port 587
tls_certcheck off
aliases /etc/msmtp.aliases
logfile /var/log/msmtp.log

# Gmail
account gmail
host smtp.gmail.com
port 587
tls on
tls_starttls on
auto_from on
auth on
#user $(echo $GMAIL_USR | awk -F@ '{print $1}')
user $GMAIL_USR
password $GMAIL_PWD

# SendGrid: Email Delivery, API, Marketing Service
account sendgrid
host smtp.sendgrid.net
port 587
tls on
tls_starttls on
from $SENDGRID_FROM
auth on
user apikey
password $SENDGRID_PWD

# Set a default account
account default : sendgrid
EOF
cat << EOF > /etc/msmtp.aliases
root: $MAIL_ADR
EOF
chmod 644 /etc/msmtprc
echo '/etc/msmtprc* #mSMTP mail config' >> /etc/sysupgrade.conf
# Test mSMTP send mail:
# echo "Hello this is sending email using mSMTP" | msmtp $(id -un)
# echo -e "Subject: Test mSMTP\n\nHello this is sending email using mSMTP" | msmtp $(id -un)
# echo -e "Subject: Power outage @ $(date)\n\n$(upsc el650usb)" | msmtp -a gmail $(id -un)
# echo -e "From: Pretty Name\r\nSubject: Example subject\r\nContent goes here." | msmtp --debug $(cat .env | awk -F= '/^MAIL_ADR=/{print $2}' | sed 's/"//g')
# Error:
# Allow access to unsecure apps
# https://myaccount.google.com/lesssecureapps
# msmtp: authentication failed (method PLAIN)
# https://accounts.google.com/DisplayUnlockCaptcha

echo "* Set timezone $TZ_NAME"
fCmd opkg install zoneinfo-europe
ln -sf /usr/share/zoneinfo/$TZ_NAME /etc/localtime





###############################################################################
##### Package wget, custom scripts, cleanup
###############################################################################

echo "* Package wget"
fCmd opkg install wget

echo "* Package iperf3"
fCmd opkg install iperf3
echo "* Set iperf3 server at startup"
cat << EOF > /etc/rc.local
# Put your custom commands here that should be executed once
# the system init finished. By default this file does nothing.

# Start iperf server
rm -f /var/log/iperf3.log && /usr/bin/iperf3 --server --daemon --logfile /var/log/iperf3.log
exit 0
EOF

echo "* Add custom scripts"

echo '/root/*.sh #required script' >> /etc/sysupgrade.conf
echo '/root/*.env #required environment' >> /etc/sysupgrade.conf
echo '/root/*.conf #required config' >> /etc/sysupgrade.conf
echo '/root/.profile #my profile with opkg update check script' >> /etc/sysupgrade.conf
echo '/root/.bash_colors #shell colors syntax script' >> /etc/sysupgrade.conf


if [ ! -f opkg-downgrade.conf ]; then
  echo "#nfs-kernel-server http://archive.openwrt.org/releases/packages-17.01/$OPENWRT_ARCH/packages/nfs-kernel-server_2.1.1-1_$OPENWRT_ARCH.ipk" > opkg-downgrade.conf
  if [ "$OPENWRT_ARCH" == "arm_cortex-a9_vfpv3" ]; then
    echo "#mwlwifi-firmware-88w8864 https://github.com/eduperez/mwlwifi_LEDE/releases/dvi upownload/31d9386/mwlwifi-firmware-88w8864_20181210-31d93860-1_arm_cortex-a9_vfpv3.ipk" >> opkg-downgrade.conf
    echo "#kmod-mwlwifi kmod-mwlwifi_4.14.162+2018-06-15-8683de8e-1_arm_cortex-a9_vfpv3.ipk" >> opkg-downgrade.conf
  elif [ "$OPENWRT_ARCH" == "mips_24kc" ]; then
    echo "#ath10k-firmware-qca988x-ct http://archive.openwrt.org/releases/18.06.1/packages/mips_24kc/base/ath10k-firmware-qca988x-ct_2018-05-12-952afa49-1_mips_24kc.ipk" >> opkg-downgrade.conf
  fi
fi
echo '/root/*.ipk #upgrade opkg exception packages' >> /etc/sysupgrade.conf


if [ -n "$(uci show | grep "$H_WIFI_SSID")" ]; then
  echo "* Remove Hotspot <$H_WIFI_SSID> as of wan zone"
  # /etc/config/wireless
  uci -q del wireless.wifinet10
  uci commit wireless
  # /etc/config/network
  uci -q del network.hwan
  uci commit network
  # /etc/config/firewall
  uci commit firewall
fi

echo "* Remove duplicated conffile"
find /etc -name *-opkg -print | xargs rm > /dev/null 2>&1

echo "* "
echo "* "
echo "******************************"
echo " /!\ After reboot checks /!\\ "
echo "******************************"
echo "* "
echo "* "
echo "* Please check swap mounted partition http://$HOSTNAME/cgi-bin/luci/admin/system/mounts"
echo "* "
echo "* "
echo "* Get ACME certificates command line to run, if encountered errors during installation!"
echo "* "
if [ $FW_FWD_NAS_CERTS -eq 1 ]; then
  echo "* Certificates issue:"
  echo "/etc/init.d/uhttpd stop; /etc/acme/acme.sh --home /etc/acme --upgrade > /etc/acme/log.txt 2>&1; /root/fw-redirect.sh Allow-http=on Allow-NAS-http=off; /etc/acme/acme.sh --home /etc/acme --issue --server letsencrypt -d $DOMAIN -w /www --keylength 2048 2>&1 | tee -a /etc/acme/log.txt; /root/fw-redirect.sh Allow-http=off Allow-NAS-http=on; /etc/init.d/uhttpd restart 2> /dev/null; /etc/init.d/ipsec restart"
  echo "* "
  echo "* Certificates renew:"
  echo "/etc/init.d/uhttpd stop; /etc/acme/acme.sh --home /etc/acme --upgrade > /etc/acme/log.txt 2>&1; /root/fw-redirect.sh Allow-http=on Allow-NAS-http=off; /etc/acme/acme.sh --home /etc/acme --renew-all --standalone --force 2>&1 | tee -a /etc/acme/log.txt; /root/fw-redirect.sh Allow-http=off Allow-NAS-http=on; /etc/init.d/uhttpd restart 2> /dev/null; /etc/init.d/ipsec restart"
else
  echo "* Certificates issue:"
  echo "/etc/init.d/uhttpd stop; /etc/acme/acme.sh --home /etc/acme --upgrade > /etc/acme/log.txt 2>&1; /root/fw-redirect.sh Allow-http=on; /etc/acme/acme.sh --home /etc/acme --issue --server letsencrypt -d $DOMAIN -w /www --keylength 2048 2>&1 | tee -a /etc/acme/log.txt; /root/fw-redirect.sh Allow-http=off; /etc/init.d/uhttpd restart 2> /dev/null; /etc/init.d/ipsec restart"
  echo "* "
  echo "* Certificates renew:"
  echo "/etc/init.d/uhttpd stop; /etc/acme/acme.sh --home /etc/acme --upgrade > /etc/acme/log.txt 2>&1; /root/fw-redirect.sh Allow-http=on; /etc/acme/acme.sh --home /etc/acme --renew-all --standalone --force 2>&1 | tee -a /etc/acme/log.txt; /root/fw-redirect.sh Allow-http=off; /etc/init.d/uhttpd restart 2> /dev/null; /etc/init.d/ipsec restart"
fi
if [ -f /root/dl-certs_*.sh ]; then
  echo "* "
  echo "* Certificates download:"
  ls /root/dl-certs_*.sh
fi
echo "* "
echo "* "

echo "* End time: $(date)"
runend=$(date +%s)
runtime=$((runend-runstart))
echo "* Elapsed time: $(($runtime / 3600))hrs $((($runtime / 60) % 60))min $(($runtime % 60))sec"

# Rollback Internal Field Separator
IFS=$SAVEIFS

echo -n "* Reboot to complete the installation? [Y/n] "
read answer
if [ -n "$(echo $answer | grep -i '^y')" ] || [ -z "$answer" ]; then
  reboot
fi

exit 0