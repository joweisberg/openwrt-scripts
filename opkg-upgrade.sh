#!/bin/sh
#
# Upgrade packages with specific ipk
#
# crontab -e
# # Packages upgrade daily @05:55
# 55 5 * * * /root/opkg-upgrade.sh
#
# Launch command:
# /root/opkg-upgrade.sh --auto
# /root/opkg-upgrade.sh --manual
#

FILE_PATH=$(readlink -f $(dirname $0))  #/root
FILE_NAME=$(basename $0)                #opkg-upgrade.sh
FILE_NAME=${FILE_NAME%.*}               #opkg-upgrade
FILE_DATE=$(date +'%Y%m%d-%H%M%S')
FILE_LOG="/var/log/$FILE_NAME.log"
FILE_LOG_ERRORS="/var/log/$FILE_NAME-errors.log"

###############################################################################
### Functions

function fSendMail() {
  local MSG_HEAD=$1 MSG_BODY=$2
  echo -e "Subject: [$HOSTNAME@$DOMAIN] Upgrade\n\n$MSG_HEAD\n\n$MSG_BODY" | msmtp $(id -un)
  #echo -e "$MSG_HEAD\n\n$MSG_BODY" | mailx -s "[$HOSTNAME@$DOMAIN] Upgrade" -- $(whoami)
}

###############################################################################
### Environment Variables

source /etc/os-release

# Source environment variables
cd $FILE_PATH
if [ -f ./opkg-install.env ]; then
  source ./opkg-install.env
fi

###############################################################################
### Pre-Script

REBOOT=0
UPG_AUTO=1
[ $# -gt 0 ] && ([ "$1" == "-m" ] || [ "$1" == "--manual" ]) && UPG_AUTO=0

###############################################################################
### Script

runstart=$(date +%s)
rundate="$(date)"
echo "* Start time: $(date)" | tee $FILE_LOG

# Free buffers cache (pagecache, dentries and inodes)
free > /dev/null 2>&1 && sync && echo 3 > /proc/sys/vm/drop_caches

rm -Rf /var/opkg-lists/*
echo "* " | tee -a $FILE_LOG
echo "* Checking for updates, please wait..." | tee -a $FILE_LOG
opkg update > /dev/null

opkgStatus=""
opkgDowngradeOn=0
opkgDowngradeList=""
opkgDowngradeNb=0
if [ -f ./opkg-downgrade.conf ]; then
  opkgDowngradeList=$(cat ./opkg-downgrade.conf | grep -v '^#' | cut -d' ' -f1 | xargs | sed -e 's/ /|/g')
  opkgDowngradeNb=$(cat ./opkg-downgrade.conf | grep -v '^#' | cut -d' ' -f1 | wc -l)
  
  if [ $UPG_AUTO -eq 0 ] && [ $opkgDowngradeNb -gt 0 ]; then
    echo "* "
    echo -n "* Downgrade these packages <$opkgDowngradeList>? [y/N] "
    read answer
    if [ -n "$(echo $answer | grep -i '^y')" ]; then
      opkgDowngradeOn=1

      cat ./opkg-downgrade.conf | while read line
      do
        # Skip line starts with #
        if [ -n "$(echo $line | grep -v '^#')" ]; then
          pkg_name=$(echo $line | cut -d' ' -f1)
          pkg_url=$(echo $line | cut -d' ' -f2)
          # Evaluate variable inside the url
          pkg_url=$(eval echo $pkg_url)
          
          if [ -n "$(echo $pkg_url | grep $OPENWRT_ARCH)" ]; then
            if [ -n "$(echo $pkg_url | grep '^http')" ]; then
              rm -f $pkg_name*.ipk
              echo "* Downloading $pkg_url"
              wget --no-check-certificate -q --timeout=5 $pkg_url
            else
              echo "* Using $pkg_url"
            fi
            echo "* Installing package $pkg_name"
            opkg install --force-downgrade $pkg_name*.ipk
            find /etc -name *-opkg -print | xargs rm > /dev/null 2>&1
          else
            echo "* Skipping $pkg_name... Not compatible with $OPENWRT_ARCH!"
          fi
        fi
      done
    fi
    echo "* "
  fi
  
elif [ $UPG_AUTO -eq 0 ]; then
  echo "* File not found: $(pwd)/opkg-downgrade.conf"
  echo "* "
fi


rm -f $FILE_LOG_ERRORS

opkgInstalled="$(opkg list-installed 2> /dev/null | wc -l)"
opkgUpgradable=$(opkg list-upgradable 2> /dev/null | wc -l)
opkgUpgradable=$(($opkgUpgradable - $opkgDowngradeNb))
echo "* Packages installed: $opkgInstalled" | tee -a $FILE_LOG
echo "* Packages upgradable: $opkgUpgradable" | tee -a $FILE_LOG
if [ $opkgUpgradable -gt 0 ]; then
  echo "* " | tee -a $FILE_LOG
  
  if [ $opkgDowngradeNb -eq 0 ]; then
    echo "* Running full opkg upgrade" | tee -a $FILE_LOG
    # Running in backgroud
    #(opkg list-upgradable | cut -d' ' -f1 | xargs opkg upgrade && find /etc -name *-opkg -print | xargs rm > /dev/null 2>&1 && rm -f /tmp/opkgCheckDate.txt)&

    # Print upgradable packages list
    opkg list-upgradable | cut -d' ' -f1 | sed 's/^/- /' | tee -a $FILE_LOG
    # Do the packages upgrade
    opkg list-upgradable | cut -d' ' -f1 | xargs opkg upgrade > /dev/null 2> $FILE_LOG_ERRORS

    # Fix packages install issue
    if [ -f $FILE_LOG_ERRORS ] && [ $(cat $FILE_LOG_ERRORS | grep "check_data_file_clashes" | wc -l) -gt 0 ]; then
      # * check_data_file_clashes: Package openwrt-keyring wants to install file /etc/opkg/keys/f94b9dd6febac963
      cat $FILE_LOG_ERRORS | awk '/Package/{print $4}' | sed 's/^/- /' | sed 's/$/ (f)/'
      opkg install --force-reinstall $(cat $FILE_LOG_ERRORS | awk '/Package/{print $4}')
      REBOOT=1
    fi
    if [ -f $FILE_LOG_ERRORS ] && [ $(cat $FILE_LOG_ERRORS | grep "opkg_install_cmd" | wc -l) -gt 0 ]; then
      #  * opkg_install_cmd: Cannot install package openwrt-keyring.
      cat $FILE_LOG_ERRORS | awk '/Cannot install package/{print $6}' | sed 's/\.//g' | sed 's/^/- /' | sed 's/$/ (f)/'
      opkg install --force-reinstall $(cat $FILE_LOG_ERRORS | awk '/Cannot install package/{print $6}' | sed 's/\.//g')
      REBOOT=1
    fi

    if [ $? -ne 0 ]; then
      echo "* " | tee -a $FILE_LOG
      echo "* Retrying upgrade..." | tee -a $FILE_LOG
      opkg list-upgradable | cut -d' ' -f1 | xargs opkg upgrade 2>> $FILE_LOG
    fi
  else
    echo "* Running partial opkg upgrade and skipping <$opkgDowngradeList>" | tee -a $FILE_LOG
    # Running in backgroud
    #(opkg list-upgradable | cut -d' ' -f1 | grep -vE "$opkgDowngradeList" | xargs opkg upgrade && find /etc -name *-opkg -print | xargs rm > /dev/null 2>&1 && rm -f /tmp/opkgCheckDate.txt)&

    # Print upgradable packages list
    opkg list-upgradable | cut -d' ' -f1 | grep -vE "$opkgDowngradeList" | sed 's/^/- /' | tee -a $FILE_LOG
    # Do the packages upgrade
    opkg list-upgradable | cut -d' ' -f1 | grep -vE "$opkgDowngradeList" | xargs opkg upgrade > /dev/null 2> $FILE_LOG_ERRORS

    # Fix packages install issue
    if [ -f $FILE_LOG_ERRORS ] && [ $(cat $FILE_LOG_ERRORS | grep "check_data_file_clashes" | wc -l) -gt 0 ]; then
      # * check_data_file_clashes: Package openwrt-keyring wants to install file /etc/opkg/keys/f94b9dd6febac963
      cat $FILE_LOG_ERRORS | awk '/Package/{print $4}' | sed 's/^/- /' | sed 's/$/ (f)/'
      opkg install --force-reinstall $(cat $FILE_LOG_ERRORS | awk '/Package/{print $4}')
      REBOOT=1
    fi
    if [ -f $FILE_LOG_ERRORS ] && [ $(cat $FILE_LOG_ERRORS | grep "opkg_install_cmd" | wc -l) -gt 0 ]; then
      #  * opkg_install_cmd: Cannot install package openwrt-keyring.
      cat $FILE_LOG_ERRORS | awk '/Cannot install package/{print $6}' | sed 's/\.//g' | sed 's/^/- /' | sed 's/$/ (f)/'
      opkg install --force-reinstall $(cat $FILE_LOG_ERRORS | awk '/Cannot install package/{print $6}' | sed 's/\.//g')
      REBOOT=1
    fi

    if [ $? -ne 0 ]; then
      echo "* " | tee -a $FILE_LOG
      echo "* Retrying upgrade..." | tee -a $FILE_LOG
      opkg list-upgradable | cut -d' ' -f1 | grep -vE "$opkgDowngradeList" | xargs opkg upgrade 2>> $FILE_LOG
    fi
  fi

  if [ $? -eq 0 ]; then
    opkgStatus="Upgrade completed."
    echo "* $opkgStatus" | tee -a $FILE_LOG
  else
    opkgStatus="Upgrade ending with errors!"
    echo "* $opkgStatus" | tee -a $FILE_LOG
  fi

  echo "* " | tee -a $FILE_LOG
  echo "* Remove duplicated conffile" | tee -a $FILE_LOG
  find /etc -name *-opkg -print | xargs rm > /dev/null 2>&1
  rm -f /tmp/opkgCheckDate.txt

elif [ $opkgDowngradeOn -eq 1 ]; then
  opkgStatus="Downgrade completed."
  echo "* " | tee -a $FILE_LOG
  echo "* $opkgStatus" | tee -a $FILE_LOG
else
  opkgStatus="OpenWrt is up to date."
  echo "* " | tee -a $FILE_LOG
  echo "* $opkgStatus" | tee -a $FILE_LOG
fi


# Free buffers cache (pagecache, dentries and inodes)
free > /dev/null 2>&1 && sync && echo 3 > /proc/sys/vm/drop_caches

# Clean unused commands
sed -i '/acme start/d' /etc/crontabs/root


#if [ $opkgUpgradable -gt 0 ] || [ $opkgDowngradeOn -eq 1 ] || [ $REBOOT -eq 1 ]; then
if [ $REBOOT -eq 1 ]; then
  if [ $UPG_AUTO -eq 1 ]; then
    echo "* " | tee -a $FILE_LOG
    echo "* " | tee -a $FILE_LOG
    echo "* " | tee -a $FILE_LOG
    echo "* Rebooting to complete the upgrade..." | tee -a $FILE_LOG
    REBOOT=1
  else
    echo "* "
    echo "* "
    echo "* "
    echo -n "* Reboot to complete the upgrade? [Y/n] "
    read answer
    if [ -n "$(echo $answer | grep -i '^y')" ] || [ -z "$answer" ]; then
      REBOOT=1
    fi
  fi
fi

echo "* " | tee -a $FILE_LOG
echo "* End time: $(date)" | tee -a $FILE_LOG
runend=$(date +%s)
runtime=$((runend-runstart))
echo "* Elapsed time: $(($runtime / 3600))hrs $((($runtime / 60) % 60))min $(($runtime % 60))sec" | tee -a $FILE_LOG

if [ $UPG_AUTO -eq 1 ] && ( [ $opkgUpgradable -gt 0 ] || [ $opkgDowngradeOn -eq 1 ] ); then
  [ -f $FILE_LOG ] && fSendMail "$opkgStatus\nOS: $OPENWRT_RELEASE" "$(cat $FILE_LOG | grep -Ev "^Downloading|^Configuring|resolve_conffiles|^\.|^$")"
fi

if [ $REBOOT -eq 1 ]; then
  reboot
fi
exit 0
