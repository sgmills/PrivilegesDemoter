#!/bin/bash

#########################################
# This removes all of PrivilegesDemoter #
#########################################

# Remove launchDaemon to check for admin every 5 minutes
launchctl bootout system "/Library/LaunchDaemons/blog.mostlymac.privileges.check.plist" 2>/dev/null
launchctl remove "/Library/LaunchDaemons/blog.mostlymac.privileges.check.plist" 2>/dev/null
rm -f "/Library/LaunchDaemons/blog.mostlymac.privileges.check.plist" 2>/dev/null

# Remove launchDaemon to confirm and optionally demote user if time limit is reached
launchctl bootout system "/Library/LaunchDaemons/blog.mostlymac.privileges.demote.plist" 2>/dev/null
launchctl remove "/Library/LaunchDaemons/blog.mostlymac.privileges.demote.plist" 2>/dev/null
rm -f "Library/LaunchDaemons/blog.mostlymac.privileges.demote.plist" 2>/dev/null

# Remove script/folder
rm -rf "/usr/local/mostlymac" 2>/dev/null

# Remove check file
rm "/tmp/privilegesCheck" 2>/dev/null

# Remove demote file
rm "/tmp/privilegesDemote" 2>/dev/null

# Remove cached demotion script
rm -rf "/Library/Application Support/JAMF/Offline Policies/privilegesDemote" 2>/dev/null

# Remove the log rotation config
rm -f "/private/etc/newsyslog.d/blog.mostlymac.PrivilegesDemoter.conf" 2>/dev/null

# Remove logs
rm -f "/var/log/privileges.log"

##########################################################
# Uncomment the following lines to remove SAP Privileges #
##########################################################

# Remove SAP Privileges
#rm -rf "/Applications/Privileges.app"

# Remove SAP Privileges helper
#rm -f "/Library/LaunchDaemons/corp.sap.privileges.helper.plist"