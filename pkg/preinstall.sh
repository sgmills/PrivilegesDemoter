#!/bin/bash

# Unload launchDaemon to check for admin every 5 minutes if needed
if launchctl list | grep -q blog.mostlymac.privileges.check; then
	launchctl bootout system /Library/LaunchDaemons/blog.mostlymac.privileges.check.plist
fi

# Unload launchDaemon to confirm and optionally demote user if time limit is reached if needed
if launchctl list | grep -q blog.mostlymac.privileges.demote; then
	launchctl bootout system /Library/LaunchDaemons/blog.mostlymac.privileges.demote.plist
fi

# Remove demote file if needed
if [ -f /tmp/privilegesDemote ]; then
	rm /tmp/privilegesDemote
fi

# Remove check file if needed
if [ -f /tmp/privilegesCheck ]; then
	rm /tmp/privilegesCheck
fi