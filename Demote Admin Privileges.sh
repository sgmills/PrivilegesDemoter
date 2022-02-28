#!/bin/bash

####################################################################################################
#
# SCRIPT: Demote Admin Privileges
# AUTHOR: Sam Mills (github.com/sgmills)
# DATE:   09 November 2021
# REV:    1.1.0
#
####################################################################################################
#
# Description
#   This script is triggered from Jamf Pro by the PrivilegedDemoter tool. If a user has been admin
#	for more than 15 minutes, they will be reminded to use standard user rights and offered the
#	option to remain admin or demote themselves.
#
#	Events to elevate privileges or demote are logged at /var/log/privileges.log.
#
####################################################################################################
# LOG SETUP #

# Create stamp for logging
stamp="$(date +"%Y-%m-%d %H:%M:%S%z") blog.mostlymac.privileges.demoter"

# Logging location
privilegesLog="/var/log/privileges.log"

# Check if log exists and create if needed
if [[ ! -f "$privilegesLog" ]]; then
	touch "$privilegesLog"
fi

# Get machine UDID
UDID=$( ioreg -d2 -c IOPlatformExpertDevice | awk -F\" '/IOPlatformUUID/{print $(NF-1)}' )

# Redirect output to log file and stdout for jamf logging
exec &>>(tee -a "$privilegesLog")

####################################################################################################
# FUNCTIONS #

# Function to confirm privileges have been changed successfully and log error after 1 retry.
# Takes user as argument $1
function confirmPrivileges () {
	
	# If user is still admin, try revoking again using dseditgroup
	if /usr/sbin/dseditgroup -o checkmember -m "${1}" admin &> /dev/null; then
		echo "$stamp Warn: "${1}" is still an admin on MachineID: $UDID. Trying again..."
		/usr/sbin/dseditgroup -o edit -d "${1}" -t user admin
		sleep 1
		
		# If user was not sucessfully demoted after retry, write error to log. Otherwise log success.
		if /usr/sbin/dseditgroup -o checkmember -m "${1}" admin &> /dev/null; then
			echo "$stamp Error: Could not demote "${1}" to standard on MachineID: $UDID."
		else
			# Successfully demoted with dseditgroup. Need to update dock tile
			# If running, reload dock to display correct privileges tile
			if /usr/bin/pgrep Dock > 0; then
				/usr/bin/killall Dock
			fi
			
			# Log that user was successfully demoted.
			echo "$stamp Status: "${1}" is now a standard user on MachineID: $UDID."
		fi
		
	else
		# Log that user was successfully demoted.
		echo "$stamp Status: "${1}" is now a standard user on MachineID: $UDID."
	fi
	
	# Clean up privilegegs check log file to reset timer
	# Location, must match logFile in "checkPrivileges.sh"
	rm /tmp/privilegesCheck &> /dev/null
}

####################################################################################################
# DEMOTE USER #

# Get the current user
currentUser=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )

# If a user is logged in, offer to demote them interactively. Else demote the last user silently
if [[ $currentUser != "" ]]; then
	
	# Get the current user's UID
	currentUserID=$(id -u "$currentUser")
	
	# If current user is an admin, offer to remove rights
	if /usr/sbin/dseditgroup -o checkmember -m "$currentUser" admin &> /dev/null; then
		
		# User with admin is logged in. Ask before removing rights
		description="You are currently an administrator on this device.

It is recommended to operate as a standard user whenever possible.
	
Do you still require elevated privileges?"
		
		selection=$( launchctl asuser "$currentUserID" sudo -u "$currentUser" \
			"/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper" \
			-windowType utility \
			-title "Privileges Reminder" \
			-description "$description" \
			-alignDescription left \
			-icon "/Applications/Privileges.app/Contents/Resources/AppIcon.icns" \
			-button1 Yes \
			-button2 No \
			-defaultButton 2 \
			-timeout 120 )
		
		# Get the button that was clicked
		buttonClicked="${selection:$i-1}"
		
		# If the user clicked YES reset timer. If they clicked NO or timeout occurred, remove admin rights
		if [[ $buttonClicked = "0" ]]; then
			echo "$stamp Decision: "$currentUser" says they still need admin rights on MachineID: $UDID."
			echo "$stamp Status: Resetting timer and allowing "$currentUser" to remain an admin on MachineID: $UDID."
			
			# Clean up privilegegs check log file to reset timer
			# Location, must match logFile in "checkPrivileges.sh"
			rm /tmp/privilegesCheck &> /dev/null
		else
			# Revoke rights with PrivilegesCLI
			echo "$stamp Decision: "$currentUser" no longer needs admin rights (or timeout occurred). Removing rights on MachineID: $UDID now."
			launchctl asuser "$currentUserID" sudo -u "$currentUser" "/Applications/Privileges.app/Contents/Resources/PrivilegesCLI" --remove &> /dev/null
			sleep 1
			
			# Run confirm privileges function with current user.
			confirmPrivileges "$currentUser"
		fi
	else
		# Current user is not an admin
		echo "$stamp Info: "$currentUser" is not an admin on MachineID: $UDID."
	fi
else
	# Get the last user if current user is not logged in
	lastUser=$( defaults read /Library/Preferences/com.apple.loginwindow lastUserName )
	echo "$stamp Info: No current user. Last user on MachineID: $UDID was "$lastUser""
	
	# Get the last user's UID
	lastUserID=$(id -u "$lastUser")
	
	# If last user is an admin, remove rights silently
	if /usr/sbin/dseditgroup -o checkmember -m "$lastUser" admin | grep -q "yes"; then
		# No user logged in. Revoke last user's rights
		echo "$stamp Decision: Removing admin rights for "$lastUser" on MachineID: $UDID silently."
		# Need to use dseditgroup instead of PrivilegesCLI because no user context exists
		/usr/sbin/dseditgroup -o edit -d "$lastUser" -t user admin
		sleep 1
		
		# Run confirm privileges function with last user.
		confirmPrivileges "$lastUser"
	else
		# Last user is not an admin
		echo "$stamp Info: "$lastUser" is not an admin on MachineID: $UDID."
	fi
fi