#!/bin/bash

# Timelimit in Seconds
timeLimit="900"

# Signal file, must match blog.mostlymac.privileges.demote.plist -> watchpaths
signalFile="/tmp/privilegesDemote"

# Log file which contains the timestamps of the last runs
logFile="/tmp/privilegesCheck"

# Current timestamp
timeStamp=$(date +%s)

# Check if log file exists and create if needed
if [[ ! -f ${logFile} ]]; then
	touch "${logFile}"
	echo ${timeStamp} > ${logFile}
fi

# Get the current user
currentUser=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )

# Check for a logged in user and proceed with last user if needed
if [[ $currentUser == "" ]]; then
	# Set currentUser variable to the last logged in user
	currentUser=$( defaults read /Library/Preferences/com.apple.loginwindow lastUserName )
fi

# Check if user is an admin
admin=$( dseditgroup -o checkmember -m $currentUser admin )

# Set user type variable
if [[ $? = 0 ]]; then
	userType="Admin"
else
	userType="Standard"
	rm "${logFile}"
	exit 0
fi
		
# Process admin time
if [[ "${userType}" == "Admin" ]]; then	
	oldTimeStamp=$(head -1 ${logFile})
	echo ${timeStamp} >> ${logFile}

	adminTime=$((${timeStamp} - ${oldTimeStamp}))
fi
	
# If user is admin for more than the time limit, trigger launchDaemon blog.mostlymac.privileges.demote.plist
# Signal file tells launchDaemon to trigger jamf policy Demote Admin Privileges
if [[ ${adminTime} -ge ${timeLimit} ]]; then
	touch "${signalFile}"
	sleep 5
	rm "${signalFile}"
fi
	