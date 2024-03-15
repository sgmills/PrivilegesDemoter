#!/bin/bash

####################################################################################################
#
# SCRIPT: Demote Admin Privileges
# AUTHOR: Sam Mills (github.com/sgmills)
# DATE:   25 April 2023
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

# Script Name
scriptName="Priviliges Demoter"

# Script Version
scriptVersion="4.0"

# All privilege events logging location
privilegesLog="/var/log/privileges.log"

dialogLog=$( mktemp -u /var/tmp/dialogLog.XXX )

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Operating System & swiftDialog Variables
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

dialogVersion=$( /usr/local/bin/dialog --version )
swiftDialogMinimumRequiredVersion="2.4.0.4750"

timestamp="$( date '+%Y-%m-%d-%H%M%S' )"

serialNumber=$( ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformSerialNumber/{print $4}' )
computerName=$( scutil --get ComputerName )
modelName=$( /usr/libexec/PlistBuddy -c 'Print :0:_items:0:machine_name' /dev/stdin <<< "$(system_profiler -xml SPHardwareDataType)" )
osVersion=$( sw_vers -productVersion )
osVersionExtra=$( sw_vers -productVersionExtra ) 
osBuild=$( sw_vers -buildVersion )
osMajorVersion=$( echo "${osVersion}" | awk -F '.' '{print $1}' )

jamfProURL=$(/usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf.plist jss_url)

jamfProComputerURL="${jamfProURL}computers.html?query=${serialNumber}&queryType=COMPUTERS"

# Report RSR sub-version if applicable
if [[ -n $osVersionExtra ]] && [[ "${osMajorVersion}" -ge 13 ]]; then osVersion="${osVersion} ${osVersionExtra}"; fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Webhook Variables
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

### Webhook Options ###

webhookEnabled="false"                                                          # Enables the webhook feature [ all | demote | false (default) ]
teamsURL=""                                                                     # Teams webhook URL                         
slackURL=""                                                                     # Slack webhook URL


# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Custom swiftDialog Variables
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

### Title in demoter window ###

appTitle="Privileges Reminder"

### swiftDialog timer in demoter window ###

timer="120"

### Overlay Icon ###

useOverlayIcon="true"								# Toggles swiftDialog to use an overlay icon [ true (default) | false ]

# Create `overlayicon` from Self Service's custom icon (thanks, @meschwartz!)
if [[ "$useOverlayIcon" == "true" ]]; then
    xxd -p -s 260 "$(defaults read /Library/Preferences/com.jamfsoftware.jamf self_service_app_path)"/Icon$'\r'/..namedfork/rsrc | xxd -r -p > /var/tmp/overlayicon.icns
    overlayicon="/var/tmp/overlayicon.icns"
else
    overlayicon=""
fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # ## # # # # # # # # # # # # # #
# IT Support Variable 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

### Support Team Details ###
supportTeamName="Add IT Support"
supportTeamPhone="Add IT Phone Number"
supportTeamEmail="Add email"
supportTeamWebsite="Add IT Help site"
supportTeamHyperlink="[${supportTeamWebsite}](https://${supportTeamWebsite})"

# Create the help message based on Support Team variables
helpMessage="If you need assistance, please contact ${supportTeamName}:  \n- **Telephone:** ${supportTeamPhone}  \n- **Email:** ${supportTeamEmail}  \n- **Help Website:** ${supportTeamHyperlink}  \n\n**Computer Information:**  \n- **Operating System:**  $osVersion ($osBuild)  \n- **Serial Number:** $serialNumber  \n- **Dialog:** $dialogVersion  \n- **Started:** $timestamp  \n- **Script Version:** $scriptVersion"

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

	# Get reminder threshold operation setting
	reminder_threshold="$( /usr/libexec/PlistBuddy -c "print reminderThreshold" "$pdPrefs" 2>/dev/null )"
	
	# Get setting for standalone mode without SAP Privileges
	standalone="$( /usr/libexec/PlistBuddy -c "print standaloneMode" "$pdPrefs" 2>/dev/null )"
	
	# Get main text for notifications. Set to default if not found
	if [[ ! $( /usr/libexec/PlistBuddy -c "print mainText" "$pdPrefs" 2>/dev/null ) ]]; then
		main_text=$( printf "You are currently an administrator on this device. \n\nDo you still require elevated privileges? \n\n _You will be demoted automatically if the timer expires_" )
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
if [ -f /usr/local/mostlymac/icon.png ]; then
	icon="/usr/local/mostlymac/icon.png"
elif [ -f /Applications/Privileges.app/Contents/Resources/AppIcon.icns ]; then
	icon="/Applications/Privileges.app/Contents/Resources/AppIcon.icns"
else
	icon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertNoteIcon.icns"
fi

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
#
# Functions
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Client-side Logging
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function updateprivilegesLog() {
    echo "${scriptName} ($scriptVersion): $( date +%Y-%m-%d\ %H:%M:%S ) - ${1}" | tee -a "${privilegesLog}"
}

function preFlight() {
    updateprivilegesLog "[PRE-FLIGHT]      ${1}"
}

function notice() {
    updateprivilegesLog "[NOTICE]          ${1}"
}

function infoOut() {
    updateprivilegesLog "[INFO]            ${1}"
}

function errorOut(){
    updateprivilegesLog "[ERROR]           ${1}"
}

function error() {
    updateprivilegesLog "[ERROR]           ${1}"
    let errorCount++
}

function warning() {
    updateprivilegesLog "[WARNING]         ${1}"
    let errorCount++
}

function fatal() {
    updateprivilegesLog "[FATAL ERROR]     ${1}"
    exit 1
}

function quitOut(){
    updateprivilegesLog "[QUIT]            ${1}"
}

####################################################################################################
#
# Pre-flight Checks
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Client-side Logging
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ ! -f "${privilegesLog}" ]]; then
    touch "${privilegesLog}"
    if [[ -f "${privilegesLog}" ]]; then
        preFlight "Created specified privilegesLog"
		preFlight "Script version is: $scriptVersion"
    else
        fatal "Unable to create specified privilegesLog '${privilegesLog}'; exiting.\n\n(Is this script running as 'root' ?)"
    fi
else
    preFlight "Specified privilegesLog exists; writing log entries to it"
	preFlight "Script version is: $scriptVersion"
fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Logging Preamble
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

preFlight "\n\n###\n# $scriptName (${scriptVersion})\n# https://github.com/sgmills/PrivilegesDemoter \n###\n"
preFlight "Initiating …"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Validate / Create Temp DialogLog File
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ ! -f "${dialogLog}" ]]; then
    touch "${dialogLog}"
    if [[ -f "${dialogLog}" ]]; then
        preFlight "Created specified dialogLog"
    else
        fatal "Unable to create specified dialogLog; exiting.\n\n(Is this script running as 'root' ?)"
    fi
else
    preFlight "Specified dialogLog exists; proceeding …"
fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Validate / install swiftDialog (Thanks big bunches, @acodega!)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function dialogInstall() {

    # Get the URL of the latest PKG From the Dialog GitHub repo
    dialogURL=$(curl -L --silent --fail "https://api.github.com/repos/swiftDialog/swiftDialog/releases/latest" | awk -F '"' "/browser_download_url/ && /pkg\"/ { print \$4; exit }")

    # Expected Team ID of the downloaded PKG
    expectedDialogTeamID="PWA5E9TQ59"

    preFlight "Installing swiftDialog..."

    # Create temporary working directory
    workDirectory=$( /usr/bin/basename "$0" )
    tempDirectory=$( /usr/bin/mktemp -d "/private/tmp/$workDirectory.XXXXXX" )

    # Download the installer package
    /usr/bin/curl --location --silent "$dialogURL" -o "$tempDirectory/Dialog.pkg"

    # Verify the download
    teamID=$(/usr/sbin/spctl -a -vv -t install "$tempDirectory/Dialog.pkg" 2>&1 | awk '/origin=/ {print $NF }' | tr -d '()')

    # Install the package if Team ID validates
    if [[ "$expectedDialogTeamID" == "$teamID" ]]; then

        /usr/sbin/installer -pkg "$tempDirectory/Dialog.pkg" -target /
        sleep 2
        dialogVersion=$( /usr/local/bin/dialog --version )
        preFlight "swiftDialog version ${dialogVersion} installed; proceeding..."

    else

        # Display a so-called "simple" dialog if Team ID fails to validate
        osascript -e 'display dialog "Please advise your Support Representative of the following error:\r\r• Dialog Team ID verification failed\r\r" with title "Setup Your Mac: Error" buttons {"Close"} with icon caution'
        completionActionOption="Quit"
        exitCode="1"
        quitScript

    fi

    # Remove the temporary working directory when done
	infoOut "Removing temp working directory"
    /bin/rm -Rf "$tempDirectory"

}



function dialogCheck() {

    # Output Line Number in `verbose` Debug Mode
    if [[ "${debugMode}" == "verbose" ]]; then preFlight "# # # SETUP YOUR MAC VERBOSE DEBUG MODE: Line No. ${LINENO} # # #" ; fi

    # Check for Dialog and install if not found
    if [[ ! -e "/Library/Application Support/Dialog/Dialog.app" || ! -e "$swift_dialog_path" ]]; then

        preFlight "swiftDialog not found. Installing..."
        dialogInstall

    else

        dialogVersion=$(/usr/local/bin/dialog --version)
        if [[ "${dialogVersion}" < "${swiftDialogMinimumRequiredVersion}" ]]; then
            
            preFlight "swiftDialog version ${dialogVersion} found but swiftDialog ${swiftDialogMinimumRequiredVersion} or newer is required; updating..."
            dialogInstall
            
        else

        preFlight "swiftDialog version ${dialogVersion} found; proceeding..."

        fi
    
    fi

}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Validate Logged-in System Accounts
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function currentLoggedInUser() {
    loggedInUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )
    preFlight "Current Logged-in User: ${loggedInUser}"

    networkUser="$(dscl . -read /Users/$loggedInUser | grep "NetworkUser" | cut -d " " -f 2)"
    preFlight "Network User is $networkUser"

    until { [[ "${loggedInUser}" != "_mbsetupuser" ]] || [[ "${counter}" -gt "180" ]]; } && { [[ "${loggedInUser}" != "loginwindow" ]] || [[ "${counter}" -gt "30" ]]; } ; do
    preFlight "Logged-in User Counter: ${counter}"
    currentLoggedInUser
    sleep 2
    ((counter++))
    done

    loggedInUserFullname=$( id -F "${loggedInUser}" )
    loggedInUserFirstname=$( echo "$loggedInUserFullname" | sed -E 's/^.*, // ; s/([^ ]*).*/\1/' | sed 's/\(.\{25\}\).*/\1…/' | awk '{print ( $0 == toupper($0) ? toupper(substr($0,1,1))substr(tolower($0),2) : toupper(substr($0,1,1))substr($0,2) )}' )
    loggedInUserLastname=$(echo "$loggedInUserFullname" | sed "s/$loggedInUserFirstname//" |  sed 's/,//g')
    loggedInUserID=$( id -u "${loggedInUser}" )
    #preFlight "Current Logged-in User First Name: ${loggedInUserFirstname}"
    preFlight "Current Logged-in User Full Name: ${loggedInUserFirstname} ${loggedInUserLastname}"
    preFlight "Current Logged-in User ID: ${loggedInUserID}"

}

preFlight "Check for Logged-in System Accounts …"

currentLoggedInUser

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Complete
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

preFlight "Complete!"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Update Privileges Log
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Redirect output to log file and stdout for logging
exec 1> >( tee -a "${privilegesLog}" ) 2>&1

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Update Dialog
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function updateDialog() {
    echo "${1}" >> "${swift_dialog_path}"
    sleep 0.4
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Quit Script (thanks, @bartreadon!)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function quitScript() {

    notice "*** QUITTING ***"

	 # Remove dialogLog
    if [[ -f "${dialogLog}" ]]; then
        infoOut "Removing ${dialogLog} …"
        rm "${dialogLog}"
    fi

    quitOut "Goodbye!"
    exit

}

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
		warning "${1} is still an admin on MachineID: $UDID. Trying again..."
		/usr/sbin/dseditgroup -o edit -d "${1}" -t user admin
		sleep 1
		
		# If user was not sucessfully demoted after retry, write error to log. Otherwise log success.
		if /usr/sbin/dseditgroup -o checkmember -m "${1}" admin &> /dev/null; then
			errorOut "Could not demote ${1} to standard on MachineID: $UDID."
		else
			# Successfully demoted with dseditgroup
			# If dock is running and not in standalone mode, reload to display correct tile
			if [[ $(/usr/bin/pgrep Dock) -gt 0 ]] && [[ "$standalone" != true ]]; then
				/usr/bin/killall Dock
			fi
			
			# Log that user was successfully demoted.
			notice "${1} is now a standard user on MachineID: $UDID."
		fi
		
	else
		# Log that user was successfully demoted.
		notice "${1} is now a standard user on MachineID: $UDID."
	fi
	
	# Clean up privileges check log file to reset timer
	infoOut "Removing check log file to reset timer"
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
	prompt_user_dialog() {
		button=$( "${swift_dialog_path}" \
		--title "$appTitle" \
		--message "$main_text" \
        --overlayicon "$overlayicon" \
        --titlefont size=18 \
		--messagefont size=14 \
		--icon "$icon" \
		--iconsize 100 \
		--button1text No \
        --helpmessage "$helpMessage" \
		--button2text Yes \
		"${help_info[@]}" \
		--timer "$timer" \
		--height 225 \
		--width 520 \
        --moveable \
		--commandfile "$dialogLog" \
		--ontop )
		
		echo "$?"
	}
	
	# Get the user's response
	buttonClicked=$( prompt_user_dialog )
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

# Function to check if array contains a user
containsUser () {
	local e
	for e in "${@:2}"; do [[ "$e" == "$1" ]] && return 1; done
	return 0
}

# Function to perform admin user demotion
demoteUser () {
	# Check for a logged in user
	if [[ $currentUser != "" ]]; then
		
		# Get the current user's UID
		currentUserID=$(id -u "$currentUser")
		
		# If current user is an admin, remove rights
		if /usr/sbin/dseditgroup -o checkmember -m "$currentUser" admin &> /dev/null; then
			
			# Read comma separated list of excluded admins into array
			IFS=', ' read -r -a excludedUsers <<< "$admin_to_exclude"
			
			# Add always excluded users to array
			excludedUsers+=("root" "_mbsetupuser")
			
			# Use function to check if current user is excluded from demotion
			containsUser "$currentUser" "${excludedUsers[@]}"
			excludedUserLoggedIn="$?"
			
			
			# If current user is excluded from demotion, reset timer and exit
			if [[ "$excludedUserLoggedIn" = 1 ]]; then
				notice "Excluded admin user ${loggedInUserFirstname} ${loggedInUserLastname}($currentUser) logged in on MachineID: $UDID. Will not perform demotion."
				# Reset timer and exit 0
				infoOut "Removing check log file to reset timer and exiting 0"
				rm "$checkFile" &> /dev/null
				exit 0
			fi
			
			# User with admin is logged in.
			# If silent option is passed, demote silently
			if [[ $silent = true ]]; then
				# Revoke rights silently
				notice "Silent option used. Removing rights for ${loggedInUserFirstname} ${loggedInUserLastname}($currentUser) on MachineID: $UDID without notification."
				webhookStatus="Silent: Removing rights (S/N ${serialNumber})"
				# Use function to demote user
				demote
				
				# Run confirm privileges function with current user.
				confirmPrivileges "$currentUser"
				
				exit
				
			else
				# Notify the user. Use app that user defined and fall back jamf helper
				if [[ $ibm_notifier = true ]]; then
					if [[ -e "${ibm_notifier_path}" ]]; then
						prompt_with_ibmNotifier
					else
						warning "IBM Notifier not found. Defaulting to Jamf Helper for notification."
						prompt_with_jamfHelper
					fi
				elif [[ $swift_dialog = true ]]; then
					if [[ -e "${swift_dialog_path}" ]]; then
						infoOut "swiftDialog installed, running swiftDialog Window"
						prompt_with_swiftDialog
					else
						warning "Swift Dialog not found. Running Dialog Check to Install."
						dialogCheck
						if [[ -e "${swift_dialog_path}" ]]; then
						errorOut "swiftDialog could not install for some reason. Defaulting to Jamf Helper for notification"
						prompt_with_jamfHelper
						else
						infoOut "swiftDialog installed, running swiftDialog Window"
						prompt_with_swiftDialog
						fi
					fi
				else
					infoOut "Defaulting to Jamf Helper for notification"
					prompt_with_jamfHelper
				fi
			fi
			
			# If the user clicked NO (button 0), remove admin rights immediately
			if [[ $buttonClicked = 0 ]]; then
				# Revoke rights
				notice "${loggedInUserFirstname} ${loggedInUserLastname}($currentUser) no longer needs admin rights. Removing rights on MachineID: $UDID now."
				webhookStatus="User Demoted: Removing Rights (S/N ${serialNumber})"
				# Use function to demote user
				demote
				
				# Run confirm privileges function with current user.
				confirmPrivileges "$currentUser"
				
			# If the user clicked YES (button 2) leave admin rights in tact
			elif [[ $buttonClicked = 2 ]]; then
				notice "${loggedInUserFirstname} ${loggedInUserLastname}($currentUser) says they still need admin rights on MachineID: $UDID."
				notice "Resetting timer and allowing ${loggedInUserFirstname} ${loggedInUserLastname}($currentUser) to remain an admin on MachineID: $UDID."
				webhookStatus="User Elevated: Resetting Time (S/N ${serialNumber})"
				# Clean up privileges check file to reset timer
				infoOut "Removing check log file to reset timer"
				rm "$checkFile" &> /dev/null
				# Restart the timer immidiately
				initTimestamp
				
			# If timeout occurred, (exit code 4) remove admin rights
			elif [[ $buttonClicked = 4 ]]; then
				notice "Timeout occurred. Removing admin rights for ${loggedInUserFirstname} ${loggedInUserLastname}($currentUser) on MachineID: $UDID now."
				webhookStatus="Timer Expired: Removing Rights (S/N ${serialNumber})"
				# Use function to demote user
				demote
				
				# Run confirm privileges function with current user.
				confirmPrivileges "$currentUser"
				
			# If unexpected code is returned, log an error
			else
				errorOut "Unexpected exit code [$buttonClicked] returned from prompt. User: ${loggedInUserFirstname} ${loggedInUserLastname}($currentUser), MachineID: $UDID."
			fi
		else
			# Current user is not an admin
			notice "${loggedInUserFirstname} ${loggedInUserLastname}($currentUser) is not an admin on MachineID: $UDID."
		fi
	else
		# No user currently logged in
		infoOut "No users logged in on MachineID: $UDID."
	fi
	
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Webhook Message (Microsoft Teams or Slack) 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function webHookMessage() {

if [[ $slackURL == "" ]]; then
    notice "No slack URL configured"
else
    if [[ $supportTeamHyperlink == "" ]]; then
        supportTeamHyperlink="https://www.slack.com"
    fi
    notice "Sending Slack WebHook"
    curl -s -X POST -H 'Content-type: application/json' \
        -d \
        '{
	"blocks": [
		{
			"type": "header",
			"text": {
				"type": "plain_text",
				"text": "'${scriptName}': '${webhookStatus}'",
			}
		},
		{
			"type": "divider"
		},
		{
			"type": "section",
			"fields": [
				{
					"type": "mrkdwn",
					"text": ">*Serial Number and Computer Name:*\n>'"$computerName"' on '"$serialNumber"'"
				},
                		{
					"type": "mrkdwn",
					"text": ">*Computer Model:*\n>'"$modelName"'"
				},
				{
					"type": "mrkdwn",
					"text": ">*Current User:*\n>'"$loggedInUserFirstname $loggedInUserLastname ($loggedInUser)"'"
				},
				{
					"type": "mrkdwn",
					"text": ">*Reminder Threshold:*\n>'"$reminder_threshold minutes"'"
				},
                		{
					"type": "mrkdwn",
					"text": ">*Computer Record:*\n>'"$jamfProComputerURL"'"
				}
			]
		},
		{
		"type": "actions",
			"elements": [
				{
					"type": "button",
					"text": {
						"type": "plain_text",
						"text": "View computer in Jamf Pro",
						"emoji": true
					},
					"style": "primary",
					"action_id": "actionId-0",
					"url": "'"$jamfProComputerURL"'"
				}
			]
		}
	]
}' \
        $slackURL
fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Teams notification (Credit to https://github.com/nirvanaboi10 for the Teams code)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ $teamsURL == "" ]]; then
    notice "No teams Webhook configured"
else
    if [[ $supportTeamHyperlink == "" ]]; then
        supportTeamHyperlink="https://www.microsoft.com/en-us/microsoft-teams/"
    fi
    notice "Sending Teams WebHook"
    jsonPayload='{
	"@type": "MessageCard",
	"@context": "http://schema.org/extensions",
	"themeColor": "0076D7",
	"summary": "'${scriptName}': '${webhookStatus}'",
	"sections": [{
		"activityTitle": "'${webhookStatus}'",
		"activityImage": "https://github.com/AndrewMBarnett/PrivilegesDemoter/blob/main/Screenshots/install.png?raw=true",
		"facts": [{
			"name": "Computer Name (Serial Number):",
			"value": "'"$computerName"' ('"$serialNumber"')"
		}, {
			"name": "Computer Model:",
			"value": "'"$modelName"'"
		}, {
			"name": "Current User:",
			"value": "'"$loggedInUserFirstname $loggedInUserLastname ($loggedInUser)"'"
		}, {
			"name": "Reminder Threshold:",
			"value": "'"$reminder_threshold minutes"'"
        }, {
			"name": "Computer Record:",
			"value": "'"$jamfProComputerURL"'"
		}],
		"markdown": true
	}],
	"potentialAction": [{
		"@type": "OpenUri",
		"name": "View in Jamf Pro",
		"targets": [{
			"os": "default",
			"uri":
			"'"$jamfProComputerURL"'"
		}]
	}]
}'

    # Send the JSON payload using curl
    curl -s -X POST -H "Content-Type: application/json" -d "$jsonPayload" "$teamsURL"

fi

}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# webHookMessage
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

case ${webhookEnabled} in

    "all" ) # Notify on all events 

        infoOut "Webhook Enabled flag set to: ${webhookEnabled}, continuing ..."

    	# Use funciton to demote user
		if [[ $swift_dialog = true ]]; then
			if [[ ! -e "${swift_dialog_path}" ]]; then
				infoOut "swiftDialog set as true, but no installed. Installing now..."
				dialogCheck
			else
				infoOut "swiftDialog set as true and installed. Checking version..."
				dialogCheck
			fi
		fi		

		infoOut "Running Demote User Functions"
			demoteUser
		infoOut "Sending webhook"
       		webHookMessage
    ;;

    "demote" ) # Notify on demotion

        demoteUser

        if [[ $buttonClicked = 0 ]] || [[ $buttonClicked = 4 ]]; then
        	infoOut "User self demoted or timer expired"
        	infoOut "Webhook Enabled flag set to: ${webhookEnabled}, continuing ..."
        		webHookMessage
    	else
        	infoOut "Webhook Enabled flag set to: ${webhookEnabled}, but conditions not met for running webhookMessage."
    	fi
    ;;

    "false" ) # Don't notify
    
        infoOut "Webhook Enabled flag set to: ${webhookEnabled}, skipping ..."
        
        # Use funciton to demote user
		if [[ $swift_dialog = true ]]; then
			if [[ ! -e "${swift_dialog_path}" ]]; then
				infoOut "swiftDialog set as true, but no installed. Installing now..."
				dialogCheck
			else
				infoOut "swiftDialog set as true and installed. Checking version..."
				dialogCheck
			fi
		fi		

		infoOut "Running Demote User Functions"
			demoteUser
    ;;

    * ) # Catch-all
        infoOut "Webhook Enabled flag set to: ${webhookEnabled}, skipping ..."
        ;;

esac

quitScript
