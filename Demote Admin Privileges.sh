#!/bin/bash

####################################################################################################
#
# SCRIPT: Demote Admin Privileges
# AUTHOR: Sam Mills (github.com/sgmills)
# DATE:   09 May 2022
# REV:    2.0
#
####################################################################################################
#
# Description
#   This script is triggered from your MDM by the PrivilegedDemoter tool. If a user has been admin
#	for more than 15 minutes, they will be reminded to use standard user rights and offered the
#	option to remain admin or demote themselves.
#
#	Events to elevate privileges or demote are logged at /var/log/privileges.log.
#
####################################################################################################
# EDITABLE VARIABLES #

# All variables may be set as parameters if using Jamf Pro
# If not using Jamf Pro, set the values here

# Set to "1" in order to enable the help button
# Leave blank or set to "0" to disable the help button.
help_button_status="${4}"

# Set the help button type
# link: trigger the url defined in the payload
# infopopup: shows an info pop-up with text
help_button_type="${5}"

# Set the help button payload
# A URL for link type or text for infopopup type
help_button_payload="${6}"

# Set to 0 in order to disable the notification sound
# Leave blank or set to 1 to enable notification sounds
notification_sound="${7}"

# Enter an administrator's username to exclude from demotion
# Leave blank to allow demotion for all users
admin_to_exclude="${8}"

# Enter the path to IBM Notifier if it is not standard.
# Leave blank to use default location of /Applications/IBM Notifier.app
ibm_notifier_path="${9}"

# Check for IBM Notifier path in parameter 9. If blank, set default path
if [ ! "$ibm_notifier_path" ]; then
	ibm_notifier_path="/Applications/IBM Notifier.app"
fi


####################################################################################################
# USE CAUTION EDITING BELOW THIS LINE

# Get the current user
currentUser=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )

# Get machine UDID
UDID=$( ioreg -d2 -c IOPlatformExpertDevice | awk -F\" '/IOPlatformUUID/{print $(NF-1)}' )

# If current user is excluded from demotion, reset timer and exit
if [[ "$currentUser" == "$admin_to_exclude" ]]; then
	echo "Excluded admin user logged in. Will not perform demotion..."
	# Reset timer and exit 0
	rm /tmp/privilegesCheck &> /dev/null
	exit 0
fi

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

# Redirect output to log file and stdout for logging
exec 1> >( tee -a "${privilegesLog}" ) 2>&1	

####################################################################################################
# FUNCTIONS #

# Function to confirm privileges have been changed successfully and log error after 1 retry.
# Takes user as argument $1
confirmPrivileges () {
	
	# If user is still admin, try revoking again using dseditgroup
	if /usr/sbin/dseditgroup -o checkmember -m "${1}" admin &> /dev/null; then
		echo "$stamp Warn: ${1} is still an admin on MachineID: $UDID. Trying again..."
		/usr/sbin/dseditgroup -o edit -d "${1}" -t user admin
		sleep 1
		
		# If user was not sucessfully demoted after retry, write error to log. Otherwise log success.
		if /usr/sbin/dseditgroup -o checkmember -m "${1}" admin &> /dev/null; then
			echo "$stamp Error: Could not demote ${1} to standard on MachineID: $UDID."
		else
			# Successfully demoted with dseditgroup. Need to update dock tile
			# If running, reload dock to display correct privileges tile
			if /usr/bin/pgrep Dock -gt 0; then
				/usr/bin/killall Dock
			fi
			
			# Log that user was successfully demoted.
			echo "$stamp Status: ${1} is now a standard user on MachineID: $UDID."
		fi
		
	else
		# Log that user was successfully demoted.
		echo "$stamp Status: ${1} is now a standard user on MachineID: $UDID."
	fi
	
	# Clean up privilegegs check log file to reset timer
	# Location, must match logFile in "checkPrivileges.sh"
	rm /tmp/privilegesCheck &> /dev/null
}

# Function to prompt with IBM Notifier
prompt_with_ibmNotifier () {
	
	# If help button is enabled, set type and payload
	if [[ $help_button_status = 1 ]]; then
		help_info=("-help_button_cta_type" "${help_button_type}" "-help_button_cta_payload" "${help_button_payload}")
	fi
	
	# Disable sounds if needed
	if [[ $notification_sound = 0 ]]; then
		sound=("-silent")
	fi
	
	# Prompt the user
	prompt_user() {
		button=$( "${ibm_notifier_path}/Contents/MacOS/IBM Notifier" \
		-type "popup" \
		-bar_title "Privileges Reminder" \
		-subtitle "You are currently an administrator on this device.
	
It is recommended to operate as a standard user whenever possible.
		
Do you still require elevated privileges?" \
		-icon_path "/Applications/Privileges.app/Contents/Resources/AppIcon.icns" \
		-main_button_label "No" \
		-secondary_button_label "Yes" \
		"${help_info[@]}" \
		-timeout 120 \
		"${sound[@]}" \
		-position center \
		-always_on_top )
		
		echo "$?"
	}
	
	# Get the user's response
	buttonClicked=$( prompt_user )
}

# Function to prompt with Jamf Helper
prompt_with_jamfHelper () {
	
	# Prompt the user
	prompt_user() {
		button=$( "/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper" \
		-windowType utility \
		-title "Privileges Reminder" \
		-description "You are currently an administrator on this device.
	
It is recommended to operate as a standard user whenever possible.
		
Do you still require elevated privileges?" \
		-alignDescription left \
		-icon "/Applications/Privileges.app/Contents/Resources/AppIcon.icns" \
		-button1 No \
		-button2 Yes \
		-defaultButton 1 \
		-timeout 120 )
		
		echo "$?"
	}
	
	# Get the user's response
	buttonClicked=$( prompt_user )
}

####################################################################################################
# DEMOTE USER #

# If a user is logged in, offer to demote them interactively. Else demote the last user silently
if [[ $currentUser != "" ]]; then
	
	# Get the current user's UID
	currentUserID=$(id -u "$currentUser")
	
	# If current user is an admin, offer to remove rights
	if /usr/sbin/dseditgroup -o checkmember -m "$currentUser" admin &> /dev/null; then
		
		# User with admin is logged in. Ask before removing rights
		# Use IBM Notifier and fall back to jamfHelper if needed
		if [[ -e "${ibm_notifier_path}" ]]; then
			prompt_with_ibmNotifier
		else
			prompt_with_jamfHelper
		fi
		
		# If the user clicked NO (button 0), remove admin rights immidiately
		if [[ $buttonClicked = 0 ]]; then
			# Revoke rights with PrivilegesCLI
			echo "$stamp Decision: $currentUser no longer needs admin rights. Removing rights on MachineID: $UDID now."
			launchctl asuser "$currentUserID" sudo -u "$currentUser" "/Applications/Privileges.app/Contents/Resources/PrivilegesCLI" --remove &> /dev/null
			sleep 1
			
			# Run confirm privileges function with current user.
			confirmPrivileges "$currentUser"
			
			# If the user clicked YES (button 2) leave admin rights in tact
		elif [[ $buttonClicked = 2 ]]; then
			echo "$stamp Decision: $currentUser says they still need admin rights on MachineID: $UDID."
			echo "$stamp Status: Resetting timer and allowing $currentUser to remain an admin on MachineID: $UDID."
			
			# Clean up privilegegs check log file to reset timer
			# Location, must match logFile in "checkPrivileges.sh"
			rm /tmp/privilegesCheck &> /dev/null
			
			# If timeout occured, remove admin rights
		elif [[ $buttonClicked = 4 ]]; then
			echo "$stamp Decision: Timeout occurred. Removing admin rights for $currentUser on MachineID: $UDID now."
			launchctl asuser "$currentUserID" sudo -u "$currentUser" "/Applications/Privileges.app/Contents/Resources/PrivilegesCLI" --remove &> /dev/null
			sleep 1
			
			# Run confirm privileges function with current user.
			confirmPrivileges "$currentUser"
			
			# If unexpected code is returned, log an error
		else
			echo "$stamp Error: Unexpected exit code returned from prompt. User: $currentUser, MachineID: $UDID."
		fi
	else
		# Current user is not an admin
		echo "$stamp Info: $currentUser is not an admin on MachineID: $UDID."
	fi
else
	# Get the last user if current user is not logged in
	lastUser=$( defaults read /Library/Preferences/com.apple.loginwindow lastUserName )
	echo "$stamp Info: No current user. Last user on MachineID: $UDID was $lastUser"
	
	# If last user is excluded from demotion, reset timer and exit
	if [[ "$lastUser" == "$admin_to_exclude" ]]; then
		echo "Last user was excluded admin. Will not perform demotion..."
		# Reset timer and exit 0
		rm /tmp/privilegesCheck &> /dev/null
		exit 0
	fi
	
	# If last user is an admin, remove rights silently
	if /usr/sbin/dseditgroup -o checkmember -m "$lastUser" admin | grep -q "yes"; then
		# No user logged in. Revoke last user's rights
		echo "$stamp Decision: Removing admin rights for $lastUser on MachineID: $UDID silently."
		# Need to use dseditgroup instead of PrivilegesCLI because no user context exists
		/usr/sbin/dseditgroup -o edit -d "$lastUser" -t user admin
		sleep 1
		
		# Run confirm privileges function with last user.
		confirmPrivileges "$lastUser"
	else
		# Last user is not an admin
		echo "$stamp Info: $lastUser is not an admin on MachineID: $UDID."
	fi
fi
