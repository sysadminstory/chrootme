#/bin/sh


# Show script usage help
echo_usage()
{
	echo "Usage: $0 [-m] [-s <shell>] [-f <file>]"
	echo
	echo "Options:"
	echo "  -m                : do not start the 'chroot' command, only mount the filesystem mount points"
	echo "  -s <string>       : When in chroot mode, start the chosen shell instead of $SHELL."
	echo "  -f <device:path>  : Specify the location (device and path to file) of the fstab file to use."
	echo "                      The device must be specified without the /dev/ folder"
	echo "                      The path to the fstab file is given considering that the specified device is the root"
	echo "                      The device and path are separated by a colon"
	echo "                      Example : The fstab file is located on the device /dev/sda5 and the path to the fstab file on this device is /etc/fstab :"
	echo "                      -f sda5:/etc/fstab"
	echo "  -h, -?            : Show this help message and exit."
	echo
	echo "Example :"
	echo "  This command would start the script in mount only mode :"
	echo "  $0 -m "
	echo 
	echo "Example :"
	echo "  This command will start the script in chroot mode, will use the fstab file located on /dev/sda5 in the path /etc/fstab and will start /bin/zsh :"
	echo "  $0 -s /bin/zsh -f sda5:/etc/fstab"
	exit 1
}



# Get all the block devices present 
get_block_devices()
{
	# Check if lsblk is available ; if not, use /proc/partitions
	which lsblk > /dev/null 2>&1

	if [ $? -eq 0 ]
	then
		BLOCKS=`lsblk --output KNAME --list --noheadings | cut -d" " -f 3`
	else
		# If tr is not available use awk
		which tr > /dev/null 2>&1
		if [ $? -eq 0 ]
		then
			BLOCKS=`cat /proc/partitions | tr -s " " |cut -d" " -f 5`
		else
			BLOCKS=`cat /proc/partitions | awk 'NR>2 {print $4}'`
		fi
	fi
}







# Initialize the /tmp dir and some vars
init_tmp_dir_vars()
{
	# Create the temporary directory, and clean it if necessary
	FINDFOLDER=/tmp/find-fstab
	mkdir -p $FINDFOLDER
	rm -rf $FINDFOLDER/*
	
	# Define the file where the chosen partition / fstab file will be stored
	DEVCHOICE=$FINDFOLDER/dev-choice
	
	# Default mount point used
	MOUNTFOLDER=/mnt

}

# Find all fstab files on all detected block devices
find_fstabs()
{
	
	for DEV in $BLOCKS
	do
		# Try to mount the block device
		echo -n "Trying to find fstab file on /dev/$DEV ..."
		mount /dev/$DEV $MOUNTFOLDER > /dev/null 2>&1
		if [ $? -eq 0 ]
		then
			# Search for fstab files & unmount the block device
			find $MOUNTFOLDER -maxdepth 2 -name fstab -fprint $FINDFOLDER/$DEV
			# Each fstab path is stored in a file named after the block device

			umount $MOUNTFOLDER
			echo " done !"
		else
			echo " failed !"
		fi
	done
}


# Format the file containing the path to fstab files
format_fstab_list()
{
	# Add before each fstab path the device name followed by a colon
	cd $FINDFOLDER
	for DEV in *
	do
		sed -i "s/^\/mnt/$DEV:/g" $DEV
	done
}


# Show the menu to choose the fstab file
show_fstab_menu()
{
	# Test if whiptail or dialog are available
	which whiptail > /dev/null 2>&1
	WHIPTAIL=$?
	which dialog > /dev/null 2>&1
	DIALOG=$?

	# If dialog or whiptail is available, use it to show the menu
	if [ $WHIPTAIL -eq 0 ]
	then
		MENU=whiptail
		show_dialog
		return
	fi

	if [ $DIALOG -eq 0 ]
	then
		MENU=dialog
		show_dialog
		return
	fi
	
	# If neither whiptail or dialog is available, show a full textual menu

	local DEVCHOICE
	until [ "$INVALID" = 0 ]
	do
		clear
		echo " +--------------------------------+"
		echo " | Choose which fstab file to use |"
		echo " +--------------------------------+"
		echo ""
		echo "Please select the fstab file corresponding to your local system  :"
		echo " Format : device:/path/to/fstab"
		echo ""
		echo "List of found fstab files :"
		FSTABITEMS=`cat $FINDFOLDER/* | sort`

		MENUID=1
		for line in $FSTABITEMS
		do
			echo "\t[$MENUID] $line"
			MENUID=$(($MENUID+1))
		done
		echo "\t[$MENUID] Quit"

		read -p "Enter the number between the brackets corresponding to your local fstab file : " CHOIX
		# If the user enters a valid choice, use it
		if [ $CHOIX -ge 1 -a $CHOIX -le $MENUID ]
		then
			INVALID=0
		else
			read -p "Invalid choice ! Press a key to continue" CRAP
		fi

		# If the user chooses to quit then exit
		if [ "$CHOIX" -eq "$MENUID" ]
		then
			echo "Exiting !"
			exit 1
		fi

		# Store the device:path according to the user choice
		cat $FINDFOLDER/* | sort | sed ${CHOIX}!d > $DEVCHOICE
		
	done
}




# Use the dialog or whiptail command to let the user choose the fstab file
show_dialog()
{
	# Establish the list of menu items
	FSTABITEMS=`(cat $FINDFOLDER/* && cat $FINDFOLDER/*) | sort `

	# Show the menu : whiptail and dialog use the same syntax
	$MENU --title "Choice of fstab file of the local system" --noitem --clear --backtitle "Chrootme 0.1" --menu "Please choose the partition and fstab file to use to mount your local system :" 20 60 10 $FSTABITEMS 2>$DEVCHOICE
	if [ $? -ne 0 ]
	then 
		echo "Exiting !"
		exit 1
	fi
}

# Mount all block devices contained in the selected fstab file
mount_fstab()
{
	# Getg the value the user chose in the menu
	FSTABLOCATION=`cat $DEVCHOICE`

	echo "Trying to use the file $FSTABLOCATION to mount the local system :"

	# Split the choice in device and path
	DEV=`echo $FSTABLOCATION | cut -d":" -f 1`
	LOCATION=`echo $FSTABLOCATION | cut -d":" -f 2-`

	
	# Define the location of the temporary fstab file, and the sanitized fstab file
	FINALFSTAB=$FINDFOLDER/fstab
	SANEFSTAB=$FINDFOLDER/fstab-sane

	# Mount the device containing the fstab file, copy it, and unmount the device
	mount /dev/$DEV $MOUNTFOLDER
	cp $MOUNTFOLDER$LOCATION $FINALFSTAB
	umount $MOUNTFOLDER
	
	# Sanitize the fstab file by removing comments
	grep -v "^#" $FINALFSTAB > $SANEFSTAB
	
	# Read each line of the fstab file, try to mount the device to the corresponding mount points, using the option set in the fstab file
	cat $SANEFSTAB | while read DEVICE MOUNTPOINT TYPE OPTION DUMP PASS
	do
		if [ "$MOUNTPOINT" != "none" ]
		then
			# Try to mount the device
			echo -n "Trying to mount $DEVICE on $MOUNTPOINT ..."
			mount $DEVICE $MOUNTFOLDER/$MOUNTPOINT -t $TYPE -o $OPTION > /dev/null 2>&1
			if [ $? -eq 0 ]
			then
				echo " done !"
			else
				echo " failed !"
			fi
		else
			echo "Ignoring swap device $DEVICE"
		fi
	done
}

# Start the chroot
start_chroot()
{
	# Mount the missing /proc & /sys & /dev folders :
	mount -t proc proc $MOUNTFOLDER/proc
	mount -t sysfs sys $MOUNTFOLDER/sys
	mount -o bind /dev $MOUNTFOLDER/dev

	echo ""
	echo "********************************************************************************"
	echo " Welcome in your local system chrooted on $MOUNTFOLDER"
	echo "********************************************************************************"
	echo ""
	echo "To leave the chrooted environment, just type exit or logout !"
	echo "Good luck fixing your local system !"
	echo ""
	echo ""

	# Start the user-chosen shell instead of the actual shell
	if [ "$STARTING_SHELL" ]
	then
		echo "Starting $STARTING_SHELL"
		chroot $MOUNTFOLDER $STARTING_SHELL
	# Start the actual shell
	else
		echo "Starting $SHELL"
		chroot $MOUNTFOLDER
	fi
}

# Unmount devices after the chroot session ends
stop_chroot()
{
	echo -n "Trying to unmount local system ..."
	umount `cat /proc/mounts | grep $MOUNTFOLDER | cut -d" " -f 2 | sort -r`
	echo " done !"
}


# Start the selected script mode : mount only or chroot
start_selected_scriptmode()
{
	if [ "$MOUNT_ONLY" -eq 1 ]
	then
		start_mount_only
	else
		start_chroot
		stop_chroot
	fi
}

# Start the mount-only mode
start_mount_only()
{

	echo ""
	echo "********************************************************************************"
	echo " Your local system was mounted in $MOUNTFOLDER"
	echo "********************************************************************************"
	echo ""
	echo "You can explore and modify your local system in the following folder :"
	echo "$MOUNTFOLDER"
	echo ""
	echo "Good luck fixing your local system !"
	echo ""
	echo ""
}

# 
fstab_locate_mode()
{
	if [ $CMDFSTABLOCATION ]
	then
		echo "User-defined fstab location : $ARGFSTABLOCATION"
		echo $CMDFSTABLOCATION > $DEVCHOICE
	else
		
		get_block_devices
		find_fstabs
		format_fstab_list
		show_fstab_menu
	fi
	
}

# Initialize the temporary directory and variables
init_tmp_dir_vars

# Set default values for the command args variables
MOUNT_ONLY=0
STARTING_SHELL=
CMDFSTABLOCATION=

# Argument handling
while getopts ms:f:h? OPT
do
	case $OPT in
		m)	MOUNT_ONLY=1;;
		s)	STARTING_SHELL=$OPTARG;;
		f)	CMDFSTABLOCATION=$OPTARG;;
		\?|h)	echo_usage;;
	esac
done

fstab_locate_mode
mount_fstab
start_selected_scriptmode
