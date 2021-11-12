#!/bin/sh
#
# OpenWrt script to enabled/disabled Firewall - Port Forwards
# ~/fw-redirect.sh Allow-http=off Allow-NAS-http=on
#

for V in "$@"; do
  name=$(echo $V | awk -F= '{print $1}')
  value=$(echo $V | awk -F= '{print $2}')
  
  # firewall.@redirect[1].name='Allow-http'
  # firewall.@redirect[1].enabled='1'
  if [ $(uci show firewall | grep @redirect | grep ".name='$name'") ]; then
    I=$(echo "$L" | awk -F'[][]' '{print $2}')
    
#    echo "* firewall.@redirect[$I].name='$name'"    
    if [ "$value" == "on" ]; then
#      echo "* firewall.@redirect[$I].enabled='1'"
      uci -q del firewall.@redirect[$I].enabled
    else
#      echo "* firewall.@redirect[$I].enabled='0'"
      uci set firewall.@redirect[$I].enabled='0'
    fi
    
  fi
done

#echo "* uci commit firewall"
uci commit firewall
#echo "* restart firewall"
fw3 -q restart

exit 0
