#!/bin/sh
#
# Check internet status
# Define aliases
# Show OS informations
#

# Check internet status
echo
wget -q --spider http://www.google.com 2> /dev/null
if [ $? -eq 0 ]; then  # if Google website is available we update
  echo "You are connected to the internet."
else
  echo "You are not connected to the internet."
fi

# Define shell aliases
alias ll="ls -alh"
alias osinfo="~/os-info.sh"

# Show OS informations and status
echo
echo -n "* Show OS informations and status? [y/N] "
read answer
if [ -n "$(echo $answer | grep -i '^y')" ]; then
  ~/os-info.sh
else
  echo "* You can use 'osinfo' command alias later."
  echo
fi
