#!/bin/sh
#
# OpenWrt script to enabled/disabled Firewall - Port Forwards
# ~/fw-redirect.sh \'Allow-NAS-http\' off
# ~/fw-redirect.sh \'Allow-http\' on
#

for L in $(uci show firewall | grep @redirect | grep .name=); do
  # firewall.@redirect[1].name='Allow-http'
  # firewall.@redirect[1].enabled='1'
  # Get the value after =
  V=${L#*=}
  if [ "$V" == "$1" ]; then
    I=$(echo "$L" | awk -F'[][]' '{print $2}')

#    echo "* firewall.@redirect[$I].name=$V"
    if [ "$2" == "on" ]; then
#      echo "* firewall.@redirect[$I].enabled='1'"
      uci -q del firewall.@redirect[$I].enabled
    else
#      echo "* firewall.@redirect[$I].enabled='0'"
      uci set firewall.@redirect[$I].enabled='0'
    fi
    break
  fi
done
#echo "* uci commit firewall"
uci commit firewall
#echo "* restart firewall"
fw3 -q restart

exit 0
