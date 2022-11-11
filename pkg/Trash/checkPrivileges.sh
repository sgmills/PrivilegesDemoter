#!/bin/bash
#Version:2.1

# Logging location
privilegesLog="/var/log/privileges.log"

# Check if log exists and create if needed
if [ ! -f "$privilegesLog" ]; then
	touch "$privilegesLog"
fi

# Get machine UDID
UDID=$( ioreg -d2 -c IOPlatformExpertDevice | awk -F\" '/IOPlatformUUID/{print $(NF-1)}' )

# The Privileges.app elevation event is not logged elsewhere, so this should capture it
# Grab last 5 minutes of logs from privileges helper
privilegesHelperLog=$( log show --style compact --predicate 'process == "corp.sap.privileges.helper"' --last 5m | grep "SAPCorp" )

# Check if elevation even exists and add it to the log file
if [ "$privilegesHelperLog" ]; then
	echo "$privilegesHelperLog" | while read -r line; do echo "${line} on MachineID: $UDID" >> $privilegesLog; done
fi

# If DockToggleTimeout is set within SAP Privileges preferences, use that value.
privilegesPreferences="/Library/Managed Preferences/corp.sap.privileges.plist"
keyName="DockToggleTimeout"
readPrivilegesPreferences=$( defaults read "$privilegesPreferences" "$keyName" 2>/dev/null )

# Check for preferences. If not present or set to never, use default value
if [ ! "$readPrivilegesPreferences" ] || [ "$readPrivilegesPreferences" = 0 ]; then
	timeLimit=900
else
	timeLimit=$((readPrivilegesPreferences * 60))
fi

# Signal file, must match blog.mostlymac.privileges.demote.plist -> watchpaths
signalFile="/tmp/privilegesDemote"

# Log file which contains the timestamps of the last runs
logFile="/tmp/privilegesCheck"

# Current timestamp
timeStamp=$(date +%s)

# Check if log file exists and create if needed
if [[ ! -f ${logFile} ]]; then
	touch ${logFile}
	echo "${timeStamp}" > ${logFile}
fi

# Get the current user
currentUser=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )

# Check for a logged in user and proceed with last user if needed
if [[ $currentUser == "" ]]; then
	# Set currentUser variable to the last logged in user
	currentUser=$( defaults read /Library/Preferences/com.apple.loginwindow lastUserName )
fi

# Check if user is an admin
if /usr/sbin/dseditgroup -o checkmember -m "$currentUser" admin &> /dev/null; then
	# Process admin time
	oldTimeStamp=$(head -1 ${logFile})
	echo "${timeStamp}" >> ${logFile}
	
	adminTime=$((timeStamp - oldTimeStamp))
	
	# If user is admin for more than the time limit, trigger launchDaemon blog.mostlymac.privileges.demote.plist
	# Signal file tells launchDaemon to trigger jamf policy Demote Admin Privileges
	if [[ ${adminTime} -ge ${timeLimit} ]]; then
		touch "${signalFile}"
		sleep 5
		rm "${signalFile}"
	fi
	
else
	# User is not admin. Reset timer and exit
	rm "${logFile}"
fi