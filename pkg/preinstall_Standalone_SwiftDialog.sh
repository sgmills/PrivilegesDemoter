#!/bin/bash

# Determine working directory
install_dir=$( dirname "$0" )

# Install Swift Dialog in the working directory
/usr/sbin/installer -dumplog -verbose -pkg "$install_dir"/"dialog-2.2.0-4535.pkg" -target "$3"

# Unload launchDaemon to check for admin every 5 minutes
launchctl bootout system /Library/LaunchDaemons/blog.mostlymac.privileges.check.plist 2>/dev/null

# Remove old script/folder
rm -rf /usr/local/mostlymac 2>/dev/null

# Remove check file
rm /tmp/privilegesCheck 2>/dev/null

# Note: All of the following are depricated as of v3. Removing unnecessary bits
# Remove launchDaemon to confirm and optionally demote user if time limit is reached
launchctl bootout system /Library/LaunchDaemons/blog.mostlymac.privileges.demote.plist 2>/dev/null
launchctl remove /Library/LaunchDaemons/blog.mostlymac.privileges.demote.plist 2>/dev/null
rm -f Library/LaunchDaemons/blog.mostlymac.privileges.demote.plist 2>/dev/null

# Remove demote file
rm /tmp/privilegesDemote 2>/dev/null

# Remove cached demotion script
rm -rf "/Library/Application Support/JAMF/Offline Policies/privilegesDemote" 2>/dev/null