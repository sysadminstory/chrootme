#/bin/sh

# Gets all the block devices present 
get_block_devices()
{
	# Check if lsblk is available ; if not, use /proc/partitions
	which lsblk > /dev/null 2>&1

	if [ $? -eq 0 ]
	then
		BLOCKS=`lsblk --output KNAME --list --noheadings | cut -d" " -f 3`
	else
		# if tr is not available use awk
		which tr > /dev/null 2>&1
		if [ $? -eq 0 ]
		then
			BLOCKS=`cat /proc/partitions | tr -s " " |cut -d" " -f 5`
		else
			BLOCKS=`cat /proc/partitions | awk 'NR>2 {print $4}'`
		fi
	fi
}







# Init the /tmp dir and some vars
init_tmp_dir_vars()
{
	# Création de répertoire temporaire et nettoyage pour stocker la liste des fichiers
	FINDFOLDER=/tmp/find-fstab
	mkdir -p $FINDFOLDER
	rm -rf $FINDFOLDER/*
	
	# On définit le chemin du fichier contenant le résultat du choix de partition / fichier
	DEVCHOICE=$FINDFOLDER/dev-choice
	
	# Chemin de montage par défaut
	MOUNTFOLDER=/mnt

	FSTABS=""
}

# Finds all fstab file on all detected block devices
find_fstabs()
{
	
	for DEV in $BLOCKS
	do
		# Try to mount the block device
		echo -n "Trying to find fstab file on /dev/$DEV ..."
		mount /dev/$DEV $MOUNTFOLDER > /dev/null 2>&1
		if [ $? -eq 0 ]
		then
			# Search for fstab files & unmounting the block device
			find $MOUNTFOLDER -name fstab -fprint $FINDFOLDER/$DEV
			# Each fstab path is stored in a file named as the block device

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
	# Add before each fstab path the device name followed by colon
	cd $FINDFOLDER
	for DEV in *
	do
		sed -i "s/^\/mnt/$DEV:/g" $DEV
	done
}

#DEBUG: echo "Liste des fichiers fstab trouvés :"
#DEBUG: cat -n $FINDFOLDER/* | column -t -s :

# Show the menu to choose the fstab file
show_menu()
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
	
	# If none of whiptail or dialog are available, show a full textual menu

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

		# If the user choose to quit then exit
		if [ "$CHOIX" -eq "$MENUID" ]
		then
			echo "Exiting !"
			exit 1
		fi

		# Storing the device:path according to the user choice
		cat $FINDFOLDER/* | sort | sed ${CHOIX}!d > $DEVCHOICE
		
	done
}




# Use the dialog or whiptail command to let the user choose the fstab file
show_dialog()
{
	# Establishing the list of menu itemps
	FSTABITEMS=`(cat $FINDFOLDER/* && cat $FINDFOLDER/*) | sort `

	# Showing the menu : whiptail and dialog use the same syntax
	$MENU --title "Choix du fichier fstab racine" --noitem --clear --backtitle "Chrootme 0.1" --menu "Veuillez choisir la partition et le fichier fstab à utiliser pour monter votre système local :" 20 60 10 $FSTABITEMS 2>$DEVCHOICE
	if [ $? -ne 0 ]
	then 
		echo "Exiting !"
		exit 1
	fi
}

# Mount all block device contained in the selected fstab file
mount_fstab()
{
	# Getting the value the user choosed in the menu
	FSTABLOCATION=`cat $DEVCHOICE`

	echo "Trying to use the file $FSTABLOCATION to mount the local system :"

	# Splitting the choice in device and path
	DEV=`echo $FSTABLOCATION | cut -d":" -f 1`
	LOCATION=`echo $FSTABLOCATION | cut -d":" -f 2-`

	
	# Define the location of the temporary fstab file, and the sanitized fstab file
	FINALFSTAB=$FINDFOLDER/fstab
	SANEFSTAB=$FINDFOLDER/fstab-sane

	# Mount the device containing the fstab file, copy it, and unmount the device
	mount /dev/$DEV $MOUNTFOLDER
	cp $MOUNTFOLDER$LOCATION $FINALFSTAB
	umount $MOUNTFOLDER
	
	# Sanitizing thr fstab file by removing comments
	grep -v "^#" $FINALFSTAB > $SANEFSTAB
	
	# Reading each line of the fstab file, try tu mount the device to the corresponding mount points, using the option set in the fstab file
	cat $SANEFSTAB | while read DEVICE MOUNTOINT TYPE OPTION DUMP PASS
	do
		# Trying to mount the device
		echo -n "Trying to mount $DEVICE on $MOUNTOINT ..."
		mount $DEVICE $MOUNTFOLDER/$MOUNTOINT -t $TYPE -o $OPTION > /dev/null 2>&1
		if [ $? -eq 0 ]
		then
			echo " done !"
		else
			echo " failed !"
		fi
	done
}

# Start the chroot
start_chroot()
{
	# Mounting the missing /proc & /sys & /dev folders :
	mount -t proc proc $MOUNTFOLDER/proc
	mount -t sysfs sys $MOUNTFOLDER/sys
	mount -o bind /dev $MOUNTFOLDER/dev

	echo ""
	echo "********************************************************************************"
	echo " Welcome in your local system chrooted on $MOUNTFOLDER"
	echo "********************************************************************************"
	echo ""
	echo "To leave the chrooted environement, juste type exit or logout !"
	echo "Good luck fixing your local system !"
	echo ""
	echo ""
	
	chroot $MOUNTFOLDER
}

stop_chroot()
{
	echo -n "Trying to unmount local system ..."
	umount `cat /proc/mounts | grep $MOUNTFOLDER | cut -d" " -f 2 | sort -r`
	echo " done !"
}

get_block_devices
init_tmp_dir_vars
find_fstabs
format_fstab_list
show_menu
mount_fstab
start_chroot
stop_chroot
