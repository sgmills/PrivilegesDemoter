#!/bin/bash
#Version:3.0

####################################################################################################
# MUST BE RUN AS ROOT #

if [ "$EUID" -ne 0 ]; then 
	echo "This script must be run as root!"
	exit
fi

####################################################################################################
# LOG SETUP #

# All privilege events logging location
privilegesLog="/var/log/privileges.log"

# Check if log exists and create if needed
if [ ! -f "$privilegesLog" ]; then
	touch "$privilegesLog"
fi

# Function for logging privileges demoter actions
pdLog () {
	# Create stamp for privileges demoter logging
	stamp="$(date +"%Y-%m-%d %H:%M:%S%z") blog.mostlymac.privileges.demoter"
	
	# Redirect to log file
	echo "$stamp $1" >> "$privilegesLog"
}

####################################################################################################
# SET SCRIPT VARIABLES #

# PrivilegesDemoter managed preferences plist
pdPrefs="/Library/Managed Preferences/blog.mostlymac.privilegesdemoter.plist"

# Get help button status
help_button_status="$( defaults read "$pdPrefs" HelpButtonStatus 2>/dev/null )"

# Get the help button type
help_button_type="$( defaults read "$pdPrefs" HelpButtonType 2>/dev/null )"

# Get the help button payload
help_button_payload="$( defaults read "$pdPrefs" HelpButtonPayload 2>/dev/null )"

# Get notification sound setting
notification_sound="$( defaults read "$pdPrefs" NotificationSound 2>/dev/null )"

# Are we using IBM Notifer?
ibm_notifier="$( defaults read "$pdPrefs" IBMNotifier 2>/dev/null )"

# Are we using Swift Dialog?
swift_dialog="$( defaults read "$pdPrefs" SwiftDialog 2>/dev/null )"

# Get list of excluded admins
admin_to_exclude="$( defaults read "$pdPrefs" AdminsToExclude 2>/dev/null )"

# Get admin threshold
admin_threshold="$( defaults read "$pdPrefs" AdminThreshold 2>/dev/null )"

# Get silent operation setting
silent="$( defaults read "$pdPrefs" Silent 2>/dev/null )"

# Get setting for running from jamf
jamf="$( defaults read "$pdPrefs" UseJamfPolicy 2>/dev/null )"

# Get setting for standalone mode without SAP Privileges
standalone="$( defaults read "$pdPrefs" Standalone 2>/dev/null )"

# Check for jamf trigger. Set to default if not found
if [[ ! $( defaults read "$pdPrefs" JamfTrigger 2>/dev/null ) ]]; then
	jamf_trigger="privilegesDemote"
else
	jamf_trigger="$( defaults read "$pdPrefs" JamfTrigger 2>/dev/null )"
fi

# Get main text for notifications. Set to default if not found
if [[ ! $( defaults read "$pdPrefs" MainText 2>/dev/null ) ]]; then
	main_text="You are currently an administrator on this device.\n\nIt is recommended to operate as a standard user whenever possible.\n\nDo you still require elevated privileges?"
else
	get_text="$( defaults read "$pdPrefs" MainText 2>/dev/null )"
	# Strip out extra slash in new line characters
	main_text="${get_text//'\\n'/\n}"
fi

# Check for IBM Notifier path. Set to default if not found
if [[ ! $( defaults read "$pdPrefs" IBMNotifierPath 2>/dev/null ) ]]; then
	ibm_notifier_path="/Applications/IBM Notifier.app"
else
	ibm_notifier_path="$( defaults read "$pdPrefs" IBMNotifierPath )"
fi

# Check for IBM Notifier custom binary name. Set to default if not found
if [[ ! $( defaults read "$pdPrefs" IBMNotifierBinary 2>/dev/null ) ]]; then
	ibm_notifier_binary="IBM Notifier"
else
	ibm_notifier_binary="$( defaults read "$pdPrefs" IBMNotifierBinary )"
fi

# Set the default path to swift dialog
swift_dialog_path="/usr/local/bin/dialog"

# Get DockToggleTimeout from SAP Privileges preferences (if it exists)
sapPrivilegesPreferences="/Library/Managed Preferences/corp.sap.privileges.plist"
sapDockToggleTimeout=$( defaults read "$sapPrivilegesPreferences" DockToggleTimeout 2>/dev/null )

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
	pdLog "Info: Excluded admin user $currentUser logged in on MachineID: $UDID. Will not perform demotion."
	# Reset timer and exit 0
	rm "$checkFile" &> /dev/null
	exit 0
fi

####################################################################################################
# THRESHOLD SETUP #

# Check for PrivilegesDemoter admin_threshold or SAP Privileges DockTileTimeout (in that order)
# If keys are not present or set to never, use default value of 15 minutes
if [ "$admin_threshold" ] && [ "$admin_threshold" != 0 ]; then
	timeLimit=$((admin_threshold * 60))
elif [ "$sapDockToggleTimeout" ] && [ "$sapDockToggleTimeout" != 0 ]; then
	timeLimit=$((sapDockToggleTimeout * 60))
else
	timeLimit=900
fi

####################################################################################################
# FUNCTIONS #

# Function to display help message with usage options
usage () {
	echo ""
	echo "   Usage: ./PrivilegesDemoter.sh [--options]"
	echo ""
	echo "   [no flags]       If the current user has passed the admin threshold, offer to demote them."
	echo "   --elevate        Elevate the current user to administrator"
	echo "   --demote         Demote the current user to standard"
	echo "   --demote-silent  Demote the current user to standard silently"
	echo "   --status         Displays the current user's privileges"
	echo "   --admin-time     Display elapsed time since last PrivilegesDemoter run"
	echo "   --help           Display this message"
	echo ""
	
	exit
}

# Function to get elapsed time since last run
adminTime () {
	if /usr/sbin/dseditgroup -o checkmember -m "$currentUser" admin &> /dev/null; then
		# Use function to initiate timestamp
		initTimestamp
		
		# Get the start time
		startTime=$( head -n 1 "$checkFile" )
		
		# Get the elapsed time
		elapsedTime=$((timeStamp - startTime))
		
		convertAndPrintSeconds() {
			local totalSeconds=$1;
			local seconds=$((totalSeconds%60));
			local minutes=$((totalSeconds/60%60));
			(( minutes > 0 )) && printf '%d minutes ' $minutes;
			printf '%d seconds\n' $seconds;
		}
		
		# Convert to human readable format
		convertAndPrintSeconds "$elapsedTime"
	else
		# User is not admin.
		echo "$currentUser is not an administrator. Nothing to do."
	fi
	
	exit
}

# Function to elevate the current user
elevate () {
	if [[ "$standalone" = 1 ]] || [[ ! -e "${privilegesCLI}" ]]; then
		if /usr/sbin/dseditgroup -o checkmember -m "$currentUser" admin &> /dev/null; then
			pdLog "Status: User $currentUser already has the requested privileges. Nothing to do."
			echo "$currentUser is already an administrator. Nothing to do."
		else
			/usr/sbin/dseditgroup -o edit -a "$currentUser" -t user admin
			initTimestamp
			pdLog "Status: $currentUser is now an admin user on MachineID: $UDID."
			echo "$currentUser now has administrator rights."
		fi
	else
		launchctl asuser "$currentUserID" sudo -u "$currentUser" "$privilegesCLI" --add
		initTimestamp
	fi
	
	exit
}

# Function to demote the current user
demote () {
	if [[ "$standalone" = 1 ]] || [[ ! -e "${privilegesCLI}" ]]; then
		/usr/sbin/dseditgroup -o edit -d "$currentUser" -t user admin
		echo "$currentUser is now a standard user."
		
	else
		launchctl asuser "$currentUserID" sudo -u "$currentUser" "$privilegesCLI" --remove &> /dev/null
	fi
}

# Function to get the current user status
status () {
	if [[ "$standalone" = 1 ]] || [[ ! -e "${privilegesCLI}" ]]; then
		if /usr/sbin/dseditgroup -o checkmember -m "$currentUser" admin &> /dev/null; then
			echo "User $currentUser has administrator rights."
		else
			echo "User $currentUser has standard user rights."
		fi
	else
		launchctl asuser "$currentUserID" sudo -u "$currentUser" "$privilegesCLI" --status
	fi
	
	exit
}


# Function to get the last 5 minutes of logs from SAP privileges helper
sapPrivilegesLogger () {
	# The Privileges.app elevation event is not logged elsewhere, so this should capture it
	privilegesHelperLog=$( log show --style compact --predicate 'process == "corp.sap.privileges.helper"' --last 5m | grep "SAPCorp" )
	
	# Check if elevation event exists and add it to the log file
	if [ "$privilegesHelperLog" ]; then
		echo "$privilegesHelperLog" | while read -r line; do echo "${line} on MachineID: $UDID" >> $privilegesLog; done
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
		pdLog "Warn: ${1} is still an admin on MachineID: $UDID. Trying again..."
		/usr/sbin/dseditgroup -o edit -d "${1}" -t user admin
		sleep 1
		
		# If user was not sucessfully demoted after retry, write error to log. Otherwise log success.
		if /usr/sbin/dseditgroup -o checkmember -m "${1}" admin &> /dev/null; then
			pdLog "Error: Could not demote ${1} to standard on MachineID: $UDID."
		else
			# Successfully demoted with dseditgroup. Need to update dock tile
			# If running, and not in standalone mode, reload dock to display correct tile
			if [[ $(/usr/bin/pgrep Dock) -gt 0 ]] && [[ "$standalone" = 0 ]]; then
				/usr/bin/killall Dock
			fi
			
			# Log that user was successfully demoted.
			pdLog "Status: ${1} is now a standard user on MachineID: $UDID."
		fi
		
	else
		# Log that user was successfully demoted.
		pdLog "Status: ${1} is now a standard user on MachineID: $UDID."
	fi
	
	# Clean up privileges check log file to reset timer
	rm "$checkFile" &> /dev/null
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
		button=$( "${ibm_notifier_path}/Contents/MacOS/${ibm_notifier_binary}" \
		-type "popup" \
		-bar_title "Privileges Reminder" \
		-subtitle "$main_text" \
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

# Function to prompt with Swift Dialog
prompt_with_swiftDialog () {
	
	# If help button is enabled, set message and payload accordingly
	if [[ $help_button_status = 1 ]]; then
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
		--icon "/Applications/Privileges.app/Contents/Resources/AppIcon.icns" \
		--button1text No \
		--button2text Yes \
		"${help_info[@]}" \
		--timer 120 \
		--hidetimerbar \
		--small )
		
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
			if [[ $silent = 1 ]]; then
				# Revoke rights with PrivilegesCLI silently
				pdLog "Info: Silent option used. Not notifying user and removing rights for $currentUser on MachineID: $UDID now."
				# Use function to demote user
				demote
				
				# Run confirm privileges function with current user.
				confirmPrivileges "$currentUser"
				
				exit
				
			else
				# Notify the user. Use app that user defined and fall back to what is available if needed
				if [[ $ibm_notifier = 1 ]] && [[ -e "${ibm_notifier_path}" ]]; then
					prompt_with_ibmNotifier
				elif [[ $swift_dialog = 1 ]] && [[ -e "${swift_dialog_path}" ]]; then
					prompt_with_swiftDialog 
				else
					prompt_with_jamfHelper
				fi
			fi
			
			# If the user clicked NO (button 0), remove admin rights immediately
			if [[ $buttonClicked = 0 ]]; then
				# Revoke rights with PrivilegesCLI
				pdLog "Decision: $currentUser no longer needs admin rights. Removing rights on MachineID: $UDID now."
				# Use function to demote user
				demote
				
				# Run confirm privileges function with current user.
				confirmPrivileges "$currentUser"
				
			# If the user clicked YES (button 2) leave admin rights in tact
			elif [[ $buttonClicked = 2 ]]; then
				pdLog "Decision: $currentUser says they still need admin rights on MachineID: $UDID."
				pdLog "Status: Resetting timer and allowing $currentUser to remain an admin on MachineID: $UDID."
				
				# Clean up privileges check file to reset timer
				rm "$checkFile" &> /dev/null
				
			# If timeout occurred, remove admin rights
			elif [[ $buttonClicked = 4 ]]; then
				pdLog "Decision: Timeout occurred. Removing admin rights for $currentUser on MachineID: $UDID now."
				# Use function to demote user
				demote
				
				# Run confirm privileges function with current user.
				confirmPrivileges "$currentUser"
				
			# If unexpected code is returned, log an error
			else
				pdLog "Error: Unexpected exit code returned from prompt. User: $currentUser, MachineID: $UDID."
			fi
		else
			# Current user is not an admin
			pdLog "Info: $currentUser is not an admin on MachineID: $UDID."
		fi
	else
		# No user currently logged in
		pdLog "Info: No users logged in on MachineID: $UDID."
	fi
	
	exit
}

# Function to check if admin time threshold is passed
checkAdminThreshold () {
	# Check if user is an admin
	if /usr/sbin/dseditgroup -o checkmember -m "$currentUser" admin &> /dev/null; then
		# Process admin time
		oldTimeStamp=$(head -1 "${checkFile}")
		echo "${timeStamp}" >> "${checkFile}"
		
		adminTime=$((timeStamp - oldTimeStamp))
		
		# If user is admin for more than the time limit, return true
		if [[ ${adminTime} -ge ${timeLimit} ]]; then
			return 1
		fi
	else
		# User is not admin. Return false, and reset timer
		pdLog "Info: $currentUser is not an admin on MachineID: $UDID."
		rm "${checkFile}"
		return 0
	fi
}

####################################################################################################
# GET INPUTS #

# Get inputs
while test $# -gt 0; do
	case "$1" in
		--elevate)
			# Run function to elevate the user now
			elevate
		;;
		--demote)
			# Run function to demote the user now
			demoteUser
		;;
		--demote-silent)
			# Set the silent flag to true
			silent=1
			# Run function to demote the user now
			demoteUser
		;;
		--admin-time)
			# Run function to display how long user has had admin rights
			adminTime
		;;
		--status)
			# Run function to display user status
			status
		;;
		--help|-*)
			# Display usage dialog
			usage
		;;
	esac
	shift
done

####################################################################################################
# DO THE WORK #

# Use function to initiate timestamp
initTimestamp

# Use function to get the last 5 minutes of logs from SAP privileges helper
sapPrivilegesLogger

# Use function to determine if logged in user has passed the threshold
checkAdminThreshold
passedThreshold="$?"

# If logged in user is passed the threshold offer to demote them
if [[ "$passedThreshold" = 1 ]]; then
	# Check if we should perform demotion from Jamf or locally
	if [[ "$jamf" = 1 ]]; then
		/usr/local/bin/jamf policy -event "$jamf_trigger"
	else
		# Use function to demote user
		demoteUser
	fi
fi