#!/bin/sh
#
# https://eko.one.pl/?p=openwrt-openvpntun#dostpdosiecilanklienta
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

# Source under this script directory
cd $(readlink -f $(dirname $0))
source ./.env

LOCAL_DOMAIN="${DOMAIN%%.*}"
NETADDR=${IPADDR%.*}
IPADDR_GTW=${IPADDR_GTW:-$IPADDR}
BRIDGED_AP=${BRIDGED_AP:-0}

###############################################################################
### Script
###############################################################################

echo "* Package VPN client with OpenVPN"
fCmd opkg install openvpn-openssl openvpn-easy-rsa luci-app-openvpn
echo "* Set OpenVPN config files"
uci -q del openvpn.sample_server
uci -q del openvpn.sample_client
uci -q del openvpn.custom_config


export EASYRSA_PKI="/etc/easy-rsa/pki"
export EASYRSA_REQ_CN="OpenWrt"
export EASYRSA_BATCH=1
# Certificate will expired in 1000 years
export EASYRSA_CA_EXPIRE=365000
export EASYRSA_CERT_EXPIRE=365000

if [ ! -f $EASYRSA_PKI/ca.crt ]; then
  echo "* Build certificates with easy-rsa"
  echo -e "\t* Remove and re-initialize the PKI directory (1/6)"
  easyrsa init-pki
  echo -e "\t* Generate DH parameters (2/6)"
  easyrsa gen-dh > /dev/null 2>&1
  echo -e "\t* Create a new CA (3/6)"
  easyrsa build-ca nopass > /dev/null 2>&1
  echo -e "\t* Generate a key pair and sign locally for server (4/6)"
  easyrsa build-server-full server nopass > /dev/null 2>&1
  echo -e "\t* Generate a key pair and sign locally for client (5/6)"
  easyrsa build-client-full client nopass > /dev/null 2>&1
  echo -e "\t* Generate TLS PSK (6/6)"
  openvpn --genkey --secret $EASYRSA_PKI/tc.pem > /dev/null 2>&1
fi

echo "* Set OpenVPN certificates files with network & firewall config"
OVPN_KEYS="/etc/openvpn/keys"
mkdir -p $OVPN_KEYS
sed -e "/^#/d;/^\w/N;s/\n//" $EASYRSA_PKI/tc.pem > $OVPN_KEYS/tc.key
ln -sf $EASYRSA_PKI/ca.crt $OVPN_KEYS/ca.crt
ln -sf $EASYRSA_PKI/dh.pem $OVPN_KEYS/dh2048.pem
openssl x509 -in $EASYRSA_PKI/issued/server.crt -out $EASYRSA_PKI/issued/server.crt
ln -sf $EASYRSA_PKI/issued/server.crt $OVPN_KEYS/server.crt
ln -sf $EASYRSA_PKI/private/server.key $OVPN_KEYS/server.key
openssl x509 -in $EASYRSA_PKI/issued/client.crt -out $EASYRSA_PKI/issued/client.crt
ln -sf $EASYRSA_PKI/issued/client.crt $OVPN_KEYS/client.crt
ln -sf $EASYRSA_PKI/private/client.key $OVPN_KEYS/client.key

# Add automatically vpn user
rm -f /etc/openvpn/authpass.txt
# VPN_USER="username|password"
for L in $(cat .env | grep "^VPN_USER="); do
  # Get the value after =
  V=${L#*=}
  # Evaluate variable inside the line
  V=$(eval echo $V)
  # Remove " from string
  #V=${V//\"}
  
  # Username:Password
  echo "$(echo $V | cut -d'|' -f1):$(echo $V | cut -d'|' -f2)" >> /etc/openvpn/authpass.txt
done

cat << 'EOF' > /etc/openvpn/authpass
#!/bin/sh
#
# https://github.com/troydm/ovpnauth.sh/blob/master/ovpnauth.sh
#

fname=$(basename $0)
conffile="/etc/openvpn/authpass.txt"
logfile="/var/log/openvpn-authpass.log"

log(){
  #echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a $logfile
  # Fri May 28 15:49:06 2021 [authpass] OpenVPN authentication successfull: username
  # Wed Jun  2 17:13:16 2021 [authpass] OpenVPN authentication successfull: username
  #echo "$(date +"%a %b %d %T %Y" | xargs printf "%s %s %2.f %s %4d\n") [$fname] $1" | tee -a $logfile
  echo "$(date +"%Y-%m-%d %T") [$fname] $1" | tee -a $logfile
}

md5(){
  echo "$1.$(uname -n)" > /tmp/$$.md5calc
  sum="$(md5sum /tmp/$$.md5calc | awk '{print $1}')"
  rm /tmp/$$.md5calc
  log "$sum"
}

if [ "$1" == "" ] || [ "$1" == "help" ]; then
  log "authpass v0.1 - OpenVPN sh authentication script with simple user db"
  log "                   for use with auth-user-pass-verify via-file option"
  log ""
  log "help - prints help"
  log "md5 password - to compute password md5 checksum"
  exit 1
fi

if [ "$1" == "md5" ]; then
  log $(md5 $2)
  exit 1
fi

envr="$(echo $(env))"
userpass=$(cat $1)
username=$(echo $userpass | awk '{print $1}')
password=$(echo $userpass | awk '{print $2}')

# Computing password md5
#password=$(md5 $password)
userpass=$(cat $conffile | grep $username: | awk -F: '{print $2}')

if [ "$password" == "$userpass" ]; then
  log "OpenVPN authentication successfull: $username"
  log $envr
  exit 0
fi

log "OpenVPN authentication failed: $username"
log $(cat $1)
log $envr
exit 1
EOF
chmod +x /etc/openvpn/authpass

# Generate client OpenVPN config import file
cat << EOF > /etc/openvpn/client.ovpn
client
dev tun
proto udp
remote $DOMAIN 1194
remote-cert-tls server
resolv-retry 5
nobind
auth-nocache
auth-user-pass
script-security 2

<ca>
$(cat $OVPN_KEYS/ca.crt)
</ca>

<cert>
$(cat $OVPN_KEYS/client.crt)
</cert>

<key>
$(cat $OVPN_KEYS/client.key)
</key>

<tls-crypt>
$(cat $OVPN_KEYS/tc.key)
</tls-crypt>
EOF

# Expose client config for uHTTPd
mkdir -p /www/openvpn
ln -sf /etc/openvpn/client.ovpn /www/openvpn/client.ovpn

i=0
# Set OpenVPN server config
uci -q del openvpn.server
uci set openvpn.server=openvpn
uci set openvpn.server.enabled='1'
uci set openvpn.server.port='1194'
uci set openvpn.server.proto='udp'
uci set openvpn.server.dev="tun$i"
uci set openvpn.server.ca="$OVPN_KEYS/ca.crt"
uci set openvpn.server.cert="$OVPN_KEYS/server.crt"
uci set openvpn.server.key="$OVPN_KEYS/server.key"
uci set openvpn.server.dh="$OVPN_KEYS/dh2048.pem"
uci set openvpn.server.tls_crypt="$OVPN_KEYS/tc.key"
uci set openvpn.server.auth_user_pass_verify='/etc/openvpn/authpass via-file'
uci set openvpn.server.script_security='2'
uci set openvpn.server.tls_server='1'
uci set openvpn.server.server='10.10.1.0 255.255.255.0'
uci set openvpn.server.topology=subnet
uci set openvpn.server.keepalive='10 120'
uci set openvpn.server.log='/var/log/openvpn.log'
uci set openvpn.server.verb='3'
uci set openvpn.server.mute='5'

# Options to push to clients
uci -q del openvpn.server.push
uci add_list openvpn.server.push="route $NETADDR.0 255.255.255.0"
uci add_list openvpn.server.push="dhcp-option DNS $IPADDR"
uci add_list openvpn.server.push="dhcp-option DOMAIN $LOCAL_DOMAIN"

# Redirect all customer traffic through the vpn tunnel
uci add_list openvpn.server.push='redirect-gateway def1'

uci commit openvpn

# Add vpn interface
uci set network.ovpn_server=interface
uci set network.ovpn_server.proto='none'
uci set network.ovpn_server.device="tun$i"
uci set network.ovpn_server.auto='1'
uci commit network

# Add vpn zone
# firewall.@zone[3].name='vpn'
I=$(echo "$(uci show firewall | grep ".name='vpn'")" | awk -F'[][]' '{print $2}')
if [ -z "$I" ]; then
  # Add new zone
  uci add firewall zone
  uci set firewall.@zone[-1]=zone
  uci set firewall.@zone[-1].name='vpn'
  uci set firewall.@zone[-1].network='ovpn_server'
  uci set firewall.@zone[-1].input='ACCEPT'
  uci set firewall.@zone[-1].output='ACCEPT'
  uci set firewall.@zone[-1].forward='ACCEPT'
  uci set firewall.@zone[-1].masq='1'
else
  # Add network on existing zone
  uci add_list firewall.@zone[$I].network='ovpn_server'
fi
uci commit firewall

# Add vpn forwarding
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='vpn'
uci set firewall.@forwarding[-1].dest='lan'
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='vpn'
uci set firewall.@forwarding[-1].dest='wan'
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='lan'
uci set firewall.@forwarding[-1].dest='vpn'
uci commit firewall

# Open OpenVPN port
uci add firewall rule
uci set firewall.@rule[-1]=rule
uci set firewall.@rule[-1].name='Allow-OpenVPN'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].dest_port='1194'
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall




if [ -n "$(cat .env | grep "^VPN_CLIENT=")" ]; then

  echo "* Set OpenVPN server Site-to-Site config"

  i=$((i+1))
  # Set OpenVPN server Site-to-Site config
  uci -q del openvpn.server_s2s
  uci set openvpn.server_s2s=openvpn
  uci set openvpn.server_s2s.enabled='1'
  uci set openvpn.server_s2s.port='1195'
  uci set openvpn.server_s2s.proto='udp'
  uci set openvpn.server_s2s.dev="tun$i"
  uci set openvpn.server_s2s.ca="$OVPN_KEYS/ca.crt"
  uci set openvpn.server_s2s.cert="$OVPN_KEYS/server.crt"
  uci set openvpn.server_s2s.key="$OVPN_KEYS/server.key"
  uci set openvpn.server_s2s.dh="$OVPN_KEYS/dh2048.pem"
  uci set openvpn.server_s2s.tls_crypt="$OVPN_KEYS/tc.key"
  uci set openvpn.server_s2s.auth_user_pass_verify='/etc/openvpn/authpass via-file'
  uci set openvpn.server_s2s.script_security='2'
  uci set openvpn.server_s2s.up='/etc/openvpn/dnsmasq-update'
  uci set openvpn.server_s2s.down='/etc/openvpn/dnsmasq-update'
  uci set openvpn.server_s2s.tls_server='1'
  uci set openvpn.server_s2s.server='10.10.2.0 255.255.255.0'
  uci set openvpn.server_s2s.client_to_client='1'
  uci set openvpn.server_s2s.persist_tun='1'
  uci set openvpn.server_s2s.persist_key='1'
  uci set openvpn.server_s2s.keepalive='10 120'
  uci set openvpn.server_s2s.log='/var/log/openvpn-s2s.log'
  uci set openvpn.server_s2s.verb='3'
  uci set openvpn.server_s2s.mute='5'

  mkdir -p /etc/openvpn/ccd
  uci set openvpn.server_s2s.client_config_dir='/etc/openvpn/ccd'
  uci -q del openvpn.server_s2s.route
  # VPN_CLIENT="username|network|local_domain|dns_server"
  for L in $(cat .env | grep "^VPN_CLIENT="); do
    # Get the value after =
    V=${L#*=}
    # Evaluate variable inside the line
    V=$(eval echo $V)
    # Remove " from string
    #V=${V//\"}
    
    CLIENT="$(echo $V | cut -d'|' -f1)"
    CL_NETADDR="$(echo $V | cut -d'|' -f2)"
    
    echo -e "\t* Generate a key pair and sign locally for Client $CLIENT"
    easyrsa build-client-full $CLIENT nopass > /dev/null 2>&1

    echo -e "\t* Set certificates files for Client $CLIENT"
    openssl x509 -in $EASYRSA_PKI/issued/$CLIENT.crt -out $EASYRSA_PKI/issued/$CLIENT.crt
    ln -sf $EASYRSA_PKI/issued/$CLIENT.crt $OVPN_KEYS/$CLIENT.crt
    ln -sf $EASYRSA_PKI/private/$CLIENT.key $OVPN_KEYS/$CLIENT.key

    echo -e "\t* Add client route $CL_NETADDR/24"
    echo -e "ifconfig-push 10.10.2.0 255.255.255.0\niroute $CL_NETADDR 255.255.255.0" > /etc/openvpn/ccd/$CLIENT
    uci add_list openvpn.server_s2s.route="$CL_NETADDR 255.255.255.0"

    echo -e "\t* Generate OpenVPN Client $CLIENT config import file"
    cat << EOF > /etc/openvpn/client_$CLIENT.ovpn
client
dev tun
proto udp
remote $DOMAIN 1195
remote-cert-tls server
resolv-retry 5
nobind
auth-nocache
auth-user-pass /etc/openvpn/$DOMAIN.auth
script-security 2
up /etc/openvpn/dnsmasq-update
down /etc/openvpn/dnsmasq-update
log /var/log/openvpn-$DOMAIN.log
verb 3
mute 5

<ca>
$(cat $OVPN_KEYS/ca.crt)
</ca>

<cert>
$(cat $OVPN_KEYS/$CLIENT.crt)
</cert>

<key>
$(cat $OVPN_KEYS/$CLIENT.key)
</key>

<tls-crypt>
$(cat $OVPN_KEYS/tc.key)
</tls-crypt>
EOF

    echo -e "\t* Expose OpenVPN Client $CLIENT config for uHTTPd"
    ln -sf /etc/openvpn/client_$CLIENT.ovpn /www/openvpn/$CLIENT.ovpn
    
  done

  # Options to push to clients
  uci -q del openvpn.server_s2s.push
  uci add_list openvpn.server_s2s.push="route $NETADDR.0 255.255.255.0"
  uci add_list openvpn.server_s2s.push="dhcp-option DNS $IPADDR"
  uci add_list openvpn.server_s2s.push="dhcp-option DOMAIN $LOCAL_DOMAIN"
  uci add_list openvpn.server_s2s.push='persist-tun'
  uci add_list openvpn.server_s2s.push='persist-key'
  
  uci commit openvpn

  # Add vpn interface
  uci set network.ovpn_server_s2s=interface
  uci set network.ovpn_server_s2s.proto='none'
  uci set network.ovpn_server_s2s.device="tun$i"
  uci set network.ovpn_server_s2s.auto='1'
  uci commit network

  # Add vpn zone
  # firewall.@zone[3].name='vpn'
  I=$(echo "$(uci show firewall | grep ".name='vpn'")" | awk -F'[][]' '{print $2}')
  uci add_list firewall.@zone[$I].network='ovpn_server_s2s'
  uci commit firewall
  
  # Open OpenVPN port
  uci add firewall rule
  uci set firewall.@rule[-1]=rule
  uci set firewall.@rule[-1].name='Allow-OpenVPN-s2s'
  uci set firewall.@rule[-1].src='wan'
  uci set firewall.@rule[-1].proto='udp'
  uci set firewall.@rule[-1].dest_port='1195'
  uci set firewall.@rule[-1].target='ACCEPT'
  uci commit firewall
  
  # Accept DNS queries from others hosts
  uci set dhcp.@dnsmasq[0].localservice='0'
  uci commit dhcp

fi




# Add custom OpenVPN Client Site config files
if [ -n "$(cat .env | grep "^VPN_SITE=")" ] && [ $BRIDGED_AP -eq 0 ]; then

  echo "* Set OpenVPN Client Site config"

  # VPN_SITE="https://ejw.root.sx/openvpn/jdwt.root.sx.ovpn|username|password"
  for L in $(cat .env | grep "^VPN_SITE="); do
    # Get the value after =
    V=${L#*=}
    # Evaluate variable inside the line
    V=$(eval echo $V)
    # Remove " from string
    #V=${V//\"}
    
    V_CFG="$(echo $V | cut -d'|' -f1)"
    V_USR="$(echo $V | cut -d'|' -f2)"
    V_PWD="$(echo $V | cut -d'|' -f3)"
    
    # Retreive the config file from url
    F_FULLNAME=$(basename $V_CFG)
    F_NAME=${F_FULLNAME%.*}
    # Remove all characters before @, and the delimiter too
    #F_NAME=$(echo $F_NAME | sed 's/^.*\(@.*\)/\1/g' | sed 's/\@//g')
    # Remove username from config file
    # F_NAME=jdwt.root.sx@ejw.root.sx.ovpn --> ejw.root.sx.ovpn
    F_NAME=$(echo $F_NAME | sed "s/$V_USR\@//g")
    F_EXT=${F_FULLNAME##*.}
    F_FULLPATH=/etc/openvpn/$F_NAME.$F_EXT
    
    echo -e "\t* Downloading config file from $V_CFG"
    wget --no-check-certificate -qO$F_FULLPATH $V_CFG

    NAME=$F_NAME
    #NAME=my_expressvpn_france_-_paris_-_1_udp.ovpn
    # Remove "my_" at the beginning
    NAME=$(echo $NAME | sed 's/^my_//g')
    # Remove "_udp" at the end
    NAME=$(echo $NAME | sed 's/_udp$//g')
    # Remove "-"
    NAME=$(echo $NAME | sed 's/-//g')
    # Remove "_"
    NAME=$(echo $NAME | sed 's/_//g')
    # Remove "."
    NAME=$(echo $NAME | sed 's/\.//g')
    #NAME=expressvpnfranceparis1

    echo -e "\t* Update config file for OpenWrt device"
    i=$((i+1))
    # Align tun with local interface id
    sed -i "s/^dev tun.*/dev tun$i/g" $F_FULLPATH

    # Set username/password .auth file
    sed -i "s#^auth-user-pass.*#auth-user-pass /etc/openvpn/$F_NAME.auth#g" $F_FULLPATH
    [ ! -f /etc/openvpn/$F_NAME.auth ] && echo -e "$V_USR\n$V_PWD" > /etc/openvpn/$F_NAME.auth
    
    # Update log file
    sed -i "s#^log .*#log /var/log/openvpn-$NAME.log#g" $F_FULLPATH
    
    echo -e "\t* Add Client Site config $NAME"

    uci set openvpn.$NAME=openvpn
    uci set openvpn.$NAME.enabled='1'
    uci set openvpn.$NAME.config=$F_FULLPATH

    # /etc/config/network
    uci set network.vpn_$NAME=interface
    uci set network.vpn_$NAME.proto='none'
    uci set network.vpn_$NAME.device="tun$i"
    uci set network.vpn_$NAME.auto='1'

    # /etc/config/firewall
    #uci add_list firewall.@zone[1].network='ovpn_server'
    if [ -n "$(cat /etc/config/firewall | grep 'ovpn_server')" ]; then
      #sed -i "s/vpn$((i-1))/vpn$((i-1)) vpn$i/g" /etc/config/firewall
      sed -i "s/\tlist network 'ovpn_server'/\tlist network 'ovpn_server'\n\tlist network 'vpn_$NAME'/g" /etc/config/firewall
    #else
    #  uci add firewall zone
    #  uci set firewall.@zone[-1]=zone
    #  uci set firewall.@zone[-1].name='vpn'
    #  uci set firewall.@zone[-1].network="vpn$i"
    #  uci set firewall.@zone[-1].input='ACCEPT'
    #  uci set firewall.@zone[-1].output='ACCEPT'
    #  uci set firewall.@zone[-1].forward='ACCEPT'
    #  uci set firewall.@zone[-1].masq='1'
    #  uci commit firewall
    fi

  done
  
  uci commit firewall
  uci commit network
  uci commit openvpn
  
  # Accept DNS queries from others hosts
  uci set dhcp.@dnsmasq[0].localservice='0'
  uci commit dhcp

fi




# Add dnsmasq update script
cat << 'EOF' > /etc/openvpn/dnsmasq-update
#!/bin/sh
#
# Parses DHCP options from openvpn to update dnsmasq server
# To use set as 'up' and 'down' script in your openvpn *.conf:
# up /etc/openvpn/dnsmasq-update
# down /etc/openvpn/dnsmasq-update
#
# Example envs set from openvpn:
# foreign_option_1='dhcp-option DNS 193.43.27.132'
# foreign_option_2='dhcp-option DNS 193.43.27.133'
# foreign_option_3='dhcp-option DOMAIN be.bnc.ch'
# foreign_option_4='dhcp-option DOMAIN-SEARCH bnc.local'
#

function fLog() {
  # Fri May 28 15:49:06 2021 [dnsmasq-update] Start up
  # Wed Jun  2 17:13:16 2021 [dnsmasq-update] Start up
  #echo "$(date +"%a %b %d %T %Y" | xargs printf "%s %s %2.f %s %4d\n") [$fname] $1"
  echo "$(date +"%Y-%m-%d %T") [$fname] $1"
}

fname=$(basename $0)

fLog "Start $script_type"

case $script_type in
  up)
    OPT_DNS=$(env | awk -F'=' '/^foreign_option_.*=dhcp-option.*DNS/{print $2}' | cut -d' ' -f3)
    OPT_DOM=$(env | awk -F'=' '/^foreign_option_.*=dhcp-option.*DOMAIN/{print $2}' | cut -d' ' -f3)

    fLog "Remove previous DNS and domain provided by VPN server"
    uci -q del dhcp.@dnsmasq[0].rebind_domain
    uci -q del dhcp.@dnsmasq[0].server

    if [ -n "$OPT_DOM" ]; then
      fLog "Use DNS and domain provided by VPN server /$OPT_DOM/$OPT_DNS"
      # uci add_list dhcp.@dnsmasq[0].rebind_domain='ejw'
      # uci add_list dhcp.@dnsmasq[0].server="/ejw/192.168.10.1"
      uci add_list dhcp.@dnsmasq[0].rebind_domain="$OPT_DOM"
      uci add_list dhcp.@dnsmasq[0].server="/$OPT_DOM/$OPT_DNS"
      
    else
      fLog "No dhcp-option value found on env"
      #env

      # VPN_CLIENT="username|network|local_domain|dns_server"
      for L in $(cat /root/.env | grep "^VPN_CLIENT="); do
        # Get the value after =
        V=${L#*=}
        # Evaluate variable inside the line
        V=$(eval echo $V)
        # Remove " from string
        #V=${V//\"}
        
        CLIENT="$(echo $V | cut -d'|' -f1)"
        CL_NETADDR="$(echo $V | cut -d'|' -f2)"
        CL_DOMAIN="$(echo $V | cut -d'|' -f3)"
        CL_DNS="$(echo $V | cut -d'|' -f4)"
        
        OPT_DOM=$CL_DOMAIN
        OPT_DNS=$CL_DNS
        
        fLog "Use DNS and domain provided by /root/.env /$OPT_DOM/$OPT_DNS"
        # uci add_list dhcp.@dnsmasq[0].rebind_domain='ejw'
        # uci add_list dhcp.@dnsmasq[0].server="/ejw/192.168.10.1"
        uci add_list dhcp.@dnsmasq[0].rebind_domain="$OPT_DOM"
        uci add_list dhcp.@dnsmasq[0].server="/$OPT_DOM/$OPT_DNS"
      done
    fi
    
    uci commit dhcp
    /etc/init.d/dnsmasq restart > /dev/null 2>&1
    ;;
  
  down)
    fLog "Remove DNS and domain provided by VPN server"
    uci -q del dhcp.@dnsmasq[0].rebind_domain
    uci -q del dhcp.@dnsmasq[0].server
    uci commit dhcp
    /etc/init.d/dnsmasq restart > /dev/null 2>&1
    ;;
esac

fLog "End $script_type"

exit 0
EOF
chmod +x /etc/openvpn/dnsmasq-update


echo "$EASYRSA_PKI #OpenVPN certificates" >> /etc/sysupgrade.conf
echo '/etc/openvpn #OpenVPN config files' >> /etc/sysupgrade.conf


# Rollback Internal Field Separator
IFS=$SAVEIFS

exit 0