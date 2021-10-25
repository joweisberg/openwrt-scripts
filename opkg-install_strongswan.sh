#!/bin/sh
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

###############################################################################
### Environment Variables
###############################################################################

# Do not interprate sapce in variable
SAVEIFS=$IFS
IFS=$'\n'

# Source environment variables
cd $FILE_PATH
source ./opkg-install.env
LOCAL_DOMAIN="${DOMAIN%%.*}"
NETADDR=${IPADDR%.*}
IPADDR_GTW=${IPADDR_GTW:-$IPADDR}

###############################################################################
### Script
###############################################################################

echo "* UCI config firewall for IKEv2/IPsec VPN server"
uci add firewall rule
uci set firewall.@rule[-1]=rule
uci set firewall.@rule[-1].name='Allow-IPsec-ESP'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].proto='esp'
uci set firewall.@rule[-1].target='ACCEPT'
uci add firewall rule
uci set firewall.@rule[-1]=rule
uci set firewall.@rule[-1].name='Allow-IPsec-AH'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].proto='ah'
uci set firewall.@rule[-1].target='ACCEPT'
uci add firewall rule
uci set firewall.@rule[-1]=rule
uci set firewall.@rule[-1].name='Allow-IPsec-IKE'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].dest_port='500'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].target='ACCEPT'
uci add firewall rule
uci set firewall.@rule[-1]=rule
uci set firewall.@rule[-1].name='Allow-IPsec-NAT-T'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].dest_port='4500'
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall

echo "* UCI config network/interface for IKEv2/IPsec VPN server"
# Add vpn interface
uci set network.ipsec_server=interface
uci set network.ipsec_server.proto='none'
uci set network.ipsec_server.ifname='ipsec0'
uci set network.ipsec_server.auto='1'
uci commit network

echo "* UCI config network/zone for IKEv2/IPsec VPN server"
# Add vpn zone
# firewall.@zone[3].name='vpn'
I=$(echo "$(uci show firewall | grep ".name='vpn'")" | awk -F'[][]' '{print $2}')
if [ -z "$I" ]; then
  # Add new zone
  uci add firewall zone
  uci set firewall.@zone[-1]=zone
  uci set firewall.@zone[-1].name='vpn'
  uci set firewall.@zone[-1].network='ipsec_server'
  uci set firewall.@zone[-1].input='ACCEPT'
  uci set firewall.@zone[-1].output='ACCEPT'
  uci set firewall.@zone[-1].forward='ACCEPT'
  uci set firewall.@zone[-1].masq='1'
else
  # Add network on existing zone
  uci add_list firewall.@zone[$I].network='ipsec_server'
fi
uci commit firewall

echo "* UCI config network/route for IKEv2/IPsec VPN server"
# Add route
uci add network route
uci set network.@route[-1].interface='ipsec_server'
uci set network.@route[-1].target='10.10.3.0'
uci set network.@route[-1].netmask='255.255.255.0'
uci set network.@route[-1].gateway="$IPADDR_GTW"
uci commit network

echo "* UCI config dhcp/dnsmasq for IKEv2/IPsec VPN server"
# Accept DNS queries from others hosts
uci set dhcp.@dnsmasq[0].localservice='0'
uci commit dhcp

if [ -f /etc/acme/$DOMAIN/ca.cer ]; then
  echo "* Link ACME cetificates for IKEv2/IPsec VPN server"
  [ -d /etc/ipsec.d ] && rm -f /etc/ipsec.d/cacerts/acme.ca.cer
  [ -d /etc/ipsec.d ] && find /etc/ipsec.d -name *.pem -print | xargs rm > /dev/null 2>&1
  mkdir -p /etc/ipsec.d/cacerts && ln -sf /etc/acme/$DOMAIN/ca.cer /etc/ipsec.d/cacerts/acme.ca.cer
  mkdir -p /etc/ipsec.d/certs && ln -sf /etc/acme/$DOMAIN/fullchain.cer /etc/ipsec.d/certs/$DOMAIN.cert.pem
  mkdir -p /etc/ipsec.d/private && ln -sf /etc/acme/$DOMAIN/$DOMAIN.key /etc/ipsec.d/private/$DOMAIN.pem
fi

echo "* Package IKEv2/IPsec VPN server with strongSwan"
fCmd opkg install strongswan-full
# Fix missing package in OpenWrt 21.02.0: 
# [KNL] received netlink error: Function not implemented (89)
# [KNL] unable to add SAD entry with SPI ccc321fa
# [IKE] unable to install inbound and outbound IPsec SA (SAD) in kernel
fCmd opkg install strongswan-mod-kernel-libipsec

echo "* Set config files for IKEv2/IPsec VPN server with strongSwan"
cat << EOF > /etc/strongswan.conf
# strongswan.conf - strongSwan configuration file
#
# Refer to the strongswan.conf(5) manpage for details
#
# Configuration changes should be made in the included files

charon {
  threads = 16
  load_modular = yes
  plugins {
    include strongswan.d/charon/*.conf
  }
}

include strongswan.d/*.conf
EOF
cat << EOF > /etc/ipsec.conf
# ipsec.conf - strongSwan IPsec configuration file

config setup
  # Increase debug level
  #charondebug = "all"
  charondebug = "ike 1, knl 1, cfg 0"
  # Allows few simultaneous connections with one user account
  uniqueids=no

conn %default
  # Dead peer detection will ping clients and terminate sessions after timeout
  dpdaction=clear
  dpdtimeout=90s
  dpddelay=30s
  fragmentation=yes
  forceencaps=yes

conn ikev2-eap
  # Create IKEv2 VPN tunnel
  auto=add
  compress=no
  type=tunnel
  keyexchange=ikev2
  reauth=no
  rekey=no
  ike=3des-sha1-modp1024,3des-sha256-modp1024,aes256gcm16-sha256-modp2048!
  esp=3des-sha1,3des-sha256,aes256gcm16-sha256!

  # left - local (server) side
  left=%any
  leftid=@$DOMAIN
  leftauth=pubkey
  leftcert=$DOMAIN.cert.pem # Filename of certificate located at /etc/ipsec.d/certs/
  leftsendcert=always
  leftsubnet=0.0.0.0/0

  # right - remote (client) side
  right=%any
  rightid=%any
  rightauth=eap-mschapv2
  rightsourceip=10.10.3.0/24
  rightdns=$NETADDR.1
  rightsendcert=never
  eap_identity=%identity

EOF
cat << EOF > /etc/ipsec.secrets
# /etc/ipsec.secrets - strongSwan IPsec secrets file

: RSA $DOMAIN.pem
EOF
# Add automatically vpn user
# VPN_USER="username|password"
for L in $(cat ./opkg-install.env | grep "^VPN_USER="); do
  # Get the value after =
  V=${L#*=}
  # Evaluate variable inside the line
  V=$(eval echo $V)
  # Remove " from string
  #V=${V//\"}
  
  # username : EAP "password"
  echo "$(echo $V | cut -d'|' -f1) : EAP \"$(echo $V | cut -d'|' -f2)\"" >> /etc/ipsec.secrets
done

echo "* UCI config remove default firewall - Traffic Rules for IKEv2/IPsec VPN server"
L=$(uci show firewall | grep 'Allow-IPSec-ESP')
if [ -n "$L" ]; then
  I=$(echo "$L" | awk -F'[][]' '{print $2}')
  uci -q del firewall.@rule[$I]
fi
L=$(uci show firewall | grep 'Allow-ISAKMP')
if [ -n "$L" ]; then
  I=$(echo "$L" | awk -F'[][]' '{print $2}')
  uci -q del firewall.@rule[$I]
fi
uci commit firewall

# Rollback Internal Field Separator
IFS=$SAVEIFS

exit 0