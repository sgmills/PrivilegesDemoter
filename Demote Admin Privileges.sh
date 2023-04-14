#!/bin/bash

####################################################################################################
#
# SCRIPT: Demote Admin Privileges
# AUTHOR: Sam Mills (github.com/sgmills)
# DATE:   08 November 2022
# REV:    3.0
#
####################################################################################################
#
# Description
#   This tool reminds users to operate as a standard user. If a given user has had admin privileges
#	for longer than a specific threshold, they will be reminded to use standard user rights. Users
#	are offered the option to remain admin or demote themselves.
#
#	Events to elevate privileges or demote are logged at /var/log/privileges.log.
#
####################################################################################################
# LOG SETUP #

# All privilege events logging location
privilegesLog="/var/log/privileges.log"

# Check if log exists and create if needed
if [ ! -f "$privilegesLog" ]; then
	touch "$privilegesLog"
fi

# Create stamp for logging
stamp="$(date +"%Y-%m-%d %H:%M:%S%z") blog.mostlymac.privileges.demoter"

# Redirect output to log file and stdout for logging
exec 1> >( tee -a "${privilegesLog}" ) 2>&1

####################################################################################################
# SET SCRIPT VARIABLES #

# PrivilegesDemoter managed preferences plist
pdPrefs="/Library/Managed Preferences/blog.mostlymac.privilegesdemoter.plist"

if [[ -e "$pdPrefs" ]]; then
	# Get help button status
	help_button_status="$( /usr/libexec/PlistBuddy -c "print helpButton:helpButtonStatus" "$pdPrefs" 2>/dev/null )"
	
	# Get the help button type
	help_button_type="$( /usr/libexec/PlistBuddy -c "print helpButton:helpButtonType" "$pdPrefs" 2>/dev/null )"
	
	# Get the help button payload
	help_button_payload="$( /usr/libexec/PlistBuddy -c "print helpButton:helpButtonPayload" "$pdPrefs" 2>/dev/null )"
	
	# Get notification sound setting
	notification_sound="$( /usr/libexec/PlistBuddy -c "print ibmNotifierSettings:notificationSound" "$pdPrefs" 2>/dev/null )"
	
	# Are we using IBM Notifer?
	ibm_notifier="$( /usr/libexec/PlistBuddy -c "print notificationAgent:ibmNotifier" "$pdPrefs" 2>/dev/null )"
	
	# Are we using Swift Dialog?
	swift_dialog="$( /usr/libexec/PlistBuddy -c "print notificationAgent:swiftDialog" "$pdPrefs" 2>/dev/null )"
	
	# Get list of excluded admins
	admin_to_exclude="$( /usr/libexec/PlistBuddy -c "print excludedAdmins" "$pdPrefs" 2>/dev/null )"
	
	# Get silent operation setting
	silent="$( /usr/libexec/PlistBuddy -c "print notificationAgent:disableNotifications" "$pdPrefs" 2>/dev/null )"
	
	# Get setting for standalone mode without SAP Privileges
	standalone="$( /usr/libexec/PlistBuddy -c "print standaloneMode" "$pdPrefs" 2>/dev/null )"
	
	# Get main text for notifications. Set to default if not found
	if [[ ! $( /usr/libexec/PlistBuddy -c "print mainText" "$pdPrefs" 2>/dev/null ) ]]; then
		main_text=$( printf "You are currently an administrator on this device.\n\nIt is recommended to operate as a standard user whenever possible.\n\nDo you still require elevated privileges?" )
	else
		get_text="$( /usr/libexec/PlistBuddy -c "print mainText" "$pdPrefs" 2>/dev/null )"
		# Strip out extra slash in new line characters
		main_text=$( printf "${get_text//'\\n'/\n}" )
	fi
	
	# Check for IBM Notifier path. Set to default if not found
	if [[ ! $( /usr/libexec/PlistBuddy -c "print ibmNotifierSettings:ibmNotifierPath" "$pdPrefs" 2>/dev/null ) ]]; then
		ibm_notifier_path="/Applications/IBM Notifier.app"
	else
		ibm_notifier_path="$( /usr/libexec/PlistBuddy -c "print ibmNotifierSettings:ibmNotifierPath" "$pdPrefs" 2>/dev/null )"
	fi
	
	# Check for IBM Notifier custom binary name. Set to default if not found
	if [[ ! $( /usr/libexec/PlistBuddy -c "print ibmNotifierSettings:ibmNotifierBinary" "$pdPrefs" 2>/dev/null ) ]]; then
		ibm_notifier_binary="IBM Notifier"
	else
		ibm_notifier_binary="$( /usr/libexec/PlistBuddy -c "print ibmNotifierSettings:ibmNotifierBinary" "$pdPrefs" 2>/dev/null )"
	fi
else
	main_text=$( printf "You are currently an administrator on this device.\n\nIt is recommended to operate as a standard user whenever possible.\n\nDo you still require elevated privileges?" )
fi

# Set path to the icon
icon="/usr/local/mostlymac/icon.png"

# Set the default path to swift dialog
swift_dialog_path="/usr/local/bin/dialog"

# Log file which contains the timestamps of the last runs
checkFile="/tmp/privilegesCheck"

# Location of PrivilegesCLI
privilegesCLI="/Applications/Privileges.app/Contents/Resources/PrivilegesCLI"

####################################################################################################
# SET USER AND DEVICE INFO #

# Get the current user
currentUser=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )

# Get machine UDID
UDID=$( ioreg -d2 -c IOPlatformExpertDevice | awk -F\" '/IOPlatformUUID/{print $(NF-1)}' )

####################################################################################################
# FUNCTIONS #

# Function to demote the current user
demote () {
	if [[ "$standalone" = true ]] || [[ ! -e "${privilegesCLI}" ]]; then
		/usr/sbin/dseditgroup -o edit -d "$currentUser" -t user admin
	else
		launchctl asuser "$currentUserID" sudo -u "$currentUser" "$privilegesCLI" --remove &> /dev/null
	fi
}

# Function to initiate timestamp for admin calculations
initTimestamp () {
	# Get current timestamp
	timeStamp=$(date +%s)
	
	# Check if log file exists and create if needed
	if [[ ! -f ${checkFile} ]]; then
		# Create file with current timestamp
		touch ${checkFile}
		echo "${timeStamp}" > ${checkFile}
	fi
}

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
			# Successfully demoted with dseditgroup
			# If dock is running and not in standalone mode, reload to display correct tile
			if [[ $(/usr/bin/pgrep Dock) -gt 0 ]] && [[ "$standalone" != true ]]; then
				/usr/bin/killall Dock
			fi
			
			# Log that user was successfully demoted.
			echo "$stamp Status: ${1} is now a standard user on MachineID: $UDID."
		fi
		
	else
		# Log that user was successfully demoted.
		echo "$stamp Status: ${1} is now a standard user on MachineID: $UDID."
	fi
	
	# Clean up privileges check log file to reset timer
	rm "$checkFile" &> /dev/null
}

# Function to prompt with IBM Notifier
prompt_with_ibmNotifier () {
	
	# If help button is enabled, set type and payload
	if [[ $help_button_status = true ]]; then
		help_info=("-help_button_cta_type" "${help_button_type}" "-help_button_cta_payload" "${help_button_payload}")
	fi
	
	# Disable sounds if needed
	if [[ $notification_sound = false ]]; then
		sound=("-silent")
	fi
	
	# Prompt the user
	prompt_user() {
		button=$( "${ibm_notifier_path}/Contents/MacOS/${ibm_notifier_binary}" \
		-type "popup" \
		-bar_title "Privileges Reminder" \
		-subtitle "$main_text" \
		-icon_path "$icon" \
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

# Function to prompt with Swift Dialog
prompt_with_swiftDialog () {
	
	# If help button is enabled, set message and payload accordingly
	if [[ $help_button_status = true ]]; then
		if [[ $help_button_type == "infopopup" ]]; then
			help_info=("--helpmessage" "$help_button_payload")
		elif [[ $help_button_type == "link" ]]; then
			help_info=("--infobuttontext" "More Info" "--infobuttonaction" "$help_button_payload")
		fi
	fi
	
	# Prompt the user
	prompt_user() {
		button=$( "${swift_dialog_path}" \
		--title "Privileges Reminder" \
		--message "$main_text" \
		--icon "$icon" \
		--button1text No \
		--button2text Yes \
		"${help_info[@]}" \
		--timer 120 \
		--hidetimerbar \
		--small \
		--ontop )
		
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
		-description "$main_text" \
		-alignDescription left \
		-icon "$icon" \
		-button1 No \
		-button2 Yes \
		-defaultButton 1 \
		-timeout 120 )
		
		echo "$?"
	}
	
	# Get the user's response
	buttonClicked=$( prompt_user )
}

# Function to perform admin user demotion
demoteUser () {
	# Check for a logged in user
	if [[ $currentUser != "" ]]; then
		
		# Get the current user's UID
		currentUserID=$(id -u "$currentUser")
		
		# If current user is an admin, remove rights
		if /usr/sbin/dseditgroup -o checkmember -m "$currentUser" admin &> /dev/null; then
			
			# User with admin is logged in.
			# If silent option is passed, demote silently
			if [[ $silent = true ]]; then
				# Revoke rights silently
				echo "$stamp Info: Silent option used. Removing rights for $currentUser on MachineID: $UDID without notification."
				# Use function to demote user
				demote
				
				# Run confirm privileges function with current user.
				confirmPrivileges "$currentUser"
				
				exit
				
			else
				# Notify the user. Use app that user defined and fall back jamf helper
				if [[ $ibm_notifier = true ]] && [[ -e "${ibm_notifier_path}" ]]; then
					prompt_with_ibmNotifier
				elif [[ $swift_dialog = true ]] && [[ -e "${swift_dialog_path}" ]]; then
					prompt_with_swiftDialog
				else
					prompt_with_jamfHelper
				fi
			fi
			
			# If the user clicked NO (button 0), remove admin rights immediately
			if [[ $buttonClicked = 0 ]]; then
				# Revoke rights
				echo "$stamp Decision: $currentUser no longer needs admin rights. Removing rights on MachineID: $UDID now."
				# Use function to demote user
				demote
				
				# Run confirm privileges function with current user.
				confirmPrivileges "$currentUser"
				
			# If the user clicked YES (button 2) leave admin rights in tact
			elif [[ $buttonClicked = 2 ]]; then
				echo "$stamp Decision: $currentUser says they still need admin rights on MachineID: $UDID."
				echo "$stamp Status: Resetting timer and allowing $currentUser to remain an admin on MachineID: $UDID."
				
				# Clean up privileges check file to reset timer
				rm "$checkFile" &> /dev/null
				
				# Restart the timer immidiately
				initTimestamp
				
			# If timeout occurred, (exit code 4) remove admin rights
			elif [[ $buttonClicked = 4 ]]; then
				echo "$stamp Decision: Timeout occurred. Removing admin rights for $currentUser on MachineID: $UDID now."
				# Use function to demote user
				demote
				
				# Run confirm privileges function with current user.
				confirmPrivileges "$currentUser"
				
			# If unexpected code is returned, log an error
			else
				echo "$stamp Error: Unexpected exit code [$buttonClicked] returned from prompt. User: $currentUser, MachineID: $UDID."
			fi
		else
			# Current user is not an admin
			echo "$stamp Info: $currentUser is not an admin on MachineID: $UDID."
		fi
	else
		# No user currently logged in
		echo "$stamp Info: No users logged in on MachineID: $UDID."
	fi
	
	exit
}


####################################################################################################
# SET EXCLUDED USERS #

# Read comma separated list of excluded admins into array
IFS=', ' read -r -a excludedUsers <<< "$admin_to_exclude"

# Add always excluded users to array
excludedUsers+=("root" "_mbsetupuser")

# Function to check if array contains a user
containsUser () {
	local e
	for e in "${@:2}"; do [[ "$e" == "$1" ]] && return 1; done
	return 0
}

# Use function to check if current user is excluded from demotion
containsUser "$currentUser" "${excludedUsers[@]}"
excludedUserLoggedIn="$?"

####################################################################################################
# STOP HERE AND EXIT IF EXCLUDED USER IS LOGGED IN #

# If current user is excluded from demotion, reset timer and exit
if [[ "$excludedUserLoggedIn" = 1 ]]; then
	echo "$stamp Info: Excluded admin user $currentUser logged in on MachineID: $UDID. Will not perform demotion."
	# Reset timer and exit 0
	rm "$checkFile" &> /dev/null
	exit 0
fi

####################################################################################################
# DEMOTE THE USER #

# Use funciton to demote user
demoteUser