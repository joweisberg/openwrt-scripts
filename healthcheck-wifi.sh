#!/bin/sh
#
# crontab -e
# # Check wifi devices every 1 min
# */1 * * * * /root/healthcheck-wifi.sh
#

FILE_PATH=$(readlink -f $(dirname $0))  #/root
FILE_NAME=$(basename $0)                #healthcheck-wifi.sh
FILE_NAME=${FILE_NAME%.*}               #healthcheck-wifi
FILE_DATE=$(date +'%Y%m%d-%H%M%S')
FILE_LOG="/var/log/$FILE_NAME.log"

###############################################################################
### Functions

function fSendMail() {
  local MSG_HEAD=$1 MSG_BODY=$2
  echo -e "Subject: [$HOSTNAME@$DOMAIN] Healthcheck WiFi\n\n$MSG_HEAD\n\n$MSG_BODY" | msmtp $(id -un)
  #echo -e "$MSG_HEAD\n\n$MSG_BODY" | mailx -s "[$HOSTNAME@$DOMAIN] Healthcheck WiFi" -- $(whoami)
}

###############################################################################
### Environment Variables

# Source under this script directory
cd $(readlink -f $(dirname $0))
[ -f .env ] && source ./.env

# Local Variables
CHECK_DEV=${CHECK_DEV:-radio0|radio1}
DEV_UPDATED=0

###############################################################################
### Pre-Script

if [ ! -f /tmp/healthcheck-wifi.dev ]; then
  echo "* Start time: $(date)" | tee $FILE_LOG
  echo "* List of WiFi device(s) to monitor: " | tee -a $FILE_LOG
  echo $CHECK_DEV | tr "|" "\n" | tee -a $FILE_LOG
  echo "* " | tee -a $FILE_LOG

  echo $CHECK_DEV | tr "|" "\n" > /tmp/healthcheck-wifi.dev
  # Add | at the end of line
  sed -i 's/$/|PASSED/' /tmp/healthcheck-wifi.dev
fi

# Clean previous old files
[ -f ./healthcheck.reboot ] && [ "$(cat ./healthcheck.reboot)" != "$(date +'%Y%m%d')" ] && rm -f ./healthcheck.reboot && rm -f ./healthcheck-wifi.mail

###############################################################################
### Script

for DEV in $(echo $CHECK_DEV | tr "|" "\n"); do
  DEV_MSG=$(iwinfo $DEV info | awk '/Master  Channel/{print $4}')
  if [ "$DEV_MSG" != "unknown" ]; then
    # Move from FAILED to PASSED
    if [ $(cat /tmp/healthcheck-wifi.dev | grep "$DEV|FAILED" | wc -l) -eq 1 ]; then
      DEV_UPDATED=1
      echo "[$(date +'%Y-%m-%d %H:%M:%S')] WiFi device is up $DEV => Channel: $DEV_MSG" | tee -a $FILE_LOG
    fi
    
    sed -i "s#^$DEV|.*#$DEV|PASSED|$DEV_MSG#g" /tmp/healthcheck-wifi.dev

  elif [ $(cat /tmp/healthcheck-wifi.dev | grep "$DEV|PASSED" | wc -l) -eq 1 ]; then
    # Move from PASSED to FAILED
    DEV_UPDATED=1
    sed -i "s#^$DEV|.*#$DEV|FAILED|$DEV_MSG#g" /tmp/healthcheck-wifi.dev
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] WiFi device is down $DEV => Channel: $DEV_MSG" | tee -a $FILE_LOG

    echo "[$(date +'%Y-%m-%d %H:%M:%S')] WiFi device is restarting $DEV..." | tee -a $FILE_LOG
    
    # uci set wireless.radio0.disabled='1'
    uci set wireless.$DEV.disabled='1'
    # uci set wireless.default_radio0.disabled='1'
    # uci set wireless.wifinet0.disabled='1'
    for UCI_DEV in $(uci show wireless | grep ".device='$DEV'" | cut -d'=' -f1 | sed 's/.device//g'); do uci set $UCI_DEV.disabled='1'; done
    uci commit wireless
    wifi down $DEV > /dev/null
    
    sleep 3
    
    # uci set wireless.radio0.disabled='0'
    uci set wireless.$DEV.disabled='0'
    # uci set wireless.default_radio0.disabled='0'
    # uci set wireless.wifinet0.disabled='0'
    for UCI_DEV in $(uci show wireless | grep ".device='$DEV'" | cut -d'=' -f1 | sed 's/.device//g'); do uci set $UCI_DEV.disabled='0'; done
    uci commit wireless
    wifi up $DEV > /dev/null
    
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Waiting for device to be up $DEV..." | tee -a $FILE_LOG
    sleep 30
    
    DEV_MSG=$(iwinfo $DEV info | awk '/Master  Channel/{print $4}')
    if [ "$DEV_MSG" != "unknown" ]; then
      DEV_UPDATED=0
      echo "[$(date +'%Y-%m-%d %H:%M:%S')] WiFi device is up $DEV => Channel: $DEV_MSG" | tee -a $FILE_LOG
      sed -i "s#^$DEV|.*#$DEV|PASSED|$DEV_MSG#g" /tmp/healthcheck-wifi.dev
      
    else
      echo "[$(date +'%Y-%m-%d %H:%M:%S')] WiFi device can't be restarted, is still down $DEV => Channel: $DEV_MSG" | tee -a $FILE_LOG
    fi
  fi
done

# Send a mail if no error detected after a reboot
[ $DEV_UPDATED -eq 0 ] && [ -f ./healthcheck.reboot ] && [ "$(cat ./healthcheck.reboot)" == "$(date +'%Y%m%d')" ] && [ ! -f ./healthcheck-wifi.mail ] && echo "$(date +'%Y%m%d')" > ./healthcheck-wifi.mail && fSendMail "WiFi device(s) are up and running." "$(cat /tmp/healthcheck-wifi.dev | awk -F'|' '{print $1" => Channel: "$3}' ORS='\n')"

# Check all devices when changes are detected
if [ $DEV_UPDATED -eq 1 ]; then
  DEV_UPDATED=0

  if [ $(cat /tmp/healthcheck-wifi.dev | grep "FAILED" | wc -l) -gt 0 ]; then
  
    # Try to reboot only one time per day to solve the issue
    if [ ! -f ./healthcheck.reboot ] || [ "$(cat ./healthcheck.reboot)" != "$(date +'%Y%m%d')" ]; then
      echo "[$(date +'%Y-%m-%d %H:%M:%S')] WiFi device(s) are down, rebooting..." | tee -a $FILE_LOG
      echo "$(date +'%Y%m%d')" > ./healthcheck.reboot
      fSendMail "WiFi device(s) are down!" "$(cat /tmp/healthcheck-wifi.dev | awk -F'|' '{print $1" => Channel: "$3}' ORS='\n')\n\nKernel Log:\n$(dmesg | head -n20)\n\nRebooting..."
      reboot
      exit 1
    fi
    fSendMail "WiFi device(s) are down!" "$(cat /tmp/healthcheck-wifi.dev | awk -F'|' '{print $1" => Channel: "$3}' ORS='\n')\n\nKernel Log:\n$(dmesg | head -n20)"
    
  else
    [ -f ./healthcheck.reboot ] && [ "$(cat ./healthcheck.reboot)" != "$(date +'%Y%m%d')" ] && rm -f ./healthcheck.reboot
    fSendMail "WiFi device(s) are up and running." "$(cat /tmp/healthcheck-wifi.dev | awk -F'|' '{print $1" => Channel: "$3}' ORS='\n')"
  fi
fi

exit 0
