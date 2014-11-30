chrootme
========

Small script to mount and chroot a local system (using a recue CD or Image)

Usage
=====

    wget --no-check-certificate "https://raw.githubusercontent.com/sysadminstory/chrootme/master/chrootme.sh" -O "chrootme.sh" && sh chrootme.sh
or
    
    curl -k -o "chrootme.sh" "https://raw.githubusercontent.com/sysadminstory/chrootme/master/chrootme.sh" && sh chrootme.sh

Requirements
============
To run this tool, you will need to be able to get the file on your system, and you will need those utilities :
- sh
- cat
- tr or awk
- mkdir
- rm
- mount
- umount
- sed
- cp
- grep
- sort

There are optional tools used by this script :
- lsblk
- whiptail or dialog
