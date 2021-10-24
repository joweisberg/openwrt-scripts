#!/bin/sh
#
# Top 10 largest packages details
#

rm -f /tmp/opkg-size.txt
for pkg in $(opkg list-installed | awk '{print $1}'); do echo "$(opkg files $pkg | xargs ls -l 2> /dev/null | awk '{sum += $5}  END {print sum}' | cut -d'.' -f1) $pkg" >> /tmp/opkg-size.txt; done
echo "* "
echo "* Top 10 largest packages size"
echo "* "
cat /tmp/opkg-size.txt | sort -nur | awk '{printf "%.2f MB %s\n", $1 / 1000 / 1000, $2}' | head -n10
echo "* "
echo "* Top 10 largest packages dependencies"
echo "* "
for pkg in $(cat /tmp/opkg-size.txt | sort -nur |  awk '{print $2}' | head -n10); do opkg whatdependsrec $pkg; done
rm -f /tmp/opkg-size.txt

exit 0
