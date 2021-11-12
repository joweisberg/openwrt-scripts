#!/bin/sh
#
# crontab -e
# # Check NAS status and Port Forwards http/https every 3 mins
# */3 * * * * /root/healthcheck-nas.sh
#

FILE_PATH=$(readlink -f $(dirname $0))  #/root
FILE_NAME=$(basename $0)                #healthcheck-nas.sh
FILE_NAME=${FILE_NAME%.*}               #healthcheck-nas
FILE_DATE=$(date +'%Y%m%d-%H%M%S')
FILE_LOG="/var/log/$FILE_NAME.log"

###############################################################################
### Functions

function fSendMail() {
  local MSG_HEAD=$1 MSG_BODY=$2
  echo -e "Subject: [$HOSTNAME@$DOMAIN] Healthcheck NAS\n\n$MSG_HEAD\n\n$MSG_BODY" | msmtp $(id -un)
  #echo -e "$MSG_HEAD\n\n$MSG_BODY" | mailx -s "[$HOSTNAME@$DOMAIN] Healthcheck NAS" -- $(whoami)
}

###############################################################################
### Environment Variables

# Source environment variables
cd $FILE_PATH
if [ -f ./opkg-install.env ]; then
  source ./opkg-install.env
fi

# Local Variables
CHECK_URL=${CHECK_NAS:-http://$HOSTNAME}
URL_UPDATED=0
URL_PASSED=""

###############################################################################
### Pre-Script

if [ ! -f /tmp/healthcheck-nas.dev ]; then
  echo "* Start time: $(date)" | tee $FILE_LOG
  echo "* List of NAS to monitor: " | tee -a $FILE_LOG
  echo $CHECK_URL | tr "|" "\n" | tee -a $FILE_LOG
  echo "* " | tee -a $FILE_LOG

  echo $CHECK_URL | tr "|" "\n" > /tmp/healthcheck-nas.dev
  # Add | at the end of line
  sed -i 's/$/|PASSED/' /tmp/healthcheck-nas.dev
fi

###############################################################################
### Script

for URL in $(echo $CHECK_URL | tr "|" "\n"); do
  URL_MSG=$(curl -sSf --insecure --max-time 3 $URL 2>&1)
  URL_RET=$?
  
  if [ $URL_RET -eq 0 ]; then
    # Move from FAILED to PASSED
    if [ $(cat /tmp/healthcheck-nas.dev | grep "$URL|" | grep "FAILED" | wc -l) -eq 1 ]; then
      URL_UPDATED=1
      if [ -z "$URL_PASSED" ]; then URL_PASSED="$URL\n\t=> is up and running."; else URL_PASSED="$URL_PASSED\n$URL\n\t=> is up and running."; fi
      echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] URL is up \t$URL" | tee -a $FILE_LOG
    fi
    
    sed -i "s#^$URL|.*#$URL|PASSED#g" /tmp/healthcheck-nas.dev

  # curl: (28) Operation timed out after 3000 milliseconds with 0 bytes received
  elif [ $URL_RET -eq 28 ] && [ $(cat /tmp/healthcheck-nas.dev | grep "$URL|" | grep -E "PASSED|WAITING" | wc -l) -eq 1 ]; then
    # Move from PASSED to WAITING or FAILED
    
    WAIT_NB=$(cat /tmp/healthcheck-nas.dev | grep "$URL|" | awk -F'|' '/WAITING/{print $3}')
    [ -z "$WAIT_NB" ] && WAIT_NB=0
    WAIT_NB=$((WAIT_NB + 1))
    
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] URL is down \t$URL \n\t=> Error: $URL_MSG" | tee -a $FILE_LOG
    # Waiting for 3 * 180 sec before to raise an alert
    if [ $WAIT_NB -lt 4 ]; then
      # Move from PASSED to WAITING
      sed -i "s#^$URL|.*#$URL|WAITING|$WAIT_NB|$(date +'%Y-%m-%d %H:%M:%S')|$URL_MSG#g" /tmp/healthcheck-nas.dev
    else
      # Move from PASSED to FAILED
      URL_UPDATED=1
      sed -i "s#^$URL|.*#$URL|FAILED|$(date +'%Y-%m-%d %H:%M:%S')|$URL_MSG#g" /tmp/healthcheck-nas.dev
    fi
    
  elif [ $(cat /tmp/healthcheck-nas.dev | grep "$URL|" | grep "PASSED" | wc -l) -eq 1 ]; then
    # Move from PASSED to FAILED
    URL_UPDATED=1
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] URL is down \t$URL \n\t=> Error: $URL_MSG" | tee -a $FILE_LOG
    sed -i "s#^$URL|.*#$URL|FAILED|$(date +'%Y-%m-%d %H:%M:%S')|$URL_MSG#g" /tmp/healthcheck-nas.dev
  fi
done
  
# Check all URLs
if [ $URL_UPDATED -eq 1 ]; then
  URL_UPDATED=0
  [ $(cat /tmp/healthcheck-nas.dev | grep "FAILED" | wc -l) -gt 0 ] && fSendMail "NAS updated status and Port Forwards http/https changed to $HOSTNAME router!" "$(cat /tmp/healthcheck-nas.dev | grep "FAILED" | awk -F'|' '{print $1" \n\t=> Date: "$3" \n\t=> Error: "$4}' ORS='\n')\n$URL_PASSED" || fSendMail "NAS updated status and Port Forwards http/https is back." "$URL_PASSED"
  URL_PASSED=""

  # Change Port Forwards http/https to the router (FAILED) or to the NAS (PASSED)
  [ $(cat /tmp/healthcheck-nas.dev | grep "FAILED" | wc -l) -gt 0 ] && /root/fw-redirect.sh Allow-http=on Allow-https=on Allow-NAS-http=off Allow-NAS-https=off || /root/fw-redirect.sh Allow-http=off Allow-https=off Allow-NAS-http=on Allow-NAS-https=on
fi

exit 0
