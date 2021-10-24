#!/bin/sh
#
# crontab -e
# # Check LTE connection every 3 mins
# */3 * * * * /root/healthcheck-wwan.sh
#

INTERFACE="wwan"

FILE_PATH=$(readlink -f $(dirname $0))  #/root
FILE_NAME=$(basename $0)                #healthcheck.sh
FILE_NAME=${FILE_NAME%.*}               #healthcheck
FILE_DATE=$(date +'%Y%m%d-%H%M%S')
FILE_LOG="/var/log/$FILE_NAME.log"

###############################################################################
### Functions

###############################################################################
### Environment Variables

OFFLINE_COUNT=$(cat $FILE_LOG | tail -4 | grep OFFLINE | wc -l)
OFFLINE_COUNT_TRESHOLD=4

LINES_MAX=2160      # Keep 3 days of log
LINES_MIN=300       # Check every 2 mins on 12h: 360 times
LINES_COUNT=$(wc -l $FILE_LOG | awk '{print $1}')

###############################################################################
### Pre-Script

# if the log files gets huge, strip it, keep last LINES_MIN lines
if [ $LINES_COUNT -ge $LINES_MAX ]; then
   echo "$(tail -$LINES_MIN $FILE_LOG)" > $FILE_LOG
fi

###############################################################################
### Script

# DNS test, it's result defines the ONLINE/OFFLINE state
IP_TO_PING=8.8.8.8
IP_PACKET_COUNT=3
ONLINE=0
for i in $(seq 1 $IP_PACKET_COUNT); do
  ping -q -W 1 -c 3 $IP_TO_PING > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    ONLINE=1
  fi
done

if [ $ONLINE -eq 0 ]; then
  echo "Ooops, we're offline!"

  if [ $OFFLINE_COUNT -ge $OFFLINE_COUNT_TRESHOLD ]; then
    echo ">> Restarting router..."

    echo "$(date) > TOO MANY OFFLINE TRYOUTS" >> $FILE_LOG
    echo "$(date) > GOING TO REBOOT NOW" >> $FILE_LOG
    echo "$(date) > NOW!" >> $FILE_LOG
    echo "$(date) > SORRY FOR ANY INCONVENIENCE." >> $FILE_LOG
    reboot
    exit 0

  else
    echo ">> Restarting interface..."
    
    echo "$(date) OFFLINE > RESTARTING INTERFACE" >> $FILE_LOG
    logger -s "INTERNET KEEP ALIVE SYSTEM: Restarting the LTE interface."
    ifdown $INTERFACE
    sleep 2
    ifup $INTERFACE

  fi
else
  echo "We're okay!"
  echo "$(date) ONLINE" >> $FILE_LOG
fi

exit 0
